import 'dart:io' show Platform;

import 'package:file_saver/file_saver.dart';
import 'package:flutter/services.dart';

import 'csv_save_result.dart';

/// Talks to the small native helper added in MainActivity.kt.
/// See MainActivity.kt for the other half of this channel.
const _channel = MethodChannel('com.termiguard.app/csv_export');

/// Direct, no-dialog download.
///
/// On Android 10+ this writes into the public Downloads/Termiguard
/// folder via MediaStore (through [_channel]) - no storage permission
/// needed - so the file shows up in the Files app and can be
/// opened/shared straight from the export success message.
///
/// On Android 9 and below, MediaStore's Downloads collection doesn't
/// exist yet, so this falls back to the previous behaviour: file_saver
/// writes to the app's own external files directory. That's saved, but
/// not browsable from the Files app - callers should say so explicitly
/// rather than implying it landed in Downloads.
///
/// Returns null on iOS and desktop native builds, where there's no
/// direct-save equivalent - the caller falls back to the share sheet.
///
/// A real save failure (e.g. out of storage) is NOT swallowed here - it
/// throws, so the caller can report exactly which file failed.
Future<SavedFile?> downloadFile(String name, List<int> bytes) async {
  if (!Platform.isAndroid) return null;

  try {
    final uri = await _channel.invokeMethod<String>('saveToDownloads', {
      'fileName': name,
      'bytes': Uint8List.fromList(bytes),
      'subfolder': 'Termiguard',
      'mimeType': 'text/csv',
    });
    return SavedFile(SaveMethod.androidDownloads, uri);
  } on PlatformException catch (e) {
    if (e.code != 'UNSUPPORTED_SDK') rethrow; // a real failure - surface it
  }

  // Android 9 (API < 29): MediaStore.Downloads isn't available yet.
  // Fall back to the previous app-private-storage save.
  final dot = name.lastIndexOf('.');
  final base = dot == -1 ? name : name.substring(0, dot);
  final ext = dot == -1 ? '' : name.substring(dot + 1);
  await FileSaver.instance.saveFile(
    name: base,
    bytes: Uint8List.fromList(bytes),
    fileExtension: ext,
    mimeType: MimeType.other,
    customMimeType: 'text/csv',
  );
  return const SavedFile(SaveMethod.androidLegacyPrivate);
}

/// Opens a saved file's content URI with whatever app the user has for
/// CSVs. Never throws for "no app installed" - returns false so the
/// caller can show a friendly message and offer Share instead.
Future<bool> openSavedFile(String uri, {String mimeType = 'text/csv'}) async {
  try {
    await _channel.invokeMethod('openUri', {'uri': uri, 'mimeType': mimeType});
    return true;
  } on PlatformException catch (e) {
    if (e.code == 'NO_VIEWER') return false;
    rethrow;
  }
}

/// Shares a saved file's content URI via the normal Android share sheet.
Future<void> shareSavedFile(String uri, {String mimeType = 'text/csv'}) {
  return _channel.invokeMethod('shareUri', {'uri': uri, 'mimeType': mimeType});
}