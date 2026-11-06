import 'dart:js_interop';

const String _deckKey = 'weeds_deck_v1';

@JS('localStorage.getItem')
external JSString? _getItem(JSString key);

@JS('localStorage.setItem')
external void _setItem(JSString key, JSString value);

/// Where the deck is kept on the web: this browser's own storage, so the save
/// belongs to the phone/browser it was made in.
String deckLocation() => 'this browser\'s saved data (localStorage)';

/// Returns the saved deck JSON, or null if there is no save yet.
/// A browser that blocks storage (private mode) simply looks like a fresh
/// start instead of throwing.
Future<String?> readDeck() async {
  try {
    return _getItem(_deckKey.toJS)?.toDart;
  } catch (_) {
    return null;
  }
}

/// Throws if the browser refuses the write (private mode / quota exceeded) so
/// the UI can say so out loud rather than losing it quietly.
Future<void> writeDeck(String data) async => _setItem(_deckKey.toJS, data.toJS);
