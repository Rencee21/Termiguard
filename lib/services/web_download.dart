/// Picks the right implementation at compile time: the real browser
/// download on web, a no-op stub everywhere else.
library;
export 'web_download_io.dart' if (dart.library.html) 'web_download_web.dart';
