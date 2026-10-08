import 'dart:async';
import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// What the app currently knows about the Termiguard hardware.
enum Esp32Status {
  /// Still working it out (right after opening the screen).
  checking,

  /// Fresh data from the ESP32 is arriving.
  online,

  /// The app is online, but the ESP32 has stopped updating its status
  /// (unplugged, no Wi-Fi, crashed...).
  deviceOffline,

  /// This phone / browser has no connection to Firebase.
  appOffline,

  /// Firebase refused the read (usually the database rules).
  error,
}

/// One click detected by the ESP32 (a child of `.../events`).
///
/// [amplitude], [rms] and [snrDb] are real per-block measurements from
/// the ESP32 firmware (added alongside peakDb/peakFreqHz) — null only
/// for events logged by an older firmware version that didn't send
/// them yet.
class Esp32Event {
  final double peakDb;
  final double peakFreqHz;
  final double? amplitude;
  final double? rms;
  final double? snrDb;

  const Esp32Event({
    required this.peakDb,
    required this.peakFreqHz,
    this.amplitude,
    this.rms,
    this.snrDb,
  });
}

/// The ESP32's live `status` values (any of them may be missing).
///
/// [amplitude], [rms] and [snrDb] are only filled in if the firmware
/// writes them to the status node (keys `amplitude`, `rms`, `snrDb`).
/// [hits] mirrors the ESP32's own hit counter (key `hits`) — the same
/// number shown in the Serial Monitor as e.g. "hits = 3/5".
class Esp32Live {
  final double? peakDb;
  final double? peakFreqHz;
  final double? amplitude;
  final double? rms;
  final double? snrDb;
  final int? hits;
  final bool detected;
  final int? lastUpdateMs;

  const Esp32Live({
    this.peakDb,
    this.peakFreqHz,
    this.amplitude,
    this.rms,
    this.snrDb,
    this.hits,
    this.detected = false,
    this.lastUpdateMs,
  });
}

/// Talks to the ESP32 THROUGH Firebase Realtime Database. The app never
/// connects to the ESP32 directly.
///
/// The ESP32 writes:
///   termite_detector/detector01/status  -> {detected, hits, lastUpdate,
///                                            peakDb, peakFreqHz, uptimeSec}
///   termite_detector/detector01/events/<id> -> {peakDb, peakFreqHz,
///                                            timestamp}   (one per click)
class Esp32Service {
  static const String detectorPath = 'termite_detector/detector01';
  static const String statusPath = '$detectorPath/status';
  static const String eventsPath = '$detectorPath/events';

  /// The hardware's identifier, matching the last path segment of
  /// [detectorPath]. Used to fill "Device ID" in exports so it's clear
  /// which physical unit a reading came from.
  static const String deviceId = 'detector01';

  /// Firebase keeps the last values after the ESP32 is unplugged, so
  /// "data exists" proves nothing. The ESP32 counts as online only while
  /// its status keeps being updated: `lastUpdate` is recent, or the
  /// status values keep changing. Make this longer than the ESP32's
  /// status write interval.
  static const Duration onlineWindow = Duration(seconds: 20);

  /// How long to wait for a first sign of life before saying "offline".
  static const Duration firstCheck = Duration(seconds: 8);

  /// How long the app may take to reach Firebase before it is called
  /// offline.
  static const Duration appGrace = Duration(seconds: 5);

  // One shared instance, so the click feed below is started once (early)
  // and every screen uses the same live connection.
  static final Esp32Service _instance = Esp32Service._();
  factory Esp32Service() => _instance;
  Esp32Service._();

  final FirebaseDatabase _db = FirebaseDatabase.instance;

  final StreamController<Esp32Event> _eventController =
      StreamController<Esp32Event>.broadcast();
  StreamSubscription<DatabaseEvent>? _eventSub;
  bool _feedStarting = false;

  /// Clicks detected by the ESP32, delivered the moment Firebase pushes
  /// them. Only NEW clicks: older events already in the database are
  /// skipped. Push IDs sort by time, so the feed starts after the newest
  /// existing one (no clock comparison needed).
  Stream<Esp32Event> get liveEvents {
    startEventFeed();
    return _eventController.stream;
  }

  /// Starts the click feed. Safe to call any time, any number of times.
  /// Call it EARLY (e.g. when the Connect Hardware screen opens) so the
  /// feed is already running when a scan starts: no start-up delay.
  Future<void> startEventFeed() async {
    if (_eventSub != null || _feedStarting) return;
    _feedStarting = true;
    try {
      final newest = await _db
          .ref(eventsPath)
          .orderByKey()
          .limitToLast(1)
          .get()
          .timeout(const Duration(seconds: 8));

      Query query = _db.ref(eventsPath).orderByKey();
      if (newest.children.isNotEmpty) {
        query = query.startAfter(newest.children.first.key);
      }

      _eventSub = query.onChildAdded.listen(
        (event) {
          final value = event.snapshot.value;
          if (value is! Map) return;
          final db = value['peakDb'];
          final hz = value['peakFreqHz'];
          if (db is num && hz is num) {
            double? asDouble(Object? v) => v is num ? v.toDouble() : null;
            _eventController.add(
              Esp32Event(
                peakDb: db.toDouble(),
                peakFreqHz: hz.toDouble(),
                amplitude: asDouble(value['amplitude']),
                rms: asDouble(value['rms']),
                snrDb: asDouble(value['snrDb']),
              ),
            );
          }
        },
        onError: (Object error) {
          debugPrint('ESP32 EVENTS ERROR: $error');
        },
      );
    } catch (error) {
      // Not started (offline / rules). Do NOT subscribe without the
      // "newest key" marker: that would replay every old event as new.
      debugPrint('ESP32 EVENT FEED NOT STARTED (will retry): $error');
    } finally {
      _feedStarting = false;
    }
  }

  bool _warnedMissingMeasurements = false;

  /// Logs (once) which keys the status node really has if amplitude /
  /// rms / snr are not among them, so a missing field is reported
  /// instead of silently becoming a blank or zero.
  void _warnIfMeasurementsMissing(Map status) {
    if (_warnedMissingMeasurements) return;
    bool has(String a, String b) =>
        status[a] is num || status[b] is num;
    if (has('amplitude', 'amp') && has('rms', 'rms') && has('snrDb', 'snr')) {
      return;
    }
    _warnedMissingMeasurements = true;
    debugPrint('ESP32 STATUS IS MISSING amplitude/rms/snr. '
        'Keys actually present at $statusPath: ${status.keys.toList()}');
  }

  /// The ESP32's current status values, as fast as it writes them.
  Stream<Esp32Live> liveStatus() {
    double? number(Object? x) => x is num ? x.toDouble() : null;

    return _db.ref(statusPath).onValue.map((event) {
      final v = event.snapshot.value;
      if (v is! Map) return const Esp32Live();
      _warnIfMeasurementsMissing(v);
      final stamp = v['lastUpdate'];
      final hitsRaw = v['hits'];
      return Esp32Live(
        peakDb: number(v['peakDb']),
        peakFreqHz: number(v['peakFreqHz']),
        amplitude: number(v['amplitude'] ?? v['amp']),
        rms: number(v['rms']),
        snrDb: number(v['snrDb'] ?? v['snr']),
        hits: hitsRaw is num ? hitsRaw.toInt() : null,
        detected: v['detected'] == true,
        lastUpdateMs: stamp is num ? stamp.toInt() : null,
      );
    });
  }

  /// A live stream of [Esp32Status]. Listen to it to start watching;
  /// cancel the subscription to stop.
  Stream<Esp32Status> watch() {
    StreamSubscription<DatabaseEvent>? connSub;
    StreamSubscription<DatabaseEvent>? dataSub;
    Timer? ticker;
    late final StreamController<Esp32Status> controller;

    void start() {
      final startedAt = DateTime.now();
      var appOnline = false;
      var readError = false;
      String? lastSeen; // the last status snapshot, as text
      DateTime? lastChange; // when the status last CHANGED
      int? stampMs; // the ESP32's own `lastUpdate` (epoch milliseconds)
      Esp32Status? logged;

      int? stampAgeMs() {
        final stamp = stampMs;
        if (stamp == null) return null;
        return DateTime.now().millisecondsSinceEpoch - stamp;
      }

      Esp32Status current() {
        if (readError) return Esp32Status.error;

        final now = DateTime.now();
        final sinceStart = now.difference(startedAt);

        if (!appOnline) {
          return sinceStart < appGrace
              ? Esp32Status.checking
              : Esp32Status.appOffline;
        }

        // 1) The ESP32 stamps every status write with lastUpdate. A
        //    recent stamp means it is alive right now. (A little
        //    tolerance in case this device's clock is slightly behind.)
        final age = stampAgeMs();
        if (age != null && age >= -60000 && age <= onlineWindow.inMilliseconds) {
          return Esp32Status.online;
        }

        // 2) Otherwise, has the status changed recently? (Works even if
        //    the clocks disagree.)
        final changed = lastChange;
        if (changed != null) {
          return now.difference(changed) <= onlineWindow
              ? Esp32Status.online
              : Esp32Status.deviceOffline;
        }

        // Nothing fresh yet: give the ESP32 a fair chance.
        return sinceStart < firstCheck
            ? Esp32Status.checking
            : Esp32Status.deviceOffline;
      }

      void emit() {
        if (controller.isClosed) return;
        final status = current();
        if (status != logged) {
          logged = status;
          final age = stampAgeMs();
          final note = age == null
              ? ''
              : ' (last update ${(age / 1000).toStringAsFixed(0)} s ago)';
          debugPrint('ESP32 STATUS: ${status.name}$note');
        }
        controller.add(status);
      }

      // Is THIS device connected to Firebase?
      connSub = _db.ref('.info/connected').onValue.listen(
        (event) {
          appOnline = event.snapshot.value == true;
          emit();
        },
        onError: (Object error) {
          appOnline = false;
          emit();
        },
      );

      // Is the ESP32 still updating its status?
      dataSub = _db.ref(statusPath).onValue.listen(
        (event) {
          final value = event.snapshot.value;
          if (value is Map) {
            final stamp = value['lastUpdate'];
            stampMs = stamp is num ? stamp.toInt() : null;
          }
          final text = _encode(value);
          // The first snapshot is just whatever was stored last
          // (possibly hours ago), so it only sets a baseline.
          if (lastSeen != null && text != lastSeen) {
            lastChange = DateTime.now();
          }
          lastSeen = text;
          emit();
        },
        onError: (Object error) {
          debugPrint('ESP32 SERVICE ERROR: $error');
          readError = true;
          emit();
        },
      );

      // Re-check every second so "went offline" is noticed even when
      // no new data arrives.
      ticker = Timer.periodic(const Duration(seconds: 1), (_) => emit());
      emit();
    }

    void stop() {
      connSub?.cancel();
      dataSub?.cancel();
      ticker?.cancel();
    }

    controller = StreamController<Esp32Status>(onListen: start, onCancel: stop);
    return controller.stream.distinct();
  }

  static String _encode(Object? value) {
    try {
      return jsonEncode(value);
    } catch (_) {
      return '$value';
    }
  }
}