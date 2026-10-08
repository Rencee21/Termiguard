import 'dart:math';

import 'scan_result.dart';

/// Five numbers computed from a scan's clicks, named and scaled to line
/// up with the columns used in the thesis's ML notebook
/// (dominant_frequency_hz, amplitude, rms, snr_db, pulse_rate_hz).
///
/// [amplitude], [rms] and [snrDb] use the ESP32's own real per-block
/// measurements (added to the firmware) when the clicks have them.
/// [isMeasured] tells you which: true once every click in the scan
/// carries real values, false if any of them fall back to an
/// after-the-fact estimate from peak dB alone (older firmware, or a
/// scan recorded before the firmware update).
class AudioFeatures {
  /// Peak amplitude of the raw waveform (ESP32: ADC counts, DC
  /// removed), averaged over the scan's clicks — or, when not
  /// measured, an estimate from peak dB, 45 dB -> 0, 70 dB -> 1.
  final double amplitude;

  /// RMS of the raw waveform, averaged over the scan's clicks — or,
  /// when not measured, the RMS of the same dB-based estimate.
  final double rms;

  /// In-band peak vs. out-of-band noise floor, in dB, averaged over
  /// the scan's clicks — or, when not measured, the loudest click's
  /// level minus the quietest click's level (a rougher proxy).
  final double snrDb;

  /// Clicks per second over the whole scan. Always a real, direct
  /// count — nothing to measure on the ESP32 for this one.
  final double pulseRateHz;

  /// The frequency bin with the most total energy across the scan.
  /// Always real — computed from the FFT peak, same as on the device.
  final double dominantFrequencyHz;

  /// True if amplitude/rms/snrDb above are the ESP32's real
  /// measurements; false if any of them are the older dB-based proxy.
  final bool isMeasured;

  const AudioFeatures({
    required this.amplitude,
    required this.rms,
    required this.snrDb,
    required this.pulseRateHz,
    required this.dominantFrequencyHz,
    required this.isMeasured,
  });

  static const _dbFloor = 45.0;
  static const _dbCeiling = 70.0;

  static double _levelOf(double peakDb) =>
      ((peakDb - _dbFloor) / (_dbCeiling - _dbFloor)).clamp(0.0, 1.0);

  static double _mean(List<double> v) =>
      v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

  /// Computes features from a scan. [dominantFrequencyHz], when given
  /// (e.g. from the recorded spectrogram), is used as-is so the app and
  /// the export always agree; otherwise it falls back to the mean of
  /// the clicks' own peak frequencies.
  factory AudioFeatures.fromScan(
    ScanResult scan, {
    double? dominantFrequencyHz,
  }) {
    final clicks = scan.clicks ?? const <ScanClick>[];
    final secs = scan.scanDuration.inMilliseconds / 1000.0;
    final pulseRateHz = secs > 0 ? clicks.length / secs : 0.0;

    if (clicks.isEmpty) {
      return AudioFeatures(
        amplitude: 0,
        rms: 0,
        snrDb: 0,
        pulseRateHz: pulseRateHz,
        dominantFrequencyHz: dominantFrequencyHz ?? 0,
        isMeasured: false,
      );
    }

    final freq = dominantFrequencyHz ??
        _mean([for (final c in clicks) c.peakFreqHz]);

    final measured =
        clicks.every((c) => c.amplitude != null && c.rms != null && c.snrDb != null);

    if (measured) {
      return AudioFeatures(
        amplitude: _mean([for (final c in clicks) c.amplitude!]),
        rms: _mean([for (final c in clicks) c.rms!]),
        snrDb: _mean([for (final c in clicks) c.snrDb!]),
        pulseRateHz: pulseRateHz,
        dominantFrequencyHz: freq,
        isMeasured: true,
      );
    }

    // Fallback proxy, for scans recorded before the firmware sent real
    // amplitude/rms/snrDb.
    final levels = [for (final c in clicks) _levelOf(c.peakDb)];
    final dbs = [for (final c in clicks) c.peakDb];
    final rmsProxy = sqrt(_mean([for (final v in levels) v * v]));
    final snrProxy = dbs.reduce(max) - dbs.reduce(min);

    return AudioFeatures(
      amplitude: _mean(levels),
      rms: rmsProxy,
      snrDb: snrProxy,
      pulseRateHz: pulseRateHz,
      dominantFrequencyHz: freq,
      isMeasured: false,
    );
  }

  String get amplitudeLabel => amplitude.toStringAsFixed(3);
  String get rmsLabel => rms.toStringAsFixed(3);
  String get snrLabel => '${snrDb.toStringAsFixed(1)} dB';
  String get pulseRateLabel => '${pulseRateHz.toStringAsFixed(2)} Hz';
  String get dominantFrequencyLabel => '${dominantFrequencyHz.round()} Hz';
}