import 'dart:html' as html;

import 'csv_save_result.dart';

/// Triggers a direct browser download - no share picker, nothing that
/// can be "dismissed". This is the reliable path on desktop web, where
/// the OS share panel (Windows' Share flyout, etc.) is easy to miss or
/// close without picking anything.
Future<SavedFile?> downloadFile(String name, List<int> bytes) async {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)..download = name;
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
  return const SavedFile(SaveMethod.browserDownload);
}

/// Not applicable on web - the browser already handled the download
/// directly, so there's no separate URI to open.
Future<bool> openSavedFile(String uri, {String mimeType = 'text/csv'}) async {
  return false;
}

/// Not applicable on web.
Future<void> shareSavedFile(String uri, {String mimeType = 'text/csv'}) async {}