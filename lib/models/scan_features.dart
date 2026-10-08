import 'dart:math';

import 'scan_result.dart';

/// The single place that turns a scan's raw ESP32 readings into named
/// feature columns — used by the Results screen, the Spectrogram
/// screen, and (should be) the CSV exporter, so what you see in the app
/// always matches what gets exported for training.
///
/// Source of the acoustic numbers (db_*, freq_*, amplitude, rms,
/// snr_db): prefers [ScanResult.samples] — continuous status readings
/// taken for the WHOLE scan, present even when nothing was
/// "detected" — so a clean or noise scan still gets real numbers.
/// Falls back to [ScanResult.clicks] only for older scans saved before
/// samples were recorded. If a scan has neither, every acoustic key is
/// null (shown as "—" in the UI, blank in CSV — never a fake 0).
///
/// click_count / click_rate_hz always come from [ScanResult.clicks]
/// specifically (the real detected events), regardless of which source
/// the acoustic numbers came from — a quiet scan can have plenty of
/// samples but zero clicks, and that distinction matters.
///
/// features_measured is 1 only if every reading used for the acoustic
/// numbers had real amplitude/rms/snrDb from the firmware (not null) —
/// 0 if any of them were missing (older firmware).
Map<String, num?> computeScanFeatures(ScanResult r) {
  final clicks = r.clicks;
  final durationS = r.scanDuration.inMilliseconds / 1000.0;

  final clickCount = clicks?.length ?? 0;
  final clickRateHz = durationS > 0 ? clickCount / durationS : 0.0;

  // ---- pick the acoustic-data source: samples first, then clicks ----
  final samples = r.samples;
  List<double> dbs;
  List<double> hzs;
  List<double?> amps;
  List<double?> rmss;
  List<double?> snrs;

  if (samples != null && samples.isNotEmpty) {
    dbs = [for (final s in samples) s.peakDb];
    hzs = [for (final s in samples) s.peakFreqHz];
    amps = [for (final s in samples) s.amplitude];
    rmss = [for (final s in samples) s.rms];
    snrs = [for (final s in samples) s.snrDb];
  } else if (clicks != null && clicks.isNotEmpty) {
    dbs = [for (final c in clicks) c.peakDb];
    hzs = [for (final c in clicks) c.peakFreqHz];
    amps = [for (final c in clicks) c.amplitude];
    rmss = [for (final c in clicks) c.rms];
    snrs = [for (final c in clicks) c.snrDb];
  } else {
    // No samples AND no clicks at all: nothing acoustic to compute.
    return {
      'click_count': clickCount,
      'click_rate_hz': clickRateHz,
      'pulse_rate_hz': clickRateHz,
      'db_mean': null,
      'db_max': null,
      'db_std': null,
      'freq_mean_hz': null,
      'freq_median_hz': null,
      'freq_std_hz': null,
      'dominant_frequency_hz': null,
      'amplitude': null,
      'rms': null,
      'snr_db': null,
      'features_measured': 0,
    };
  }

  // ---- gaps between consecutive real clicks (timing only, not tied
  // to whichever source the acoustic numbers came from) ----
  final gapS = <double>[];
  if (clicks != null && clicks.length > 1) {
    final times = clicks.map((c) => c.tMs).toList()..sort();
    for (var i = 1; i < times.length; i++) {
      gapS.add((times[i] - times[i - 1]) / 1000.0);
    }
  }

  final realAmps = [for (final a in amps) if (a != null) a];
  final realRms = [for (final v in rmss) if (v != null) v];
  final realSnr = [for (final v in snrs) if (v != null) v];
  final allMeasured =
      realAmps.length == amps.length && realRms.length == rmss.length &&
      realSnr.length == snrs.length && amps.isNotEmpty;

  return {
    'click_count': clickCount,
    'click_rate_hz': clickRateHz,
    'pulse_rate_hz': clickRateHz,
    'db_mean': _mean(dbs),
    'db_max': dbs.isEmpty ? null : dbs.reduce(max),
    'db_std': _std(dbs),
    'freq_mean_hz': _mean(hzs),
    'freq_median_hz': _median(hzs),
    'freq_std_hz': _std(hzs),
    'dominant_frequency_hz': _mean(hzs),
    'amplitude': realAmps.isEmpty ? null : _mean(realAmps),
    'rms': realRms.isEmpty ? null : _mean(realRms),
    'snr_db': realSnr.isEmpty ? null : _mean(realSnr),
    'gap_mean_s': _mean(gapS),
    'gap_std_s': _std(gapS),
    'features_measured': allMeasured ? 1 : 0,
  };
}

double? _mean(List<double> v) =>
    v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;

double? _std(List<double> v) {
  if (v.length < 2) return v.isEmpty ? null : 0.0;
  final m = _mean(v)!;
  final variance =
      v.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / v.length;
  return sqrt(variance);
}

double? _median(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}