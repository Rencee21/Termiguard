import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/scan_features.dart';
import '../models/scan_result.dart';
import 'csv_save_result.dart';
import 'web_download.dart';

/// Builds training CSVs from labeled scans.
///
/// Sensor measurements (peak dB, peak frequency, amplitude, rms, snr)
/// come from the readings recorded during the WHOLE scan
/// ([ScanResult.samples]), whether or not any click was detected.
/// Click columns (click_count, click_rate_hz, pulse_rate_hz, gap_*)
/// come from the detected clicks and are a separate thing.
///
/// A cell is left EMPTY (never 0) when the value was not measured, and
/// features_measured says whether real sensor measurements were received.
class ScanExportService {
  static const featureNames = [
    'click_count',
    'click_rate_hz',
    'db_mean',
    'db_max',
    'db_std',
    'freq_mean_hz',
    'freq_median_hz',
    'freq_std_hz',
    'gap_mean_s',
    'gap_std_s',
    'dominant_frequency_hz',
    'amplitude',
    'rms',
    'snr_db',
    'pulse_rate_hz',
    'features_measured',
  ];

  /// Scans that are labeled AND have raw click data.
  static List<ScanResult> exportable(Iterable<ScanResult> scans) =>
      scans.where((s) => s.label != null && s.clicks != null).toList();

  /// One row per scan: the label plus summary features.
  static String featuresCsv(List<ScanResult> scans) {
    final b = StringBuffer(
        'scan_id,scan_date,duration_s,label,${featureNames.join(',')}\n');
    for (final s in scans) {
      b.writeln([
        s.id,
        s.scanDate.toIso8601String(),
        s.scanDuration.inSeconds,
        s.label!.name,
        ..._features(s),
      ].join(','));
    }
    return b.toString();
  }

  /// One row per click: the raw data behind the summary rows.
  static String clicksCsv(List<ScanResult> scans) {
    final b = StringBuffer('scan_id,label,t_ms,peak_db,peak_hz\n');
    for (final s in scans) {
      for (final c in s.clicks!) {
        b.writeln('${s.id},${s.label!.name},${c.tMs},'
            '${c.peakDb.toStringAsFixed(2)},'
            '${c.peakFreqHz.toStringAsFixed(1)}');
      }
    }
    return b.toString();
  }

  /// One row per live ESP32 reading recorded during a scan (independent
  /// of whether a click was detected), in the raw-measurement format:
  /// Timestamp, Device ID, Peak Frequency (Hz), Peak dB, Amplitude,
  /// RMS, SNR (dB), Hits, Label.
  ///
  /// Reads only from [ScanResult.samples] — the same stored records
  /// the rest of the app already relies on — so this always matches
  /// what was actually received from Firebase during the scan. A
  /// field that was never measured for a given reading (e.g. hits or
  /// deviceId on a scan saved before those were recorded) is left
  /// EMPTY, never turned into a fake 0.
  static String readingsCsv(List<ScanResult> scans) {
    final b = StringBuffer('Timestamp,Device ID,Peak Frequency (Hz),'
        'Peak dB,Amplitude,RMS,SNR (dB),Hits,Label\n');
    final stamp = DateFormat('yyyy-MM-dd HH:mm:ss');
    for (final s in scans) {
      final label = s.label?.display ?? '';
      for (final sample in s.samples ?? const <ScanSample>[]) {
        final readingTime =
            s.scanDate.add(Duration(milliseconds: sample.tMs));
        b.writeln([
          stamp.format(readingTime),
          sample.deviceId ?? '',
          sample.peakFreqHz.toStringAsFixed(1),
          sample.peakDb.toStringAsFixed(2),
          sample.amplitude?.toStringAsFixed(1) ?? '',
          sample.rms?.toStringAsFixed(1) ?? '',
          sample.snrDb?.toStringAsFixed(1) ?? '',
          sample.hits?.toString() ?? '',
          label,
        ].join(','));
      }
    }
    return b.toString();
  }

  /// Exports all three CSV files, attempting each independently so a
  /// failure on one doesn't hide whether the other two actually saved.
  ///
  /// Tries a direct, no-dialog save first (Android/web - see
  /// web_download.dart). Only when that isn't available at all (iOS,
  /// desktop native) does it fall back to the share sheet for all three
  /// files together, exactly as before.
  ///
  /// A real failure while saving on Android (or web) is not swallowed:
  /// it's captured per-file in the returned [CsvExportResult] instead of
  /// silently falling back to the share sheet or hiding which file
  /// failed.
  static Future<CsvExportResult> share(List<ScanResult> scans) async {
    // Human-readable, timestamped names, e.g.
    // "Termiguard_Scan_2026-09-25_1225_readings.csv". On Android these
    // are saved via MediaStore, which auto-disambiguates (appending
    // "(1)", "(2)", ...) if a file with the same name already exists
    // in Downloads/Termiguard, so an export never overwrites or deletes
    // one.
    final stamp = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
    final featuresName = 'Termiguard_Scan_${stamp}_features.csv';
    final clicksName = 'Termiguard_Scan_${stamp}_clicks.csv';
    final readingsName = 'Termiguard_Scan_${stamp}_readings.csv';

    final files = <(String, Uint8List)>[
      (featuresName, Uint8List.fromList(utf8.encode(featuresCsv(scans)))),
      (clicksName, Uint8List.fromList(utf8.encode(clicksCsv(scans)))),
      (readingsName, Uint8List.fromList(utf8.encode(readingsCsv(scans)))),
    ];

    final outcomes = <CsvFileOutcome>[];
    SaveMethod? mode;
    var attemptedDirectSave = false;

    for (final (name, bytes) in files) {
      try {
        final saved = await downloadFile(name, bytes);
        if (saved == null) {
          continue; // this platform has no direct-save path at all
        }
        attemptedDirectSave = true;
        mode ??= saved.method;
        outcomes
            .add(CsvFileOutcome(fileName: name, success: true, uri: saved.uri));
      } catch (e) {
        attemptedDirectSave = true;
        outcomes.add(CsvFileOutcome(fileName: name, success: false, error: '$e'));
      }
    }

    if (attemptedDirectSave) {
      return CsvExportResult(
        mode: mode ?? SaveMethod.androidDownloads,
        outcomes: outcomes,
        completed: true,
      );
    }

    // iOS / desktop native: no direct-save path - use the share sheet,
    // exactly as before.
    XFile file(String name, Uint8List bytes) =>
        XFile.fromData(bytes, mimeType: 'text/csv', name: name);

    final result = await SharePlus.instance.share(
      ShareParams(
        subject: 'Termiguard labeled scans',
        files: [for (final (name, bytes) in files) file(name, bytes)],
        fileNameOverrides: [for (final (name, _) in files) name],
      ),
    );

    final shared = result.status != ShareResultStatus.dismissed;
    return CsvExportResult(
      mode: SaveMethod.shareSheet,
      outcomes: [
        for (final (name, _) in files)
          CsvFileOutcome(fileName: name, success: shared),
      ],
      completed: shared,
    );
  }

  // ------------------------------ features ------------------------------

  /// One cell per entry of [featureNames], in the same order. All values
  /// come from [computeScanFeatures]: measurements from the samples
  /// recorded during the scan, click columns from the detected clicks.
  /// `click_count == 0` never changes the measurement columns.
  static List<String> _features(ScanResult s) {
    final f = computeScanFeatures(s);
    return [for (final name in featureNames) _cell(name, f[name])];
  }

  static String _cell(String name, num? v) {
    if (v == null) return ''; // not measured: empty, never a fake 0
    if (name == 'click_count' || name == 'features_measured') {
      return '${v.toInt()}';
    }
    return v.toDouble().toStringAsFixed(3);
  }
}