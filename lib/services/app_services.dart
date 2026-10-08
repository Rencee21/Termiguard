import 'scan_history_service.dart';

/// A tiny service locator so screens deep in the navigation stack
/// (Results, History) can reach the same [ScanHistoryService]
/// instance without adding a state-management package. Initialized
/// once in main() before runApp().
class AppServices {
  AppServices._();

  static final ScanHistoryService scanHistory = ScanHistoryService();
}
