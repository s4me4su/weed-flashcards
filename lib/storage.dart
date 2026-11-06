/// Deck save/load, with a per-platform implementation picked at compile
/// time: a JSON file next to the app on Windows (temp folder if that is not
/// writable), the app's files directory on Android, and browser localStorage
/// on the web. No packages.
library;

export 'storage_io.dart' if (dart.library.js_interop) 'storage_web.dart';
