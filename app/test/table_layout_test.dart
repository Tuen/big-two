import "package:big_two/rules/cards.dart";
import "package:big_two/theme.dart";
import "package:big_two/widgets/table_view.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

SeatSpot spot(String name, {bool turn = false, bool passing = false}) {
  return SeatSpot(name: name, cardsLeft: 13, total: 4, turn: turn, passing: passing);
}

void main() {
  final ranks = ["3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A", "2"];
  final hand = [for (final rank in ranks) parseCard("${rank}S")];
  const sizes = <Size>[
    Size(844, 390),
    Size(932, 430),
    Size(667, 375),
    Size(390, 844),
    Size(430, 932),
    Size(1440, 900),
  ];

  for (final size in sizes) {
    testWidgets("pile, previous play, and Play fit at ${size.width.toInt()}x${size.height.toInt()}", (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(MaterialApp(
        theme: bigTwoTheme(),
        home: TableView(
          bottom: spot("Justin", turn: true),
          left: spot("Bot Jade", turn: true),
          top: spot("Bot Pearl"),
          right: spot("Bot Ruby", passing: true),
          hand: hand,
          selected: const {},
          trick: [parseCard("3D"), parseCard("4D"), parseCard("5D"), parseCard("6D"), parseCard("7D")],
          trickLabel: "Straight",
          trickPlayer: "Bot Jade",
          previousCards: [parseCard("KS"), parseCard("KH")],
          previousLabel: "Pair of Ks",
          previousPlayer: "Bot Pearl",
          yourTurn: true,
          canPlay: true,
          canPass: true,
          passLabel: "Pass",
          reason: null,
          banner: "",
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

      expectOnScreen(tester, find.byKey(const Key("pile")), size);
      expectOnScreen(tester, find.byKey(const Key("previous-play")), size);
      expectOnScreen(tester, find.byKey(const Key("play-button")), size);
      if (size.width > size.height && size.height < 500) {
        expect(tester.getSize(find.byKey(const Key("pile"))).height, greaterThanOrEqualTo(90));
      }
      expect(find.text("Bot Jade"), findsOneWidget);
      expect(find.text("Bot Pearl"), findsOneWidget);
      expect(find.text("Bot Ruby"), findsOneWidget);
      expect(find.text("▶ Turn"), findsWidgets);
      expect(find.text("Pass"), findsWidgets);
      expect(find.text("Your turn"), findsOneWidget);
      final play = tester.getRect(find.byKey(const Key("play-button")));
      final undo = tester.getRect(find.byKey(const Key("undo-button")));
      final pass = tester.getRect(find.byKey(const Key("pass-button")));
      expect(play.height, greaterThanOrEqualTo(48));
      expect(undo.height, greaterThanOrEqualTo(48));
      expect(pass.height, greaterThanOrEqualTo(48));
      final landscapePhone = size.width > size.height && size.height < 500;
      if (landscapePhone) {
        expect((play.center.dy - pass.center.dy).abs(), lessThan(4));
        expect((play.center.dy - undo.center.dy).abs(), lessThan(4));
        final boxes = [pass, undo, play]..sort((a, b) => a.left.compareTo(b.left));
        expect(boxes[1].left - boxes[0].right, greaterThanOrEqualTo(8));
        expect(boxes[2].left - boxes[1].right, greaterThanOrEqualTo(8));
        expect(play.width, greaterThanOrEqualTo(48));
        final pile = tester.getRect(find.byKey(const Key("pile")));
        final mine = tester.getRect(find.byKey(const Key("my-score")));
        expect(play.overlaps(pile), isFalse);
        expect(undo.overlaps(pile), isFalse);
        expect(pass.overlaps(pile), isFalse);
        expect(play.overlaps(mine), isFalse);
        expect(tester.getRect(find.text("Bot Jade")).overlaps(play), isFalse);
        expect(tester.getRect(find.text("Bot Pearl")).overlaps(play), isFalse);
        expect(tester.getRect(find.text("Bot Ruby")).overlaps(play), isFalse);
      }
    });
  }
}

void expectOnScreen(WidgetTester tester, Finder finder, Size screen) {
  expect(finder, findsOneWidget);
  final rect = tester.getRect(finder);
  expect(rect.width, greaterThan(0));
  expect(rect.height, greaterThan(0));
  expect(rect.left, greaterThanOrEqualTo(-1));
  expect(rect.top, greaterThanOrEqualTo(-1));
  expect(rect.right, lessThanOrEqualTo(screen.width + 1));
  expect(rect.bottom, lessThanOrEqualTo(screen.height + 1));
}
