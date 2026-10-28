import "package:big_two/online/selection.dart";
import "package:big_two/rules/cards.dart";
import "package:big_two/rules/combo.dart";
import "package:big_two/rules/game.dart";
import "package:big_two/theme.dart";
import "package:big_two/widgets/playing_card_view.dart";
import "package:big_two/widgets/table_view.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  const settings = defaultSettings;

  test("a pre-selected play goes through with one tap, and an illegal one stays stopped", () {
    final ready = makeState(
      hands: [
        parseCards(["KH", "4C", "9D"]),
        parseCards(["QS", "3C"]),
        parseCards(["6H", "7H"]),
        parseCards(["8D", "TD"]),
      ],
      turn: 0,
      trick: identify(parseCards(["5D"])),
      trickSeat: 3,
      trickCards: ["5D"],
    );
    final selected = ["KH"];
    expect(canPressPlay(yourTurn: false, paused: false, issue: null), isFalse);
    final legal = playIssue(ready, 0, parseCards(selected), settings);
    expect(legal, isNull);
    expect(canPressPlay(yourTurn: true, paused: false, issue: legal), isTrue);
    final played = applyPlay(ready, 0, selected, settings);
    expect(played, isA<StepOk>());

    final beaten = makeState(
      hands: ready.hands,
      turn: 0,
      trick: identify(parseCards(["AS"])),
      trickSeat: 1,
      trickCards: ["AS"],
    );
    final blocked = playIssue(beaten, 0, parseCards(selected), settings);
    expect(blocked, "Doesn't beat the current play");
    expect(canPressPlay(yourTurn: true, paused: false, issue: blocked), isFalse);
    expect(applyPlay(beaten, 0, selected, settings), isA<StepBad>());
    expect(selected, ["KH"]);
  });

  test("a selection made before the turn survives a poll, a reordered hand, and the lead", () {
    const selected = {"KH", "4C"};
    const hand = ["KH", "4C", "9D", "3S"];

    expect(
      retainSelection(selected: selected, hand: hand, newHand: false, played: false),
      selected,
    );
    expect(
      retainSelection(selected: selected, hand: ["3S", "9D", "4C", "KH"], newHand: false, played: false),
      selected,
    );
    expect(
      retainSelection(selected: selected, hand: hand, newHand: false, played: false),
      selected,
    );
  });

  test("cards that left the hand are dropped, and a play or a new hand clears the rest", () {
    const selected = {"KH", "4C", "9D"};
    expect(
      retainSelection(selected: selected, hand: ["KH", "9D", "3S"], newHand: false, played: false),
      {"KH", "9D"},
    );
    expect(
      retainSelection(selected: selected, hand: ["4C", "9D", "3S"], newHand: false, played: true),
      isEmpty,
    );
    expect(
      retainSelection(selected: selected, hand: ["KH", "4C", "2S"], newHand: true, played: false),
      isEmpty,
    );
  });

  testWidgets("cards chosen before the turn stay raised when the turn arrives", (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var selected = <String>{"KH"};
    var yourTurn = false;
    const hand = ["KH", "4C", "9D"];

    Future<void> show() {
      return tester.pumpWidget(MaterialApp(
        theme: bigTwoTheme(),
        home: TableView(
          bottom: SeatSpot(name: "Justin", cardsLeft: hand.length, total: 0, turn: yourTurn),
          left: SeatSpot(name: "Mary", cardsLeft: 13, total: 0, turn: !yourTurn),
          top: const SeatSpot(name: "Pauline", cardsLeft: 13, total: 0, turn: false),
          right: const SeatSpot(name: "Damien", cardsLeft: 13, total: 0, turn: false),
          hand: [for (final id in hand) parseCard(id)],
          selected: selected,
          trick: yourTurn ? const [] : [parseCard("5D")],
          trickLabel: yourTurn ? null : "5",
          trickPlayer: yourTurn ? null : "Mary",
          yourTurn: yourTurn,
          canPlay: yourTurn,
          canPass: false,
          passLabel: "Pass",
          reason: null,
          banner: yourTurn ? "Your lead" : "Waiting for Mary",
          onPlay: () {},
          onPass: () {},
          onSortRank: () {},
          onSortSuit: () {},
          onScores: () {},
          onToggle: (_) {},
          onReorder: (_, __) {},
        ),
      ));
    }

    PlayingCardView face(String id) {
      return tester.widget<PlayingCardView>(find.byWidgetPredicate(
        (widget) => widget is PlayingCardView && widget.card?.id == id,
      ));
    }

    await show();
    await tester.pumpAndSettle();
    expect(face("KH").selected, isTrue);
    expect(face("4C").selected, isFalse);

    selected = retainSelection(selected: selected, hand: hand, newHand: false, played: false);
    yourTurn = true;
    await show();
    await tester.pumpAndSettle();
    expect(selected, {"KH"});
    expect(face("KH").selected, isTrue);
    expect(find.text("Your turn"), findsOneWidget);

    selected = retainSelection(selected: selected, hand: ["4C", "9D"], newHand: false, played: true);
    await tester.pumpWidget(MaterialApp(
      theme: bigTwoTheme(),
      home: TableView(
        bottom: const SeatSpot(name: "Justin", cardsLeft: 2, total: 0, turn: false),
        left: const SeatSpot(name: "Mary", cardsLeft: 12, total: 0, turn: true),
        top: const SeatSpot(name: "Pauline", cardsLeft: 13, total: 0, turn: false),
        right: const SeatSpot(name: "Damien", cardsLeft: 13, total: 0, turn: false),
        hand: [parseCard("4C"), parseCard("9D")],
        selected: selected,
        trick: const [],
        trickLabel: null,
        trickPlayer: null,
        yourTurn: false,
        canPlay: false,
        canPass: false,
        passLabel: "Pass",
        reason: null,
        banner: "Waiting for Mary",
        onPlay: () {},
        onPass: () {},
        onSortRank: () {},
        onSortSuit: () {},
        onScores: () {},
        onToggle: (_) {},
        onReorder: (_, __) {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
    expect(find.byWidgetPredicate((widget) => widget is PlayingCardView && widget.card?.id == "KH"), findsNothing);
    expect(face("4C").selected, isFalse);
  });
}
