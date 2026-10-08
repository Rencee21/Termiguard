import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/scan_result.dart';
import '../models/spectrogram_data.dart';
import '../services/esp32_service.dart';
import '../theme/app_theme.dart';
import '../widgets/flow_stepper.dart';
import '../widgets/section_card.dart';
import '../widgets/spectrogram_view.dart';
import 'spectrogram_screen.dart';

/// What the user picked in the "Leave the scan?" dialog.
enum _StopChoice { keepScanning, finish, discard }

/// Step 2 of the flow — a live, real-time scan of the ESP32.
///
/// The scan has NO fixed length: it keeps listening until the user taps
/// "Stop & See Result" (a safety limit of [_maxMs] applies so a
/// forgotten scan can't run forever). The live spectrogram shows the
/// most recent [_windowFrames] columns and scrolls as the scan goes on,
/// while the whole recording is kept and used for the result.
///
/// Everything updates every screen refresh (about 60 times a second):
///  - a click detected by the ESP32 appears on the live spectrogram and
///    the live bars the instant Firebase delivers it;
///  - the timer runs smoothly on a real clock;
///  - the ESP32's own status (peak level, last update) streams in live.
///
/// The ESP32's status readings are also recorded for the WHOLE scan
/// ([_samples]), whether or not any click happens, so clean and noise
/// scans still have real acoustic measurements.
///
/// The scan also stops by itself if the hardware goes offline, so a
/// scan with the ESP32 unplugged can never report a false "no activity".
class ScanningScreen extends StatefulWidget {
  const ScanningScreen({super.key});

  @override
  State<ScanningScreen> createState() => _ScanningScreenState();
}

class _ScanningScreenState extends State<ScanningScreen>
    with SingleTickerProviderStateMixin {
  static const _frameMs = 100; // one spectrogram column = 100 ms
  static const _bins = 32;

  /// The live spectrogram shows the last 16 s (160 columns) and scrolls.
  static const _windowFrames = 160;

  /// Safety limit so a forgotten scan can't grow forever (5 minutes).
  static const _maxFrames = 3000;
  static const _maxMs = _maxFrames * _frameMs;

  /// Stopping before this gives too little data to analyze.
  static const _minMs = 3000;

  final _service = Esp32Service();

  /// The whole recording: one byte per cell, [_bins] rows per column. It
  /// starts small and grows as the scan gets longer.
  Uint8List _cells = Uint8List(300 * _bins);

  /// Every click of this scan, kept with the saved result so it can be
  /// labeled and exported as training data later.
  final List<ScanClick> _clicks = [];

  /// Continuous status readings for the whole scan (independent of
  /// clicks). The acoustic features are calculated from these.
  final List<ScanSample> _samples = [];

  /// The first status snapshot after subscribing is just the last value
  /// stored in Firebase (possibly hours old), so it is not recorded.
  bool _gotFirstStatus = false;

  /// The live bars (latest clicks, fading out smoothly).
  final List<double> _liveBars = List<double>.filled(_bins, 0);

  late final Ticker _ticker;
  StreamSubscription<Esp32Event>? _eventSub;
  StreamSubscription<Esp32Status>? _watchSub;
  StreamSubscription<Esp32Live>? _liveSub;

  bool _stopped = false;
  bool _dialogOpen = false;
  int _elapsedMs = 0;
  Duration _lastTick = Duration.zero;

  int _eventCount = 0;
  Esp32Event? _lastEvent;
  DateTime? _lastEventAt;
  double _peakDb = 0;

  Esp32Live _status = const Esp32Live();
  DateTime? _statusAt;

  @override
  void initState() {
    super.initState();

    _ticker = createTicker(_onTick)..start();

    _eventSub = _service.liveEvents.listen(_onEvent);

    _liveSub = _service.liveStatus().listen((live) {
      _status = live;
      _statusAt = DateTime.now();

      if (!_gotFirstStatus) {
        _gotFirstStatus = true;
        return;
      }
      if (_stopped) return;

      final db = live.peakDb;
      final hz = live.peakFreqHz;
      if (db == null || hz == null) return;
      _samples.add(ScanSample(
        tMs: _elapsedMs,
        peakDb: db,
        peakFreqHz: hz,
        amplitude: live.amplitude,
        rms: live.rms,
        snrDb: live.snrDb,
        hits: live.hits,
        deviceId: Esp32Service.deviceId,
      ));
    });

    _watchSub = _service.watch().listen((status) {
      if (status == Esp32Status.deviceOffline ||
          status == Esp32Status.appOffline ||
          status == Esp32Status.error) {
        _abort(status);
      }
    });
  }

  /// Makes sure the recording buffer has room for [frame].
  void _ensureCapacity(int frame) {
    final needed = (frame + 1) * _bins;
    if (needed <= _cells.length) return;
    final newLength = min(_maxFrames * _bins, max(_cells.length * 2, needed));
    final bigger = Uint8List(newLength);
    bigger.setRange(0, _cells.length, _cells);
    _cells = bigger;
  }

  int get _currentFrame => min(_maxFrames - 1, _elapsedMs ~/ _frameMs);

  /// Runs every screen refresh.
  void _onTick(Duration elapsed) {
    if (_stopped) return;
    _elapsedMs = elapsed.inMilliseconds;
    _ensureCapacity(_currentFrame);

    // Fade the live bars smoothly (half-life 150 ms), independent of
    // the frame rate.
    final dtMs = (elapsed - _lastTick).inMilliseconds;
    _lastTick = elapsed;
    final fade = pow(0.5, dtMs / 150.0).toDouble();
    for (var b = 0; b < _bins; b++) {
      _liveBars[b] *= fade;
    }

    // Safety limit reached (wait if the dialog is open; it finishes on
    // the next tick after the user answers).
    if (_elapsedMs >= _maxMs && !_dialogOpen) {
      _finishScan();
      return;
    }
    setState(() {});
  }

  /// A click arrived from the ESP32: mark it in the current column
  /// straight away (no waiting for the next "frame").
  void _onEvent(Esp32Event e) {
    if (_stopped) return;

    _eventCount++;
    _lastEvent = e;
    _lastEventAt = DateTime.now();
    _peakDb = max(_peakDb, e.peakDb);
    _clicks.add(ScanClick(
      tMs: _elapsedMs,
      peakDb: e.peakDb,
      peakFreqHz: e.peakFreqHz,
      amplitude: e.amplitude,
      rms: e.rms,
      snrDb: e.snrDb,
    ));

    final column = _currentFrame;
    _ensureCapacity(column);
    final bin = SpectrogramData.binForHz(e.peakFreqHz, _bins);

    // Every click the ESP32 reports counts as a hit (>= 0.55); louder
    // ones (45 dB up to ~70 dB) are brighter.
    final level = ((e.peakDb - 45) / 25).clamp(0.0, 1.0).toDouble();
    final amplitude = 0.55 + 0.45 * level;

    for (var d = -1; d <= 1; d++) {
      final b = bin + d;
      if (b < 0 || b >= _bins) continue;
      final v = d == 0 ? amplitude : amplitude * 0.55;
      final byte = (v * 255).round();
      final i = column * _bins + b;
      if (byte > _cells[i]) _cells[i] = byte;
      if (v > _liveBars[b]) _liveBars[b] = v;
    }
  }

  // ------------------------- live readings -------------------------

  /// The last [_windowFrames] columns of the recording, for the live
  /// spectrogram. It fills from the left, then scrolls.
  SpectrogramData get _liveWindow {
    final endFrame = _currentFrame + 1;
    final start = max(0, endFrame - _windowFrames);
    final available = endFrame - start;
    final window = Uint8List(_windowFrames * _bins);
    window.setRange(0, available * _bins, _cells, start * _bins);
    return SpectrogramData(
      frames: _windowFrames,
      bins: _bins,
      frameMs: _frameMs,
      cells: window,
    );
  }

  /// Position of the white "now" line inside the live window.
  double get _playhead => min(1.0, (_elapsedMs / _frameMs) / _windowFrames);

  String get _detectionStatus {
    if (_status.detected) return 'Activity Detected';
    final at = _lastEventAt;
    final recent =
        at != null && DateTime.now().difference(at) < const Duration(seconds: 2);
    return recent ? 'Possible Activity' : 'No Activity';
  }

  String get _currentPeakLabel {
    final db = _status.peakDb;
    final hz = _status.peakFreqHz;
    if (db == null || hz == null) return '—';
    return '${db.toStringAsFixed(1)} dB @ ${hz.round()} Hz';
  }

  /// How long ago the ESP32 last updated its status. Uses the ESP32's
  /// own timestamp when it looks sensible, otherwise when the update
  /// reached this device.
  String get _lastUpdateLabel {
    final now = DateTime.now();
    double? seconds;
    final stamp = _status.lastUpdateMs;
    if (stamp != null) {
      final age = now.millisecondsSinceEpoch - stamp;
      if (age >= -60000 && age <= 3600000) seconds = max(0, age) / 1000;
    }
    final arrived = _statusAt;
    if (seconds == null && arrived != null) {
      seconds = now.difference(arrived).inMilliseconds / 1000;
    }
    return seconds == null ? '—' : '${seconds.toStringAsFixed(1)} s ago';
  }

  String get _timerLabel {
    final total = min(_maxMs, _elapsedMs) ~/ 1000;
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // --------------------------- actions ---------------------------

  void _cancelAll() {
    _ticker.stop();
    _eventSub?.cancel();
    _watchSub?.cancel();
    _liveSub?.cancel();
  }

  /// "Stop & See Result" button: ends the scan and shows the result.
  void _stopAndShowResult() {
    if (_stopped || _dialogOpen) return;
    if (_elapsedMs < _minMs) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Scan a little longer (at least 3 seconds) so '
              'there is enough to analyze.'),
        ),
      );
      return;
    }
    _finishScan();
  }

  /// "Cancel Scan" button / back button: asks what to do. The scan
  /// keeps running behind the dialog until the user answers.
  Future<void> _cancelScan() async {
    if (_stopped || _dialogOpen) return;
    _dialogOpen = true;

    final choice = await showDialog<_StopChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave the scan?'),
        content: const Text(
          'You can keep scanning, stop now and see the result of what was '
          'recorded so far, or discard this scan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_StopChoice.keepScanning),
            child: const Text('Keep scanning'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(_StopChoice.discard),
            child: const Text('Discard scan'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(_StopChoice.finish),
            child: const Text('Stop & see result'),
          ),
        ],
      ),
    );

    _dialogOpen = false;
    // The scan may have been aborted (hardware offline) while the
    // dialog was open.
    if (!mounted || _stopped) return;

    switch (choice) {
      case _StopChoice.finish:
        _stopAndShowResult();
        break;
      case _StopChoice.discard:
        _stopped = true;
        _cancelAll();
        Navigator.of(context).pop();
        break;
      case _StopChoice.keepScanning:
      case null:
        break; // just carry on
    }
  }

  /// The hardware (or this device's connection) dropped mid-scan.
  void _abort(Esp32Status status) {
    if (_stopped || !mounted) return;
    _stopped = true;
    _cancelAll();

    final message = status == Esp32Status.appOffline
        ? 'This device went offline, so the scan was stopped.'
        : status == Esp32Status.error
            ? 'Lost access to Firebase, so the scan was stopped.'
            : 'The Termiguard device stopped sending data, so the scan was '
                'stopped.';

    final messenger = ScaffoldMessenger.of(context);
    // Close the dialog first if it is showing.
    if (_dialogOpen) Navigator.of(context).pop();
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Works out the result from everything recorded and opens the
  /// spectrogram screen.
  void _finishScan() {
    if (_stopped || !mounted) return;
    _stopped = true;
    _cancelAll();

    // How many 100 ms columns were recorded.
    final framesDone =
        max(1, min(_maxFrames, (_elapsedMs / _frameMs).ceil()));
    _ensureCapacity(framesDone - 1);

    // The result is worked out from the recording itself, so what the
    // spectrogram shows and what the result says always agree.
    final spectrogram = SpectrogramData(
      frames: framesDone,
      bins: _bins,
      frameMs: _frameMs,
      cells: Uint8List.fromList(_cells.sublist(0, framesDone * _bins)),
    );
    final analysis = spectrogram.analyze();

    final hits = analysis.bandHits;
    final detected = hits >= kMinHitsToDetect;
    final level = !detected
        ? ActivityLevel.none
        : hits < 8
            ? ActivityLevel.low
            : hits < 16
                ? ActivityLevel.medium
                : ActivityLevel.high;

    // A simple estimate from how many clicks were heard. This is not
    // the output of a trained model.
    final confidence = detected
        ? min(99.0, 55.0 + hits * 4)
        : (hits == 0 ? 95.0 : 80.0);

    final result = ScanResult(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      scanDate: DateTime.now(),
      status: detected ? DetectionStatus.detected : DetectionStatus.notDetected,
      activityLevel: level,
      confidence: confidence,
      scanDuration: spectrogram.duration,
      frequencyResult: analysis.dominantLabel,
      sensorReadings:
          _eventCount == 0 ? 'No clicks' : '${_peakDb.toStringAsFixed(1)} dB peak',
      spectrogram: spectrogram,
      clicks: List<ScanClick>.of(_clicks),
      samples: List<ScanSample>.of(_samples),
    );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => SpectrogramScreen(result: result)),
    );
  }

  @override
  void dispose() {
    _stopped = true;
    _eventSub?.cancel();
    _watchSub?.cancel();
    _liveSub?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancelScan();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Scan')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const FlowStepper(current: 1),
            const SizedBox(height: 20),
            const Text(
              'Termiguard is listening through the sensor microphone for '
              'sounds associated with termite activity. Scan for as long '
              'as you like, then tap "Stop & See Result".',
              style: TextStyle(color: AppColors.mutedText, height: 1.4),
            ),
            const SizedBox(height: 20),

            // ============= LISTENING + TIMER =============
            SectionCard(
              child: Row(
                children: [
                  const Icon(Icons.hearing, color: AppColors.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Listening for audio...',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                      ),
                    ),
                  ),
                  Text(
                    _timerLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ============= LIVE SPECTROGRAM =============
            SectionTitle(
              title: 'Live Spectrogram',
              subtitle: 'Scanning range: $kFrequencyRangeLabel. Shows the '
                  'last 16 seconds. Clicks appear the moment they are '
                  'detected. The white line is "now". Dashed lines mark '
                  'the edges of the reading range.',
            ),
            SectionCard(
              child: SpectrogramView(
                data: _liveWindow,
                height: 170,
                playhead: _playhead,
              ),
            ),
            const SizedBox(height: 16),

            // ============= LIVE BARS + READINGS =============
            LiveSpectrumBars(frame: _liveBars, height: 80),
            const SizedBox(height: 16),
            SectionCard(
              child: Column(
                children: [
                  _ReadingRow('Clicks Detected', '$_eventCount'),
                  const Divider(height: 20),
                  _ReadingRow('Current Peak', _currentPeakLabel),
                  const Divider(height: 20),
                  _ReadingRow('Sensor Last Updated', _lastUpdateLabel),
                  const Divider(height: 20),
                  _ReadingRow('Detection Status', _detectionStatus),
                ],
              ),
            ),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _stopAndShowResult,
                child: const Text('Stop & See Result'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.dangerBorder),
                ),
                onPressed: _cancelScan,
                child: const Text('Cancel Scan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadingRow extends StatelessWidget {
  final String label;
  final String value;
  const _ReadingRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.mutedText)),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}