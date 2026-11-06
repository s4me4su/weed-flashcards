import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weeds_flashcards/main.dart';

/// Same path the app uses for its saved deck: `flutter test` sets FLUTTER_TEST,
/// which keeps the save in the temp folder (see _candidateDirs in
/// storage_io.dart).
final File _deckFile = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}weeds_deck_v1.json');

/// Swipes the top card with a drag past the throw distance.
Future<void> _swipe(WidgetTester tester, double dx) async {
  await tester.drag(find.byType(SwipeCard), Offset(dx, 0));
  await tester.pumpAndSettle();
}

/// Reads back the save file. Synchronous IO, so it is safe to call from the
/// fake-async test zone.
Map<String, dynamic> _readSavedDeck() {
  expect(_deckFile.existsSync(), isTrue, reason: 'no save file was written');
  return jsonDecode(_deckFile.readAsStringSync()) as Map<String, dynamic>;
}

/// Writes a save file for a test. Real IO, so it runs in `runAsync`.
Future<void> _writeSave(WidgetTester tester, String contents) =>
    tester.runAsync(() => _deckFile.writeAsString(contents));

/// Lets work that mixes the test clock with real file IO finish: pumps advance
/// the fake timer/continuations, `runAsync` lets the real IO complete.
Future<void> _drain(WidgetTester tester, {int rounds = 12}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
  }
  await tester.pumpAndSettle();
}

/// Changes the study filter without going through the (scrollable) menu.
void _setFilter(WidgetTester tester, String family) {
  tester
      .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
      .onChanged!(family);
}

void main() {
  setUp(() async {
    // Start every test with no saved deck. A save still in flight from the
    // previous test can hold its scratch file, so ignore delete failures.
    for (final path in <String>[_deckFile.path, '${_deckFile.path}.tmp']) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  });

  // ---------------------------------------------------------------------
  // Data invariants. These fail loudly when a card is added, retitled or
  // re-grouped, so the numbers quoted in the UI and the docs stay honest.
  // ---------------------------------------------------------------------

  test('deck data is internally consistent', () {
    expect(kDeck, isNotEmpty);

    final ids = kDeck.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'duplicate card ids');

    // The booklet is printed in study-list order, and the card number is the
    // page number - tools/build_weed_cards.py writes it that way.
    expect(kDeck.map((c) => c.number).toList(),
        List<int>.generate(kDeck.length, (i) => i + 1));

    for (final card in kDeck) {
      expect(card.title.trim(), isNotEmpty, reason: '${card.id} has no title');
      expect(card.sci.trim(), isNotEmpty, reason: '${card.id} has no sci name');
      expect(kFamilies.containsKey(card.family), isTrue,
          reason: '${card.id} has unknown family ${card.family}');
      // The asset naming convention is the only thing pairing the images.
      expect(card.frontAsset, 'assets/front/${card.id}.jpg');
      expect(card.backAsset, 'assets/back/${card.id}.jpg');
    }

    for (final filter in kFilterOrder) {
      final matches = kDeck.where((c) => cardMatches(c, filter)).length;
      expect(matches, greaterThan(0), reason: 'filter $filter matches nothing');
    }

    // Quoted in the dropdown and in README.md: 45 pages, 27 families, and the
    // two big families that make the filter worth having.
    expect(kDeck.length, 45);
    expect(kFamilies.length, 27);
    expect(kDeck.where((c) => c.family == 'Asteraceae').length, 9);
    expect(kDeck.where((c) => c.family == 'Poaceae').length, 5);
  });

  testWidgets('every card has both images bundled', (tester) async {
    await tester.runAsync(() async {
      for (final card in kDeck) {
        for (final asset in [card.frontAsset, card.backAsset]) {
          final data = await rootBundle.load(asset);
          expect(data.lengthInBytes, greaterThan(1000),
              reason: '$asset looks empty or missing');
        }
      }
    });
  });

  testWidgets('the name of a weed is never printed on screen', (tester) async {
    // The whole point of the front card is that the name is only in the
    // booklet page it shows. If someone adds a name label to the UI, this
    // fails - the names belong in the images, not in the app's own text.
    await tester.pumpWidget(const WeedFlashcardsApp());
    await tester.pumpAndSettle();

    for (final card in kDeck) {
      expect(find.textContaining(card.title, findRichText: true), findsNothing,
          reason: '${card.title} is shown while studying');
    }
  });

  // ---------------------------------------------------------------------
  // Behaviour
  // ---------------------------------------------------------------------

  testWidgets('deck starts at card 1 and flips on tap', (tester) async {
    await tester.pumpWidget(const WeedFlashcardsApp());

    expect(find.text('Card 1 of ${kDeck.length}'), findsOneWidget);
    expect(find.text('TAP TO FLIP'), findsOneWidget);

    await tester.tap(find.byType(SwipeCard));
    await tester.pumpAndSettle();

    // Flipped to the back (the printed page): the front hint is gone, and it
    // is still card 1 that is flipped.
    expect(find.text('TAP TO FLIP'), findsNothing);
    final flip = tester.widget<FlipCard>(find.byType(FlipCard).first);
    expect(flip.flipped, isTrue);
    expect(find.byKey(ValueKey<String>(kDeck.first.id)), findsOneWidget);
  });

  testWidgets('swipe advances the progress counter', (tester) async {
    await tester.pumpWidget(const WeedFlashcardsApp());

    await _swipe(tester, 500);

    expect(find.text('Card 2 of ${kDeck.length}'), findsOneWidget);
  });

  testWidgets('keyboard arrows swipe and space flips', (tester) async {
    await tester.pumpWidget(const WeedFlashcardsApp());
    await tester.pumpAndSettle();

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.space), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('TAP TO FLIP'), findsNothing);

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Card 2 of ${kDeck.length}'), findsOneWidget);

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Card 3 of ${kDeck.length}'), findsOneWidget);
  });

  testWidgets('remove button drops the card from the deck', (tester) async {
    await tester.pumpWidget(const WeedFlashcardsApp());

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Card 1 of ${kDeck.length - 1}'), findsOneWidget);
  });

  testWidgets('undo puts a removed card back', (tester) async {
    await tester.pumpWidget(const WeedFlashcardsApp());

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Card 1 of ${kDeck.length - 1}'), findsOneWidget);

    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();

    expect(find.text('Card 1 of ${kDeck.length}'), findsOneWidget);

    // Same card in the same place: the top card is card 1 again (the FlipCard
    // is keyed by card id), and flipping it shows the printed page.
    await tester.tap(find.byType(SwipeCard));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey<String>(kDeck.first.id)), findsOneWidget);
    expect(find.text('TAP TO FLIP'), findsNothing);
  });

  testWidgets('family dropdown narrows the deck to one family', (tester) async {
    await tester.pumpWidget(const WeedFlashcardsApp());

    // The menu lists the whole deck first, then every family in the booklet.
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('All weeds  (45)'), findsOneWidget);
    expect(find.text('Asteraceae  (9)'), findsOneWidget);

    // Close the menu by choosing the entry that is already selected.
    await tester.tap(find.text('All weeds  (45)'));
    await tester.pumpAndSettle();

    // The grass cards.
    _setFilter(tester, 'Poaceae');
    await tester.pumpAndSettle();
    expect(find.text('Card 1 of 5'), findsOneWidget);
    expect(find.text('Poaceae'), findsOneWidget); // shown on the button

    // The daisy / sunflower cards.
    _setFilter(tester, 'Asteraceae');
    await tester.pumpAndSettle();
    expect(find.text('Card 1 of 9'), findsOneWidget);

    // Back to the whole booklet.
    _setFilter(tester, kAllFilter);
    await tester.pumpAndSettle();
    expect(find.text('Card 1 of ${kDeck.length}'), findsOneWidget);
  });

  testWidgets('a one-card family can be studied on its own', (tester) async {
    await tester.pumpWidget(const WeedFlashcardsApp());

    _setFilter(tester, 'Salviniaceae');
    await tester.pumpAndSettle();
    expect(find.text('Card 1 of 1'), findsOneWidget);

    await _swipe(tester, 500);
    await tester.pumpAndSettle();
    // The app bar and the summary both say the deck is done.
    expect(find.text('Deck complete'), findsNWidgets(2));
    expect(find.text('1 cards reviewed  •  0 marked for review'),
        findsOneWidget);
  });

  testWidgets('the end of the deck lists the review marks by family',
      (tester) async {
    await tester.pumpWidget(const WeedFlashcardsApp());

    await _swipe(tester, -500); // card 1 (green cestrum) marked for review
    await _swipe(tester, 500);  // card 2 known
    await tester.pumpAndSettle();

    // Only two cards were reviewed, so the summary is not on screen yet;
    // finish the deck to see it.
    for (var i = 0; i < kDeck.length - 2; i++) {
      await _swipe(tester, 500);
    }
    await tester.pumpAndSettle();

    expect(find.text('Deck complete'), findsNWidgets(2)); // app bar + summary
    expect(find.text('45 cards reviewed  •  1 marked for review'),
        findsOneWidget);
    expect(find.text('nightshade (Solanaceae)'), findsOneWidget);
    expect(find.text(kDeck.first.title), findsOneWidget); // the review chip
  });

  testWidgets('fits a phone screen without overflowing the top bar',
      (tester) async {
    // Typical phone width in logical pixels (iPhone 15 / Pixel 8).
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    // A gesture-navigation bar eats the bottom 48 px of the screen.
    tester.view.padding =
        const FakeViewPadding(bottom: 48, left: 0, top: 24, right: 0);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const WeedFlashcardsApp());
    await tester.pumpAndSettle();

    // Any RenderFlex overflow shows up here as an exception.
    expect(tester.takeException(), isNull);
    expect(find.text('Card 1 of ${kDeck.length}'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsOneWidget);

    // The swipe buttons stay on screen and tappable at phone size, clear of
    // the navigation-bar inset (SafeArea).
    final check = tester.getRect(find.byIcon(Icons.check));
    expect(check.bottom, lessThan(852 - 48));
  });

  testWidgets('a very short window still renders', (tester) async {
    tester.view.physicalSize = const Size(900, 260);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const WeedFlashcardsApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SwipeCard), findsOneWidget);
  });

  // ---------------------------------------------------------------------
  // Saving and restoring
  // ---------------------------------------------------------------------

  testWidgets('save button writes the deck file', (tester) async {
    await tester.pumpWidget(const WeedFlashcardsApp());

    // Real file IO must run outside the fake-async test zone.
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.save_alt));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });

    expect(_readSavedDeck()['order'], hasLength(kDeck.length));
  });

  testWidgets('the deck is saved by itself after a swipe', (tester) async {
    await tester.pumpWidget(const WeedFlashcardsApp());

    await _swipe(tester, -500); // mark card 1 for review

    // The debounce timer runs on the test clock; the write itself is real IO.
    await _drain(tester);

    final saved = _readSavedDeck();
    expect(saved['index'], 1);
    expect((saved['review'] as List).cast<String>(),
        contains(kDeck.first.id));
    expect(saved['filter'], kAllFilter);
    expect(saved['v'], 1);
  });

  testWidgets('review marks survive changing the filter', (tester) async {
    await tester.pumpWidget(const WeedFlashcardsApp());

    await _swipe(tester, -500); // mark card 1 for review
    _setFilter(tester, 'Poaceae');
    await tester.pumpAndSettle();
    _setFilter(tester, kAllFilter);
    await tester.pumpAndSettle();

    await _drain(tester);

    expect((_readSavedDeck()['review'] as List).cast<String>(),
        contains(kDeck.first.id));
  });

  testWidgets('a saved deck reopens where it left off', (tester) async {
    final order = kDeck.map((c) => c.id).toList();
    await _writeSave(tester, jsonEncode({
      'v': 1,
      'order': order.sublist(2), // two cards removed
      'index': 3,
      'review': [order[0], order[1]],
      'filter': kAllFilter,
    }));

    await tester.pumpWidget(const WeedFlashcardsApp());
    await _drain(tester); // the save file is read with real IO

    expect(find.text('Card 4 of ${kDeck.length - 2}'), findsOneWidget);
    expect(find.textContaining('Saved deck restored'), findsOneWidget);
  });

  testWidgets('a saved family filter reopens with just those cards',
      (tester) async {
    await _writeSave(tester, jsonEncode({
      'v': 1,
      'order': kDeck.map((c) => c.id).toList(),
      'index': 1,
      'review': <String>[],
      'filter': 'Poaceae',
    }));

    await tester.pumpWidget(const WeedFlashcardsApp());
    await _drain(tester);

    expect(find.text('Card 2 of 5'), findsOneWidget);
    expect(find.text('Poaceae'), findsOneWidget);
  });

  testWidgets('a family filter that no longer exists falls back to all',
      (tester) async {
    // A save from a booklet with a family that has since been dropped must not
    // take the DropdownButton down.
    await _writeSave(tester, jsonEncode({
      'v': 1,
      'order': kDeck.map((c) => c.id).toList(),
      'index': 0,
      'review': <String>[],
      'filter': 'Boraginaceae',
    }));

    await tester.pumpWidget(const WeedFlashcardsApp());
    await _drain(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Card 1 of ${kDeck.length}'), findsOneWidget);
  });

  testWidgets('a corrupt save file is ignored, not fatal', (tester) async {
    await _writeSave(tester, '{"order": [ "oops"');

    await tester.pumpWidget(const WeedFlashcardsApp());
    await _drain(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Card 1 of ${kDeck.length}'), findsOneWidget);
  });

  testWidgets('removing every card leaves a usable empty deck', (tester) async {
    await tester.pumpWidget(const WeedFlashcardsApp());

    // 'Salviniaceae' matches exactly one card, so one tap empties the deck.
    _setFilter(tester, 'Salviniaceae');
    await tester.pumpAndSettle();
    expect(find.text('Card 1 of 1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Deck is empty'), findsOneWidget);

    // And the way back is right there.
    await tester.tap(find.text('Restart in order'));
    await tester.pumpAndSettle();
    expect(find.text('Card 1 of 1'), findsOneWidget);
  });
}
