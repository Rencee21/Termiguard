import 'package:flutter/material.dart';

import '../models/scan_result.dart';
import '../models/spectrogram_data.dart';
import '../theme/app_theme.dart';
import '../widgets/flow_stepper.dart';
import '../widgets/section_card.dart';
import '../widgets/spectrogram_view.dart';
import '../widgets/status_pill.dart';
import 'results_screen.dart';

// TODO: change this import to the file that defines computeScanFeatures()
// (must be the same file used in results_screen.dart). Example only:
import '../models/scan_features.dart';

/// Step 3 of the flow — the recorded audio drawn as a spectrogram
/// (frequency over time), so termite clicks show up as bright marks
/// inside the highlighted band.
class SpectrogramScreen extends StatelessWidget {
  final ScanResult result;

  const SpectrogramScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final data = result.spectrogram;
    final analysis = data?.analyze();
    final hasBandActivity = (analysis?.bandHits ?? 0) >= kMinHitsToDetect;

    // Real ESP32 measurements, from the SAME function the CSV export and
    // the Results screen use. Scans saved without samples fall back to
    // the previous values.
    final feats = computeScanFeatures(result);
    final domHz = feats['dominant_frequency_hz'];
    final dbMax = feats['db_max'];

    return Scaffold(
      appBar: AppBar(title: const Text('Spectrogram')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const FlowStepper(current: 2),
          const SizedBox(height: 20),
          const Text(
            'Clicks picked up by the sensor during the scan. Bright marks show '
            'when and at what frequency a click was detected.',
            style: TextStyle(color: AppColors.mutedText, height: 1.4),
          ),
          const SizedBox(height: 16),

          if (data == null)
            const SectionCard(
              child: Text('No spectrogram was recorded for this scan.'),
            )
          else ...[
            SpectrogramCard(data: data, height: 240),
            const SizedBox(height: 20),

            // ================= QUICK READ-OUT =================
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusPill(
                    label: hasBandActivity
                        ? 'Activity pattern in 0.5 kHz – 20 kHz band'
                        : 'No activity in 0.5 kHz – 20 kHz band',
                    tone: hasBandActivity ? PillTone.danger : PillTone.success,
                  ),
                  const SizedBox(height: 14),
                  _StatRow('Clicks in Band', '${analysis!.bandHits}'),
                  const Divider(height: 20),
                  _StatRow(
                    'Dominant Frequency',
                    domHz != null
                        ? '${domHz.toStringAsFixed(1)} Hz'
                        : analysis.dominantLabel,
                  ),
                  const Divider(height: 20),
                  _StatRow(
                    'Peak Level',
                    dbMax != null
                        ? '${dbMax.toStringAsFixed(1)} dB peak'
                        : result.sensorReadings,
                  ),
                  const Divider(height: 20),
                  _StatRow('Recording Length', result.durationLabel),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),

          // ===================== ACTIONS =====================
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Scan Again'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) =>
                            ResultsScreen(result: result, fromScan: true),
                      ),
                    );
                  },
                  child: const Text('View Result'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.mutedText)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}