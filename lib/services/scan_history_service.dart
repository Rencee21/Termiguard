import 'dart:async';
import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/scan_result.dart';
import 'db_paths.dart';

/// Saved scan history, kept in the CLOUD (Firebase Realtime Database)
/// so it survives app restarts, uninstalling, clearing browser data,
/// and works the same on every platform (Android, iOS, web) and every
/// device using the same Firebase project.
///
/// A copy is also kept on the device (shared_preferences) so history
/// still shows while offline. A scan saved while offline waits in a
/// "pending" list and uploads automatically once the connection is
/// back — even if the app was closed in between.
///
/// Each scan is stored as one JSON string at `termiguard_history/<id>`.
class ScanHistoryService extends ChangeNotifier {
  // On-device copies (also where scans from the old, device-only
  // version of the app are found and migrated to the cloud).
  static const _cacheKey = 'termiguard_scan_history';
  static const _pendingKey = 'termiguard_scan_pending';
  static const _migratedKey = 'termiguard_scan_migrated';

  /// How long to wait for the server to confirm a save.
  static const _uploadTimeout = Duration(seconds: 8);

  final List<ScanResult> _history = [];

  /// Scans not yet confirmed as stored in the cloud.
  final Map<String, ScanResult> _pending = {};

  StreamSubscription<DatabaseEvent>? _sub;
  Future<void>? _uploadRun;
  bool _uploadAgain = false;
  bool _loaded = false;
  String? _cloudError;

  List<ScanResult> get history => List.unmodifiable(_history);

  bool get isLoaded => _loaded;

  ScanResult? get latest => _history.isEmpty ? null : _history.first;

  /// Number of scans still waiting to upload.
  int get pendingCount => _pending.length;

  /// Set when the cloud can't be read (offline, or database rules
  /// blocking access). Null when everything is fine.
  String? get cloudError => _cloudError;

  DatabaseReference get _ref => FirebaseDatabase.instance.ref(kHistoryNode);

  /// Shows the on-device copy immediately, then starts listening to
  /// the cloud so history stays up to date (also across devices).
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    await _readLocal();
    notifyListeners();
    _listenToCloud();
  }

  /// Saves a scan. Returns true once the cloud has confirmed it, or
  /// false if it is only stored on this device for now (it will
  /// upload by itself later).
  Future<bool> save(ScanResult result) async {
    _history
      ..removeWhere((e) => e.id == result.id)
      ..add(result)
      ..sort((a, b) => b.scanDate.compareTo(a.scanDate));
    _pending[result.id] = result;
    await _writeLocal();
    await _writePending();
    notifyListeners();

    await _uploadPending();
    notifyListeners();
    return !_pending.containsKey(result.id);
  }

  /// Sets (or clears, with null) the ground-truth label on a saved scan.
  /// Stored locally right away and uploaded to the cloud like any other
  /// change, so it also works offline.
  Future<void> setLabel(String id, ScanLabel? label) async {
    final index = _history.indexWhere((e) => e.id == id);
    if (index == -1) return;

    final updated = _history[index].withLabel(label);
    _history[index] = updated;
    _pending[id] = updated; // queue the change for upload
    await _writeLocal();
    await _writePending();
    notifyListeners();

    await _uploadPending();
    notifyListeners();
  }

  /// Deletes a scan everywhere. (Only called when the user confirms.)
  Future<void> delete(String id) async {
    _history.removeWhere((e) => e.id == id);
    _pending.remove(id);
    await _writeLocal();
    await _writePending();
    notifyListeners();
    try {
      await _ref.child(id).remove().timeout(_uploadTimeout);
    } catch (error) {
      debugPrint('HISTORY DELETE NOT CONFIRMED: $error');
    }
  }

  Future<void> clear() async {
    _history.clear();
    _pending.clear();
    await _writeLocal();
    await _writePending();
    notifyListeners();
    try {
      await _ref.remove().timeout(_uploadTimeout);
    } catch (error) {
      debugPrint('HISTORY CLEAR NOT CONFIRMED: $error');
    }
  }

  // ------------------------------ cloud ------------------------------

  void _listenToCloud() {
    try {
      _sub = _ref.onValue.listen(
        _onCloudSnapshot,
        onError: (Object error) {
          debugPrint('HISTORY CLOUD ERROR: $error');
          _cloudError = '$error';
          notifyListeners();
        },
      );
    } catch (error) {
      debugPrint('HISTORY CLOUD UNAVAILABLE: $error');
      _cloudError = '$error';
      notifyListeners();
    }
  }

  void _onCloudSnapshot(DatabaseEvent event) {
    _cloudError = null;

    final cloud = <String, ScanResult>{};
    for (final child in event.snapshot.children) {
      final value = child.value;
      if (value is! String) continue;
      try {
        final scan =
            ScanResult.fromJson(jsonDecode(value) as Map<String, dynamic>);
        cloud[scan.id] = scan;
      } catch (error) {
        debugPrint('Skipping unreadable history entry ${child.key}: $error');
      }
    }

    // Cloud is the source of truth, plus anything still waiting to
    // upload from this device.
    final merged = <String, ScanResult>{...cloud, ..._pending};
    _history
      ..clear()
      ..addAll(merged.values)
      ..sort((a, b) => b.scanDate.compareTo(a.scanDate));

    _writeLocal();
    notifyListeners();
    _uploadPending();
  }

  /// Uploads everything in [_pending]. Only one run at a time; a call
  /// made during a run makes it go around once more.
  Future<void> _uploadPending() {
    final running = _uploadRun;
    if (running != null) {
      _uploadAgain = true;
      return running;
    }
    final run = _runUploads().whenComplete(() => _uploadRun = null);
    _uploadRun = run;
    return run;
  }

  Future<void> _runUploads() async {
    do {
      _uploadAgain = false;
      for (final scan in _pending.values.toList()) {
        try {
          await _ref
              .child(scan.id)
              .set(jsonEncode(scan.toJson()))
              .timeout(_uploadTimeout);
          // Confirmed by the server: no longer pending.
          _pending.remove(scan.id);
          await _writePending();
        } catch (error) {
          debugPrint('HISTORY UPLOAD NOT CONFIRMED (will retry): $error');
        }
      }
    } while (_uploadAgain);
  }

  // --------------------------- on-device copy ---------------------------

  Future<void> _readLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = _decode(prefs.getString(_cacheKey));
    final pending = _decode(prefs.getString(_pendingKey));

    _pending
      ..clear()
      ..addEntries(pending.map((e) => MapEntry(e.id, e)));

    // One-time: scans saved by the old device-only version get
    // uploaded so they are not stranded on this device.
    if (!(prefs.getBool(_migratedKey) ?? false)) {
      for (final scan in cached) {
        _pending.putIfAbsent(scan.id, () => scan);
      }
      await prefs.setBool(_migratedKey, true);
      await _writePending();
    }

    final byId = <String, ScanResult>{
      for (final e in cached) e.id: e,
      ..._pending,
    };
    _history
      ..clear()
      ..addAll(byId.values)
      ..sort((a, b) => b.scanDate.compareTo(a.scanDate));
  }

  List<ScanResult> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      return ScanResult.decodeList(raw);
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, ScanResult.encodeList(_history));
  }

  Future<void> _writePending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pendingKey,
      ScanResult.encodeList(_pending.values.toList()),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
