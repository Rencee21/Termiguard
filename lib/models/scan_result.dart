import 'dart:convert';

import 'spectrogram_data.dart';

enum DetectionStatus { detected, notDetected }

enum ActivityLevel { none, low, medium, high }

/// Ground-truth tag you give a scan, used only for building a training set.
enum ScanLabel { termite, clean, noise }

extension ScanLabelX on ScanLabel {
  String get display {
    switch (this) {
      case ScanLabel.termite:
        return 'Termite';
      case ScanLabel.clean:
        return 'Clean wood';
      case ScanLabel.noise:
        return 'Background noise';
    }
  }
}

/// One click reported by the ESP32 during a scan.
///
/// [amplitude], [rms] and [snrDb] are real measurements from the ESP32
/// firmware (peak amplitude and RMS of the raw waveform, and SNR from
/// the FFT spectrum) — null only for clicks recorded before the
/// firmware was updated to send them.
class ScanClick {
  final int tMs; // milliseconds since the scan started
  final double peakDb;
  final double peakFreqHz;
  final double? amplitude;
  final double? rms;
  final double? snrDb;

  const ScanClick({
    required this.tMs,
    required this.peakDb,
    required this.peakFreqHz,
    this.amplitude,
    this.rms,
    this.snrDb,
  });

  Map<String, dynamic> toJson() => {
        't': tMs,
        'db': peakDb,
        'hz': peakFreqHz,
        if (amplitude != null) 'amp': amplitude,
        if (rms != null) 'rms': rms,
        if (snrDb != null) 'snr': snrDb,
      };

  factory ScanClick.fromJson(Map<String, dynamic> json) => ScanClick(
        tMs: (json['t'] as num).toInt(),
        peakDb: (json['db'] as num).toDouble(),
        peakFreqHz: (json['hz'] as num).toDouble(),
        amplitude: (json['amp'] as num?)?.toDouble(),
        rms: (json['rms'] as num?)?.toDouble(),
        snrDb: (json['snr'] as num?)?.toDouble(),
      );
}

/// One reading of the ESP32's live status during a scan, recorded
/// whether or not a click happened. These are what the acoustic
/// features (db, frequency, amplitude, rms, snr) are calculated from,
/// so a clean or noise scan still has real measurements.
///
/// [hits] and [deviceId] are only present for readings recorded after
/// this field was added — null for older saved scans, which is
/// rendered as an empty CSV cell rather than a fake 0.
class ScanSample {
  final int tMs; // milliseconds since the scan started
  final double peakDb;
  final double peakFreqHz;
  final double? amplitude;
  final double? rms;
  final double? snrDb;
  final int? hits;
  final String? deviceId;

  const ScanSample({
    required this.tMs,
    required this.peakDb,
    required this.peakFreqHz,
    this.amplitude,
    this.rms,
    this.snrDb,
    this.hits,
    this.deviceId,
  });

  Map<String, dynamic> toJson() => {
        't': tMs,
        'db': peakDb,
        'hz': peakFreqHz,
        if (amplitude != null) 'amp': amplitude,
        if (rms != null) 'rms': rms,
        if (snrDb != null) 'snr': snrDb,
        if (hits != null) 'hits': hits,
        if (deviceId != null) 'deviceId': deviceId,
      };

  factory ScanSample.fromJson(Map<String, dynamic> json) => ScanSample(
        tMs: (json['t'] as num).toInt(),
        peakDb: (json['db'] as num).toDouble(),
        peakFreqHz: (json['hz'] as num).toDouble(),
        amplitude: (json['amp'] as num?)?.toDouble(),
        rms: (json['rms'] as num?)?.toDouble(),
        snrDb: (json['snr'] as num?)?.toDouble(),
        hits: (json['hits'] as num?)?.toInt(),
        deviceId: json['deviceId'] as String?,
      );
}

extension ActivityLevelX on ActivityLevel {
  String get label {
    switch (this) {
      case ActivityLevel.none:
        return 'None';
      case ActivityLevel.low:
        return 'Low';
      case ActivityLevel.medium:
        return 'Medium';
      case ActivityLevel.high:
        return 'High';
    }
  }
}

/// One completed audio scan: the detection result plus the recorded
/// spectrogram. This is what gets saved to (and shown from) history.
class ScanResult {
  final String id;
  final DateTime scanDate;
  final DetectionStatus status;
  final ActivityLevel activityLevel;
  final double confidence; // percent, e.g. 87.5
  final Duration scanDuration;
  final String frequencyResult; // dominant frequency, e.g. "4125 Hz"
  final String sensorReadings; // peak level, e.g. "64.9 dB peak"

  /// The recorded audio, drawn as a spectrogram. Null only for scans
  /// saved by older versions of the app (which had no spectrogram).
  final SpectrogramData? spectrogram;

  /// Your ground-truth tag for this scan (null = not labeled yet).
  final ScanLabel? label;

  /// Raw clicks the ESP32 reported. Null for scans saved before this
  /// was recorded; an empty list means the scan really had no clicks.
  final List<ScanClick>? clicks;

  /// Continuous status readings taken during the whole scan, whether or
  /// not any click happened. Null for scans saved before this was
  /// recorded (they have no measurement data).
  final List<ScanSample>? samples;

  ScanResult({
    required this.id,
    required this.scanDate,
    required this.status,
    required this.activityLevel,
    required this.confidence,
    required this.scanDuration,
    required this.frequencyResult,
    required this.sensorReadings,
    this.spectrogram,
    this.label,
    this.clicks,
    this.samples,
  });

  /// A copy with a different label (pass null to clear it).
  ScanResult withLabel(ScanLabel? newLabel) => ScanResult(
        id: id,
        scanDate: scanDate,
        status: status,
        activityLevel: activityLevel,
        confidence: confidence,
        scanDuration: scanDuration,
        frequencyResult: frequencyResult,
        sensorReadings: sensorReadings,
        spectrogram: spectrogram,
        label: newLabel,
        clicks: clicks,
        samples: samples,
      );

  String get detectionResultLabel => status == DetectionStatus.detected
      ? 'Termite Activity Detected'
      : 'No Termite Activity Detected';

  String get durationLabel {
    final m = scanDuration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = scanDuration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'scanDate': scanDate.toIso8601String(),
        'status': status.name,
        'activityLevel': activityLevel.name,
        'confidence': confidence,
        'scanDurationSeconds': scanDuration.inSeconds,
        'frequencyResult': frequencyResult,
        'sensorReadings': sensorReadings,
        'spectrogram': spectrogram?.toJson(),
        'label': label?.name,
        'clicks': clicks?.map((c) => c.toJson()).toList(),
        'samples': samples?.map((s) => s.toJson()).toList(),
      };

  factory ScanResult.fromJson(Map<String, dynamic> json) => ScanResult(
        id: json['id'] as String,
        scanDate: DateTime.parse(json['scanDate'] as String),
        status: DetectionStatus.values.byName(json['status'] as String),
        activityLevel:
            ActivityLevel.values.byName(json['activityLevel'] as String),
        confidence: (json['confidence'] as num).toDouble(),
        scanDuration: Duration(seconds: json['scanDurationSeconds'] as int),
        frequencyResult: json['frequencyResult'] as String,
        sensorReadings: json['sensorReadings'] as String,
        spectrogram: json['spectrogram'] == null
            ? null
            : SpectrogramData.fromJson(
                json['spectrogram'] as Map<String, dynamic>),
        label: json['label'] == null
            ? null
            : ScanLabel.values.byName(json['label'] as String),
        clicks: json['clicks'] == null
            ? null
            : (json['clicks'] as List<dynamic>)
                .map((e) => ScanClick.fromJson(e as Map<String, dynamic>))
                .toList(),
        samples: json['samples'] == null
            ? null
            : (json['samples'] as List<dynamic>)
                .map((e) => ScanSample.fromJson(e as Map<String, dynamic>))
                .toList(),
      );

  static String encodeList(List<ScanResult> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<ScanResult> decodeList(String source) {
    final decoded = jsonDecode(source) as List<dynamic>;
    return decoded
        .map((e) => ScanResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

enum HardwareState { checking, connected, disconnected }

class HardwareDevice {
  final String id;
  final String name;
  HardwareState state;

  HardwareDevice({
    required this.id,
    required this.name,
    this.state = HardwareState.checking,
  });
}