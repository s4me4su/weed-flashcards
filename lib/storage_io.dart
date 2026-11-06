import 'dart:io';

const String _deckName = 'weeds_deck_v1.json';

/// Places the save file may live, best first.
///
/// * Android: the app's *files* directory. `Directory.systemTemp` is the
///   *cache* directory there, which Android (or "Clear cache") can throw away.
/// * Windows / Linux / macOS: next to the executable first, so the app is
///   portable - copy the folder to a USB stick or send it to a friend and the
///   saved deck travels with it. The temp folder is the fallback for a
///   read-only install location.
/// * Anything else: the temp folder.
List<Directory> _candidateDirs() {
  // `flutter test` runs inside the Flutter SDK's test binary; keep its saves in
  // the temp folder instead of writing into the SDK install.
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return <Directory>[Directory.systemTemp];
  }
  if (Platform.isAndroid) {
    return <Directory>[
      Directory('${Directory.systemTemp.parent.path}'
          '${Platform.pathSeparator}files'),
      Directory.systemTemp, // last resort only
    ];
  }
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    return <Directory>[
      File(Platform.resolvedExecutable).parent,
      Directory.systemTemp,
    ];
  }
  return <Directory>[Directory.systemTemp];
}

String _join(String dir, String name) =>
    '$dir${Platform.pathSeparator}$name';

bool _writable(Directory dir) {
  try {
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final probe = File(_join(dir.path, '.weeds_write_test'));
    probe.writeAsStringSync('');
    probe.deleteSync();
    return true;
  } catch (_) {
    return false;
  }
}

/// The directory new saves go into: the first candidate that exists and can
/// be written to.
Directory _saveDir() {
  for (final dir in _candidateDirs()) {
    if (_writable(dir)) return dir;
  }
  return Directory.systemTemp;
}

/// An existing save, wherever it is - older releases used the temp folder and
/// Android releases used the cache folder.
File? _existingSave() {
  for (final dir in _candidateDirs()) {
    final f = File(_join(dir.path, _deckName));
    if (f.existsSync()) return f;
  }
  return null;
}

/// Where a save is written. Also moves an older save across once, so there is
/// never more than one copy to wonder about.
File _saveFile() {
  final dir = _saveDir();
  final target = File(_join(dir.path, _deckName));
  final old = _existingSave();
  if (old != null && old.path != target.path) {
    try {
      old.renameSync(target.path);
    } catch (_) {
      try {
        old.copySync(target.path);
      } catch (_) {
        // Leave the old copy where it is; reads still find it.
      }
    }
  }
  return target;
}

/// Human-readable description of where the deck is kept - shown in the UI so
/// a "where is my progress?" question can be answered.
String deckLocation() {
  final found = _existingSave();
  final dir = found?.parent ?? _saveDir();
  return _join(dir.path, _deckName);
}

/// Returns the saved deck JSON, or null if there is no save yet.
Future<String?> readDeck() async {
  final f = _existingSave();
  if (f == null) return null;
  try {
    return await f.readAsString();
  } catch (_) {
    return null; // unreadable (locked/deleted) - start fresh rather than crash
  }
}

/// Writes the save. Written to a temporary name and then renamed, so a crash
/// or a dead battery mid-write cannot leave a half-written (unusable) save.
int _writeSeq = 0;

Future<void> writeDeck(String data) async {
  final f = _saveFile();
  // Unique temp name per call: the debounced auto-save and the Save button can
  // overlap, and two writers must never share one scratch file.
  final tmp = File('${f.path}.${DateTime.now().microsecondsSinceEpoch}'
      '.${_writeSeq++}.tmp');
  try {
    await tmp.writeAsString(data, flush: true);
    try {
      await tmp.rename(f.path);
    } on FileSystemException {
      // Rename can fail across filesystems; fall back to copy + delete.
      await tmp.copy(f.path);
      await tmp.delete();
    }
  } catch (_) {
    // Never leave scratch files behind, and let the caller report the failure.
    try {
      if (tmp.existsSync()) tmp.deleteSync();
    } catch (_) {}
    rethrow;
  }
}
