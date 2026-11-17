import "package:big_two/rules/cards.dart";
import "package:big_two/rules/game.dart";
import "package:big_two/widgets/win_flourish.dart";
import "package:flutter/material.dart" hide Step;
import "package:flutter_test/flutter_test.dart";

void main() {
  testWidgets("a tap skips the win flourish", (tester) async {
    var done = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              WinFlourish(name: "Ada", cards: [parseCard("7H"), parseCard("7D")], onDone: () => done++),
              const Text("Deal next hand"),
            ],
          ),
        ),
      ),
    );
    expect(find.text("Ada wins!"), findsOneWidget);
    expect(find.byKey(const Key("confetti")), findsOneWidget);
    expect(find.text("Deal next hand"), findsOneWidget);
    await tester.tap(find.byKey(const Key("win-flourish")));
    await tester.pump();
    expect(done, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: WinFlourish(name: "Ada", cards: [parseCard("KS")], onDone: () {}),
        ),
      ),
    );
    await tester.pump();
    expect(find.text("Ada wins!"), findsOneWidget);
    expect(find.byKey(const Key("confetti")), findsNothing);
  });

  test("replaying the saved plays, including a timeout, rebuilds the leftovers", () {
    final deck = fullDeck();
    final settings = defaultSettings;
    final start = replay(deck, const [0, 0, 0, 0], true, null, const [], settings) as StepOk;
    final seat = start.state.turn;
    final played = replay(deck, const [0, 0, 0, 0], true, null, [
      ReplayEvent(kind: "play", seat: seat, cards: const ["3D"]),
    ], settings) as StepOk;
    expect(played.state.hands[seat].map(formatCard), isNot(contains("3D")));
    expect(played.state.hands[seat], hasLength(12));

    final next = played.state.turn;
    final held = played.state.hands[next].map(formatCard).toList();
    final timed = replay(deck, const [0, 0, 0, 0], true, null, [
      ReplayEvent(kind: "play", seat: seat, cards: const ["3D"]),
      ReplayEvent(kind: "timeout", seat: next, cards: const ["AS"]),
    ], settings) as StepOk;
    expect(timed.state.hands[next].map(formatCard).toList(), held);
    expect(timed.state.consecutivePasses, greaterThan(0));
  });

  test("a whole hand replayed from the deal matches the cards left", () {
    final seat0 = [for (var rank = 3; rank <= 14; rank++) PlayingCard(rank, Suit.diamonds), const PlayingCard(4, Suit.clubs)];
    final used = seat0.map(formatCard).toSet();
    final deck = [...seat0, ...fullDeck().where((card) => !used.contains(formatCard(card)))];
    final settings = defaultSettings;
    var step = replay(deck, const [0, 0, 0, 0], true, null, const [], settings) as StepOk;
    final events = <ReplayEvent>[];
    for (var guard = 0; step.state.status != "complete" && guard < 200; guard++) {
      final seat = step.state.turn;
      final cards = lowestLegalPlay(step.state, seat, settings);
      final Step next;
      if (cards == null) {
        events.add(ReplayEvent(kind: "pass", seat: seat));
        next = applyPass(step.state, seat, settings);
      } else {
        events.add(ReplayEvent(kind: "play", seat: seat, cards: cards));
        next = applyPlay(step.state, seat, cards, settings);
      }
      expect(next, isA<StepOk>(), reason: next is StepBad ? next.message : null);
      step = next as StepOk;
    }
    expect(step.state.status, "complete");
    final again = replay(deck, const [0, 0, 0, 0], true, null, events, settings) as StepOk;
    expect(again.state.winner, step.state.winner);
    expect(step.result, isNotNull);
    expect(step.result!.cardsLeft[step.state.winner!], 0);
    for (var seat = 0; seat < 4; seat++) {
      expect(again.state.hands[seat].map(formatCard).toList(), step.state.hands[seat].map(formatCard).toList());
      if (seat == step.state.winner) expect(again.state.hands[seat], isEmpty);
    }
  });
}
