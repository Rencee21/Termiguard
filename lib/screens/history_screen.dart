import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/scan_result.dart';
import '../services/app_services.dart';
import '../services/csv_save_result.dart';
import '../services/web_download.dart';
import '../theme/app_theme.dart';
import '../widgets/section_card.dart';
import '../widgets/spectrogram_view.dart';
import '../widgets/status_pill.dart';
import 'results_screen.dart';
import 'hardware_screen.dart';
import '../services/scan_export_service.dart';

/// Flutter equivalent of history.php — lists previously saved scans.
/// Backed by [ScanHistoryService], which keeps history in Firebase (so
/// it is never lost and is the same on every platform) with an
/// on-device copy for offline use.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    AppServices.scanHistory.addListener(_onHistoryChanged);
    AppServices.scanHistory.load();
  }

  @override
  void dispose() {
    AppServices.scanHistory.removeListener(_onHistoryChanged);
    super.dispose();
  }

  void _onHistoryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _exportLabeled(List<ScanResult> history) async {
    final exportable = ScanExportService.exportable(history);
    if (exportable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No labeled scans yet. Open a scan and set its '
              'label first.'),
        ),
      );
      return;
    }

    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ScanExportService.share(exportable);
      if (!mounted) return;

      switch (result.mode) {
        case SaveMethod.androidDownloads:
        case SaveMethod.androidLegacyPrivate:
          await _showAndroidResultDialog(result);
          break;
        case SaveMethod.browserDownload:
          messenger.showSnackBar(SnackBar(
            content: Text(
              'CSV downloaded successfully. Saved to your browser\'s '
              'downloads folder:\n'
              '${result.outcomes.map((o) => o.fileName).join(', ')}',
            ),
          ));
          break;
        case SaveMethod.shareSheet:
          messenger.showSnackBar(SnackBar(
            content:
                Text(result.completed ? 'Files shared.' : 'Export cancelled.'),
          ));
          break;
      }
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to save CSV file: $error')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Shows exactly which of the three files saved (and, on real Android
  /// 10+ Downloads/Termiguard saves, lets the user Open/Share each one
  /// right away without needing to leave the app).
  Future<void> _showAndroidResultDialog(CsvExportResult result) async {
    final allOk = result.allSucceeded;
    final isDownloads = result.mode == SaveMethod.androidDownloads;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            allOk ? 'Labeled Scan Exported' : 'Export Partially Completed'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  isDownloads
                      ? 'Location: Downloads/Termiguard'
                      : 'Saved to the app\'s own storage (this Android '
                          'version doesn\'t support saving straight to '
                          'Downloads).',
                  style: const TextStyle(color: AppColors.mutedText),
                ),
              ),
              for (final o in result.outcomes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        o.success ? Icons.check_circle : Icons.error,
                        color: o.success ? Colors.green : Colors.red,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          o.success
                              ? o.fileName
                              : '${o.fileName} — failed to save',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      if (o.success && o.uri != null) ...[
                        TextButton(
                          onPressed: () async {
                            final ok = await openSavedFile(o.uri!);
                            if (!ok && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('No app found to open CSV files.'),
                                ),
                              );
                            }
                          },
                          child: const Text('Open'),
                        ),
                        TextButton(
                          onPressed: () => shareSavedFile(o.uri!),
                          child: const Text('Share'),
                        ),
                      ],
                    ],
                  ),
                ),
              if (result.failed.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Unable to save: '
                    '${result.failed.map((o) => o.fileName).join(', ')}.',
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(ScanResult scan) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this scan?'),
        content: const Text(
          'This removes it from your saved history on every device. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await AppServices.scanHistory.delete(scan.id);
  }

  @override
  Widget build(BuildContext context) {
    final service = AppServices.scanHistory;
    final history = service.history;

    return Scaffold(
      appBar: AppBar(title: const Text('Scan History')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'View previously saved audio scans.',
                style: TextStyle(color: AppColors.mutedText),
              ),
            ),
          ),
          if (service.cloudError != null || service.pendingCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SectionCard(
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_outlined,
                        color: AppColors.mutedText),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        service.cloudError != null
                            ? 'Cloud history is unavailable right now '
                                '(check your internet connection and '
                                'Firebase rules). Showing results saved on '
                                'this device.'
                            : '${service.pendingCount} scan(s) waiting to '
                                'upload. They will sync when you are back '
                                'online.',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.mutedText),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (history.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.ios_share),
                  label: Text(
                    _exporting
                        ? 'Preparing export…'
                        : 'Export Labeled Scans (CSV)',
                  ),
                  onPressed: _exporting ? null : () => _exportLabeled(history),
                ),
              ),
            ),
          Expanded(
            child: history.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No scan history available yet.',
                        style: TextStyle(color: AppColors.mutedText),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: history.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final scan = history[index];
                      return _HistoryTile(
                        scan: scan,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ResultsScreen(result: scan),
                            ),
                          );
                        },
                        onDelete: () => _confirmDelete(scan),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const HardwareScreen()),
                      );
                    },
                    child: const Text('Scan Again'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                    child: const Text('Return Home'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final ScanResult scan;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _HistoryTile({
    required this.scan,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final detected = scan.status == DetectionStatus.detected;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SectionCard(
        child: Row(
          children: [
            // Thumbnail of the recorded spectrogram.
            SizedBox(
              width: 72,
              height: 56,
              child: scan.spectrogram != null
                  ? SpectrogramView(
                      data: scan.spectrogram!,
                      height: 56,
                      showAxes: false,
                      highlightBand: false,
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        color: AppColors.neutralBg,
                        child: const Icon(Icons.graphic_eq,
                            color: AppColors.mutedText),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Audio Scan',
                    style: TextStyle(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('MMM d, yyyy, h:mm a').format(scan.scanDate),
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.mutedText),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      StatusPill(
                        label: detected
                            ? '${scan.activityLevel.label} Activity'
                            : 'No Activity',
                        tone: detected ? PillTone.danger : PillTone.success,
                      ),
                      if (scan.label != null)
                        StatusPill(
                          label: scan.label!.display,
                          tone: PillTone.neutral,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.mutedText),
              onPressed: onDelete,
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }
}