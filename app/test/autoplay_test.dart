import "package:big_two/rules/cards.dart";
import "package:big_two/rules/combo.dart";
import "package:big_two/rules/game.dart";
import "package:big_two/screens/home_page.dart";
import "package:big_two/screens/online_page.dart";
import "package:big_two/screens/practice_page.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

/// Straight wrap is the stored rule variant. It cannot make a straight pass the 2.
const ruleSets = [false, true];

Settings rules(bool wrap, bool autoplay) => defaultSettings.copyWith(straightsWrap: wrap, autoplay: autoplay);

HandState facing(List<String> hand, List<String> table, {bool wrap = false}) {
  final used = {...hand, ...table};
  final rest = [for (final card in fullDeck()) if (!used.contains(formatCard(card))) card];
  List<PlayingCard> take(int count) {
    final cards = rest.sublist(0, count);
    rest.removeRange(0, count);
    return cards;
  }

  final trick = identify(parseCards(table), wrap: wrap);
  expect(trick, isNotNull);
  return makeState(
    hands: [parseCards(hand), take(5), take(5), take(5)],
    turn: 0,
    trick: trick,
    trickSeat: 3,
    trickCards: table,
  );
}

void main() {
  testWidgets("Autoplay starts off, and the rules explain the two skips", (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(MaterialApp(
      home: HomePage(prefs: prefs, supabase: null, scale: 1, onScale: (_) {}),
    ));
    final rules = find.textContaining("A single 2♠ is always passed");
    for (var step = 0; step < 6 && rules.evaluate().isEmpty; step++) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
    }
    expect(rules, findsOneWidget);
    expect(find.textContaining("fewer cards than the play needs"), findsOneWidget);
    expect(find.textContaining("best of its kind"), findsOneWidget);
    expect(find.textContaining("not passed just because the cards that could beat it have already been played"), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: PracticePage(names: const ["Ada", "Bea", "Cal", "Dee"], settings: defaultSettings, sound: false),
    ));
    final autoplayText = find.text("Autoplay");
    for (var step = 0; step < 8 && autoplayText.evaluate().isEmpty; step++) {
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pump();
    }
    final tile = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, "Autoplay"));
    expect(tile.value, isFalse);
    expect(tile.subtitle, isA<Text>().having((text) => (text).data, "subtitle", contains("best play of its kind")));
    await tester.ensureVisible(find.text("Deal"));
    final autoplayTile = find.widgetWithText(SwitchListTile, "Autoplay");
    final deal = find.widgetWithText(FilledButton, "Deal");
    expect(tester.getBottomLeft(autoplayTile).dy, lessThanOrEqualTo(tester.getTopLeft(deal).dy));
    expect(tester.getTopLeft(deal).dy - tester.getBottomLeft(autoplayTile).dy, lessThan(24));
    await tester.tap(find.text("Autoplay"));
    await tester.pump();
    expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, "Autoplay")).value, isTrue);
  });

  testWidgets("the online lobby puts Autoplay under Sounds, read-only for a guest", (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: LobbySoundAutoplay(sound: true, onSound: null, autoplay: true, onAutoplay: null),
      ),
    ));
    expect(find.text("Sounds"), findsOneWidget);
    expect(find.text("Autoplay"), findsOneWidget);
    expect(tester.getTopLeft(find.text("Sounds")).dy, lessThan(tester.getTopLeft(find.text("Autoplay")).dy));
    final autoplay = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, "Autoplay"));
    expect(autoplay.value, isTrue);
    expect(autoplay.onChanged, isNull);
  });

  testWidgets("the host can toggle lobby Autoplay", (tester) async {
    var autoplay = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => LobbySoundAutoplay(
            sound: false,
            onSound: (_) {},
            autoplay: autoplay,
            onAutoplay: (value) => setState(() => autoplay = value),
          ),
        ),
      ),
    ));
    await tester.tap(find.text("Autoplay"));
    await tester.pump();
    expect(autoplay, isTrue);
  });

  for (final wrap in ruleSets) {
    final off = rules(wrap, false);
    final on = rules(wrap, true);
    final label = wrap ? "straight wrap on" : "straight wrap off";

    test("autoplay off leaves passes unchanged ($label)", () {
      final two = facing(["3D", "4D"], ["2S"], wrap: wrap);
      expect(shouldAutoPass(two, 0, off), isTrue);
      expect(shouldAutoPass(two, 0, on), isTrue);

      final short = facing(["3D"], ["8C", "8D"], wrap: wrap);
      final bestPair = facing(["3D", "4D", "5D", "6D", "7D"], ["2S", "2H"], wrap: wrap);
      final beaten = facing(["3D", "4D", "5D", "6D", "7D"], ["8C", "8D"], wrap: wrap);
      final heart = facing(["3D", "4D", "5D", "6D", "7D"], ["2H"], wrap: wrap);
      for (final state in [short, bestPair, beaten, heart]) {
        expect(shouldAutoPass(state, 0, off), isFalse);
      }
      final lead = makeState(
        hands: [parseCards(["2H"]), parseCards(["3D"]), parseCards(["4C"]), parseCards(["5H"])],
        turn: 0,
      );
      expect(shouldAutoPass(lead, 0, on), isFalse);
    });

    test("(A) a short public count is passed only when autoplay is on ($label)", () {
      final pair = facing(["9S"], ["4C", "4D"], wrap: wrap);
      final pairWithDeuce = facing(["2S"], ["4C", "4D"], wrap: wrap);
      final enoughForPair = facing(["3D", "4D"], ["8C", "8D"], wrap: wrap);
      final triple = facing(["3D", "4D"], ["8C", "8D", "8H"], wrap: wrap);
      final enoughForTriple = facing(["3D", "4D", "5D"], ["8C", "8D", "8H"], wrap: wrap);
      final five = facing(["3D", "4D", "5D", "6D"], ["3C", "4C", "5C", "6C", "7C"], wrap: wrap);
      final enoughForFive = facing(["9D", "9C", "8D", "7D", "6D"], ["3C", "4C", "5C", "6C", "7C"], wrap: wrap);
      final oneAgainstSingle = facing(["3D"], ["5H"], wrap: wrap);

      for (final state in [pair, pairWithDeuce, triple, five]) {
        expect(shouldAutoPass(state, 0, on), isTrue);
      }
      expect(shouldAutoPass(pair, 0, on), shouldAutoPass(pairWithDeuce, 0, on));
      for (final state in [enoughForPair, enoughForTriple, enoughForFive, oneAgainstSingle]) {
        expect(shouldAutoPass(state, 0, on), isFalse);
      }
    });

    test("(B) the best play of its kind is passed under these rules ($label)", () {
      final pair = facing(["3D", "4D", "5D", "6D", "7D"], ["2S", "2C"], wrap: wrap);
      final lesserPair = facing(["3D", "4D", "5D", "6D", "7D"], ["2H", "2D"], wrap: wrap);
      final triple = facing(["3D", "4D", "5D", "6D", "7D"], ["2S", "2H", "2D"], wrap: wrap);
      final royal = facing(["3D", "4D", "5D", "6D", "7D"], ["TS", "JS", "QS", "KS", "AS"], wrap: wrap);
      final heartRoyal = facing(["3D", "4D", "5D", "6D", "7D"], ["TH", "JH", "QH", "KH", "AH"], wrap: wrap);
      final wheel = facing(["6D", "7D", "8D", "9D", "TD"], ["AS", "2S", "3S", "4S", "5S"], wrap: wrap);
      final topStraight = facing(["3D", "4D", "5D", "6D", "7D"], ["JS", "QS", "KS", "AS", "2S"], wrap: wrap);

      expect(identify(parseCards(["AS", "2S", "3S", "4S", "5S"]), wrap: wrap)?.kind, ComboKind.flush);
      expect(shouldAutoPass(pair, 0, on), isTrue);
      expect(shouldAutoPass(lesserPair, 0, on), isFalse);
      expect(shouldAutoPass(triple, 0, on), isTrue);
      expect(shouldAutoPass(royal, 0, on), isTrue);
      expect(shouldAutoPass(heartRoyal, 0, on), isFalse);
      expect(shouldAutoPass(wheel, 0, on), isFalse);
      expect(shouldAutoPass(topStraight, 0, on), isFalse);
    });

    test("a play is not auto-passed just because the cards that beat it are gone ($label)", () {
      final heart = facing(["3D", "4D", "5D", "6D", "7D"], ["2H"], wrap: wrap);
      final lowPair = facing(["3D", "4D", "5D", "6D", "7D"], ["2C", "2D"], wrap: wrap);
      final lesserTriple = facing(["3D", "4D", "5D", "6D", "7D"], ["2D", "2C", "2H"], wrap: wrap);
      final heartRoyal = facing(["3D", "4D", "5D", "6D", "7D"], ["TH", "JH", "QH", "KH", "AH"], wrap: wrap);
      for (final state in [heart, lowPair, lesserTriple, heartRoyal]) {
        expect(shouldAutoPass(state, 0, on), isFalse);
      }

      var state = makeState(
        hands: [
          parseCards(["2S", "2H", "3D", "4D", "5D"]),
          parseCards(["3C", "4C", "5C", "6C", "7C"]),
          parseCards(["8C", "8D", "8H", "9C", "9D"]),
          parseCards(["KC", "KD", "KH", "QC", "QD"]),
        ],
        turn: 0,
      );
      state = (applyPlay(state, 0, ["2S"], on) as StepOk).state;
      state = (applyPass(state, 1, on) as StepOk).state;
      state = (applyPass(state, 2, on) as StepOk).state;
      state = (applyPass(state, 3, on) as StepOk).state;
      state = (applyPlay(state, 0, ["2H"], on) as StepOk).state;
      expect(state.trickCards, ["2H"]);
      expect(shouldAutoPass(state, state.turn, on), isFalse);
      expect(shouldAutoPass(state, state.turn, off), isFalse);
    });

    test("a skip uses the public count, not the hidden cards ($label)", () {
      final cannot = facing(["3D", "4D"], ["9C", "9D"], wrap: wrap);
      final can = facing(["2S", "2H"], ["9C", "9D"], wrap: wrap);
      expect(shouldAutoPass(cannot, 0, on), isFalse);
      expect(shouldAutoPass(can, 0, on), isFalse);
      final deuceOut = facing(["3D", "4D", "5D"], ["2H"], wrap: wrap);
      expect(shouldAutoPass(deuceOut, 0, on), isFalse);
    });

  }
}
