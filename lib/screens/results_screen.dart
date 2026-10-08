import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/scan_result.dart';
import '../models/spectrogram_data.dart';
import '../services/app_services.dart';
import '../theme/app_theme.dart';
import '../widgets/flow_stepper.dart';
import '../widgets/section_card.dart';
import '../widgets/spectrogram_view.dart';
import 'history_screen.dart';
import 'hardware_screen.dart';
import '../widgets/scan_label_picker.dart';

// TODO: change this import to the file that defines computeScanFeatures()
// (the same function the CSV export uses). Example only:
import '../models/scan_features.dart';

/// Step 4 of the flow (Flutter equivalent of results.php) — the final
/// detection result, the recorded spectrogram, a scan summary, and
/// follow-up actions. Also used to re-open a saved scan from History.
class ResultsScreen extends StatefulWidget {
  final ScanResult result;

  /// True when reached at the end of a scan (shows the step tracker).
  final bool fromScan;

  const ResultsScreen({super.key, required this.result, this.fromScan = false});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  bool _saved = false;
  bool _saving = false;
  ScanLabel? _label;

  @override
  void initState() {
    super.initState();
    _saved =
        AppServices.scanHistory.history.any((e) => e.id == widget.result.id);
    _label = widget.result.label;
    // A scan that has just finished is saved to history automatically,
    // so a result is never lost just because "Save" wasn't tapped.
    if (widget.fromScan && !_saved) {
      _saving = true;
      _runSave();
    }
  }

  /// The "Save Result" button (used to retry if the automatic save
  /// could not finish).
  void _saveResult() {
    setState(() => _saving = true);
    _runSave();
  }

  Future<void> _runSave() async {
    // ---- TEMP DEBUG: remove once the CSV is verified ----
    final r = widget.result;
    final last = (r.samples?.isNotEmpty ?? false) ? r.samples!.last : null;
    debugPrint('CSV DATA BEFORE SAVE:');
    debugPrint('scan id: ${r.id}');
    debugPrint('samples: ${r.samples?.length}  clicks: ${r.clicks?.length}');
    if (last != null) {
      debugPrint('last sample -> db:${last.peakDb} hz:${last.peakFreqHz} '
          'amp:${last.amplitude} rms:${last.rms} snr:${last.snrDb} '
          'hits:${last.hits} device:${last.deviceId}');
    }
    debugPrint('features: ${computeScanFeatures(r)}');
    // ---- END TEMP DEBUG ----

    final inCloud = await AppServices.scanHistory.save(widget.result);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          inCloud
              ? 'Scan result saved to history.'
              : 'Saved on this device. It will upload when you are back online.',
        ),
      ),
    );
  }

  Future<void> _onLabelChanged(ScanLabel? label) async {
    setState(() => _label = label);
    // Labeling only makes sense once the scan is saved (it needs an id
    // in history to attach to).
    if (!_saved) await _runSave();
    await AppServices.scanHistory.setLabel(widget.result.id, label);
  }

  /// Starts a new scan at "Connect Hardware". Replaces this screen when
  /// it was pushed (so Back doesn't return to a stale result); pushes
  /// on top when this screen is the Results tab.
  void _scanAgain() {
    final nav = Navigator.of(context);
    final route = MaterialPageRoute(builder: (_) => const HardwareScreen());
    if (nav.canPop()) {
      nav.pushReplacement(route);
    } else {
      nav.push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final analysis = r.spectrogram?.analyze();
    final detected = r.status == DetectionStatus.detected;
    final dateLabel = DateFormat('MMM d, yyyy, h:mm a').format(r.scanDate);

    // Real ESP32 measurements, from the SAME function the CSV export uses.
    // Older scans saved without samples fall back to the stored text.
    final feats = computeScanFeatures(r);
    final domHz = feats['dominant_frequency_hz'];
    final dbMax = feats['db_max'];
    final dominantLabel =
        domHz != null ? '${domHz.toStringAsFixed(1)} Hz' : r.frequencyResult;
    final peakLabel =
        dbMax != null ? '${dbMax.toStringAsFixed(1)} dB peak' : r.sensorReadings;

    // Activity level plus the real click count / rate behind it.
    // (Skipped for very old scans that never recorded clicks.)
    String activityDetail = r.activityLevel.label;
    if (r.clicks != null) {
      final clickCount = (feats['click_count'] ?? 0).toInt();
      final clickRate = feats['click_rate_hz'] ?? 0;
      activityDetail = '${r.activityLevel.label} · $clickCount '
          'click${clickCount == 1 ? '' : 's'} · '
          '${clickRate.toStringAsFixed(2)}/s';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Scan Results')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.fromScan) ...[
            const FlowStepper(current: 3),
            const SizedBox(height: 20),
          ],

          // ===================== RESULT CARD =====================
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      detected ? Icons.warning_amber_rounded : Icons.verified_outlined,
                      color: detected ? AppColors.danger : AppColors.success,
                      size: 26,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.detectionResultLabel,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: detected ? AppColors.danger : AppColors.success,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 20,
                  runSpacing: 12,
                  children: [
                    _DetailItem('Activity Level', r.activityLevel.label),
                    _DetailItem(
                        'Detection Confidence', '${r.confidence.toStringAsFixed(1)}%'),
                    _DetailItem('Scan Duration', r.durationLabel),
                    _DetailItem('Date & Time', dateLabel),
                    _DetailItem('Dominant Frequency', dominantLabel),
                    _DetailItem('Peak Level', peakLabel),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ===================== SPECTROGRAM =====================
          const SectionTitle(
            title: 'Audio Spectrogram',
            subtitle: 'The audio recorded during this scan, shown as '
                'frequency over time.',
          ),
          if (r.spectrogram != null)
            SpectrogramCard(data: r.spectrogram!)
          else
            const SectionCard(
              child: Text(
                'No spectrogram was saved for this scan.',
                style: TextStyle(color: AppColors.mutedText),
              ),
            ),
          const SizedBox(height: 24),

          // ===================== AUDIO FEATURES (FOR ML) =====================
          // Uses computeScanFeatures(), the SAME function the CSV export
          // uses, so what is shown here is what is exported.
          if (r.clicks != null || r.samples != null) ...[
            const SectionTitle(
              title: 'Audio Features',
              subtitle: 'Computed from this scan\'s ESP32 sensor readings, '
                  'for use as ML training columns.',
            ),
            SectionCard(
              child: Builder(builder: (context) {
                final f = feats;
                final measured = f['features_measured'] == 1;
                String fmt(num? v, [int digits = 3]) =>
                    v == null ? '—' : v.toStringAsFixed(digits);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        measured
                            ? 'Amplitude, RMS and SNR are the ESP32\'s own '
                                'measurements for this scan.'
                            : 'No complete ESP32 sensor readings were '
                                'recorded for this scan.',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: measured
                              ? AppColors.success
                              : AppColors.mutedText,
                        ),
                      ),
                    ),
                    _SummaryRow('Amplitude', fmt(f['amplitude'])),
                    _SummaryRow('RMS', fmt(f['rms'])),
                    _SummaryRow('SNR', '${fmt(f['snr_db'], 1)} dB'),
                    _SummaryRow('Pulse Rate', '${fmt(f['pulse_rate_hz'], 2)} Hz'),
                    _SummaryRow(
                      'Dominant Frequency',
                      '${fmt(f['dominant_frequency_hz'], 0)} Hz',
                      isLast: true,
                    ),
                  ],
                );
              }),
            ),
            const SizedBox(height: 24),
          ],

          // ===================== LABEL FOR TRAINING =====================
          if (r.clicks != null) ...[
            const SectionTitle(
              title: 'Label This Scan',
              subtitle: 'Tag what this scan really was, so it can be used '
                  'as labeled training data.',
            ),
            SectionCard(
              child: ScanLabelPicker(
                initial: _label,
                onChanged: _onLabelChanged,
              ),
            ),
            const SizedBox(height: 24),
          ],

          // ===================== SCAN SUMMARY =====================
          const SectionTitle(title: 'Scan Summary'),
          SectionCard(
            child: Column(
              children: [
                _SummaryRow('Scan Date', DateFormat('MMM d, yyyy').format(r.scanDate)),
                _SummaryRow('Scan Duration', r.durationLabel),
                _SummaryRow('Detected Activity', detected ? 'Yes' : 'No'),
                _SummaryRow('Maximum Activity Level', activityDetail),
                if (analysis != null)
                  _SummaryRow('Clicks in 0.5 kHz – 20 kHz Band', '${analysis.bandHits}'),
                _SummaryRow('Peak Level', peakLabel),
                _SummaryRow('Dominant Frequency', dominantLabel),
                _SummaryRow('Detection Result', r.detectionResultLabel, isLast: true),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ===================== ACTION BUTTONS =====================
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _scanAgain,
              child: const Text('Scan Again'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: (_saved || _saving) ? null : _saveResult,
              child: Text(
                _saved
                    ? 'Saved to History'
                    : _saving
                        ? 'Saving…'
                        : 'Save Result',
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                );
              },
              child: const Text('View Scan History'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              child: const Text('Return Home'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailItem extends StatelessWidget {
  final String label;
  final String value;
  const _DetailItem(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: AppColors.mutedText)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;
  const _SummaryRow(this.label, this.value, {this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: AppColors.mutedText)),
          ),
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.w600),
              textAlign: TextAlign.right),
        ],
      ),
    );
  }
}