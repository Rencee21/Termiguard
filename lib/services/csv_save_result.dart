/// How a single CSV file ended up being written, so the UI can show an
/// accurate, platform-correct message and only offer Open/Share when a
/// real openable URI exists.
enum SaveMethod {
  /// Android 10+ (API 29+): written into the public MediaStore
  /// Downloads/Termiguard collection - shows up in the Files app and can
  /// be opened/shared via [SavedFile.uri]. No storage permission needed.
  androidDownloads,

  /// Android 9 and below (API < 29), where the MediaStore Downloads
  /// collection doesn't exist yet: falls back to the previous behaviour
  /// (file_saver's app-private external files directory). Saved, but not
  /// browsable from the Files app - the UI says so explicitly.
  androidLegacyPrivate,

  /// Web: a normal browser download was triggered.
  browserDownload,

  /// iOS / desktop native, where there's no direct-save equivalent: the
  /// OS share sheet was used instead.
  shareSheet,
}

/// Result of writing one file via the direct (non-share-sheet) path.
class SavedFile {
  final SaveMethod method;

  /// content:// URI for the saved file. Only ever set for
  /// [SaveMethod.androidDownloads] - it's what lets Open/Share work
  /// without needing any storage permission to read the file back.
  final String? uri;

  const SavedFile(this.method, [this.uri]);
}

/// Outcome for a single one of the three exported CSV files.
class CsvFileOutcome {
  final String fileName;
  final bool success;
  final String? uri;
  final String? error;

  const CsvFileOutcome({
    required this.fileName,
    required this.success,
    this.uri,
    this.error,
  });
}

/// Result of exporting all three CSV files.
class CsvExportResult {
  final SaveMethod mode;
  final List<CsvFileOutcome> outcomes;

  /// False only when the user dismissed the share sheet without picking
  /// anything - the one case where nothing happened at all.
  final bool completed;

  const CsvExportResult({
    required this.mode,
    required this.outcomes,
    required this.completed,
  });

  bool get allSucceeded => outcomes.every((o) => o.success);
  List<CsvFileOutcome> get failed =>
      outcomes.where((o) => !o.success).toList();
}
