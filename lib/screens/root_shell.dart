import 'package:flutter/material.dart';

import '../models/scan_result.dart';
import '../services/app_services.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'results_screen.dart';
import 'hardware_screen.dart';

/// Flutter equivalent of includes/navigation.php — a persistent
/// bottom navigation bar for Home / Scan / Results / History. The
/// Scan tab is the start of the scan flow (Connect Hardware -> Scan ->
/// Spectrogram -> Result); the later steps open on top of it.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    AppServices.scanHistory.load();
  }

  void _goToScan() => setState(() => _index = 1);

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(onScanPressed: _goToScan),
      const HardwareScreen(),
      const _LatestResultOrEmpty(),
      const HistoryScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.qr_code_scanner_outlined), label: 'Scan Wood'),
          BottomNavigationBarItem(
              icon: Icon(Icons.fact_check_outlined), label: 'Results'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
        ],
      ),
    );
  }
}

/// The "Results" tab: shows the most recent saved scan, or an empty
/// state if the user hasn't completed/saved one yet (there is no
/// scan result to show until a scan has been run and saved).
class _LatestResultOrEmpty extends StatefulWidget {
  const _LatestResultOrEmpty();

  @override
  State<_LatestResultOrEmpty> createState() => _LatestResultOrEmptyState();
}

class _LatestResultOrEmptyState extends State<_LatestResultOrEmpty> {
  @override
  void initState() {
    super.initState();
    AppServices.scanHistory.addListener(_onChanged);
  }

  @override
  void dispose() {
    AppServices.scanHistory.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ScanResult? latest = AppServices.scanHistory.latest;
    if (latest == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Scan Results')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.fact_check_outlined, size: 40, color: Colors.grey),
                const SizedBox(height: 12),
                const Text(
                  'No scan results yet.\nRun a scan to see results here.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HardwareScreen()),
                  ),
                  child: const Text('Scan Wood'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return ResultsScreen(result: latest);
  }
}
