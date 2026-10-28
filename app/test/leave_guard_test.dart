import "package:big_two/widgets/leave_guard.dart";
import "package:big_two/widgets/table_view.dart";
import "package:big_two/rules/cards.dart";
import "package:big_two/theme.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("a running hand warns the host and a guest, and a finished round does not", () {
    expect(
      shouldWarnBeforeLeaving(dealt: true, handInProgress: true, roundOver: false),
      isTrue,
    );
    expect(leaveMessage(host: true), leaveHostMessage);
    expect(leaveMessage(host: false), leaveGuestMessage);

    expect(
      shouldWarnBeforeLeaving(dealt: true, handInProgress: false, roundOver: false),
      isTrue,
    );
    expect(
      shouldWarnBeforeLeaving(dealt: true, handInProgress: false, roundOver: true),
      isFalse,
    );
    expect(
      shouldWarnBeforeLeaving(dealt: false, handInProgress: false, roundOver: false),
      isFalse,
    );
  });

  testWidgets("the host is warned mid-hand and Stay in game keeps the page", (tester) async {
    await _open(tester, warn: true, host: true);
    await _back(tester);
    expect(find.text(leaveTitle), findsOneWidget);
    expect(find.text(leaveHostMessage), findsOneWidget);
    expect(find.text(leaveGuestMessage), findsNothing);
    expect(find.widgetWithText(FilledButton, "Stay in game"), findsOneWidget);
    await tester.tap(find.text("Stay in game"));
    await tester.pumpAndSettle();
    expect(find.text(leaveTitle), findsNothing);
    expect(find.text("in game"), findsOneWidget);
  });

  testWidgets("another player gets the shorter warning mid-hand", (tester) async {
    await _open(tester, warn: true, host: false);
    await _back(tester);
    expect(find.text(leaveTitle), findsOneWidget);
    expect(find.text(leaveGuestMessage), findsOneWidget);
    expect(find.text(leaveHostMessage), findsNothing);
  });

  testWidgets("between hands, before anyone reaches 50, Leave anyway exits", (tester) async {
    await _open(tester, warn: true, host: false);
    await _back(tester);
    expect(find.text(leaveGuestMessage), findsOneWidget);
    await tester.tap(find.text("Leave anyway"));
    await tester.pumpAndSettle();
    expect(find.text("in game"), findsNothing);
    expect(find.text("open"), findsOneWidget);
  });

  testWidgets("once the round is over, back leaves with no warning", (tester) async {
    await _open(tester, warn: false, host: true);
    await _back(tester);
    expect(find.text(leaveTitle), findsNothing);
    expect(find.text("open"), findsOneWidget);
  });

  testWidgets("going back keeps the seat, and Exit is a separate button", (tester) async {
    var exited = false;
    await tester.pumpWidget(MaterialApp(
      theme: bigTwoTheme(),
      home: LeaveGate(
        warn: true,
        host: false,
        title: seatHeldTitle,
        message: seatHeldMessage,
        child: Scaffold(
          body: TableView(
            bottom: const SeatSpot(name: "Mary", cardsLeft: 13, total: 0, turn: true, detail: "Ralph"),
            left: const SeatSpot(name: "Justin", cardsLeft: 13, total: 0, turn: false),
            top: const SeatSpot(name: "Pauline", cardsLeft: 13, total: 0, turn: false),
            right: const SeatSpot(name: "Damien", cardsLeft: 13, total: 0, turn: false),
            hand: [parseCard("3D")],
            selected: const {},
            trick: const [],
            trickLabel: null,
            trickPlayer: null,
            yourTurn: true,
            canPlay: true,
            canPass: true,
            passLabel: "Pass",
            reason: null,
            banner: "Watching: Ralph",
            onPlay: () {},
            onPass: () {},
            onSortRank: () {},
            onSortSuit: () {},
            onScores: () {},
            onExit: () => exited = true,
            onToggle: (_) {},
            onReorder: (_, __) {},
          ),
        ),
      ),
    ));
    expect(find.text("Watching: Ralph"), findsOneWidget);
    expect(find.text("Ralph"), findsOneWidget);
    expect(find.byKey(const Key("exit-table")), findsOneWidget);
    await tester.tap(find.byTooltip("Back"));
    await tester.pumpAndSettle();
    expect(find.text(seatHeldTitle), findsOneWidget);
    expect(find.text(seatHeldMessage), findsOneWidget);
    expect(exited, isFalse);
    await tester.tap(find.byKey(const Key("stay-in-game")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key("exit-table")));
    await tester.pumpAndSettle();
    expect(exited, isTrue);
    expect(find.text(exitTitle), findsNothing);
  });

  testWidgets("confirming Exit is not the same as going back", (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => confirmExit(context),
          child: const Text("ask"),
        ),
      ),
    ));
    await tester.tap(find.text("ask"));
    await tester.pumpAndSettle();
    expect(find.text(exitTitle), findsOneWidget);
    expect(find.text(exitMessage), findsOneWidget);
    expect(find.byKey(const Key("confirm-exit")), findsOneWidget);
    await tester.tap(find.byKey(const Key("stay-in-game")));
    await tester.pumpAndSettle();
    expect(find.text(exitTitle), findsNothing);
  });
}

Future<void> _open(WidgetTester tester, {required bool warn, required bool host}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => LeaveGate(
              warn: warn,
              host: host,
              child: Scaffold(
                body: Builder(
                  builder: (context) => Column(
                    children: [
                      const Text("in game"),
                      IconButton(
                        tooltip: "Back",
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ));
        },
        child: const Text("open"),
      ),
    ),
  ));
  await tester.tap(find.text("open"));
  await tester.pumpAndSettle();
  expect(find.text("in game"), findsOneWidget);
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byTooltip("Back"));
  await tester.pumpAndSettle();
}

