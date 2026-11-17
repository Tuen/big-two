import "package:big_two/rules/cards.dart";
import "package:big_two/widgets/card_face.dart";
import "package:big_two/widgets/playing_card_view.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("only jack, queen, and king are court cards", () {
    for (var rank = 3; rank <= 10; rank++) {
      expect(isCourtRank(rank), isFalse, reason: "rank $rank");
    }
    expect(isCourtRank(14), isFalse);
    expect(isCourtRank(15), isFalse);
    expect(isCourtRank(11), isTrue);
    expect(isCourtRank(12), isTrue);
    expect(isCourtRank(13), isTrue);
  });

  testWidgets("ace to 10 keep one suit, and courts use the Android painter", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlayingCardView(card: parseCard("TS"), width: 96),
              PlayingCardView(card: parseCard("JS"), width: 96),
            ],
          ),
        ),
      ),
    );
    expect(find.text("10"), findsNWidgets(2));
    expect(find.text("♠"), findsNWidgets(2));
    expect(find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is CardFacePainter), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(MaterialApp(home: Center(child: PlayingCardView(card: parseCard("7H"), width: 96))));
    expect(find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is CardFacePainter), findsNothing);
    expect(find.text("7"), findsNWidgets(2));
    expect(find.text("♥"), findsNWidgets(2));
  });

  testWidgets("a small card and a 13-card fan do not overflow", (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final id in ["7H", "TS", "JH", "QD", "KS", "AC"]) {
      await tester.pumpWidget(MaterialApp(home: Center(child: PlayingCardView(card: parseCard(id), width: 40))));
      expect(tester.takeException(), isNull, reason: id);
    }

    final hand = sortCards(parseCards(["3D", "4C", "5H", "6S", "7H", "8D", "9C", "TS", "JH", "QD", "KS", "AH", "2S"]), "rank");
    const width = 390.0;
    const cardWidth = 74.0;
    final gap = ((width - 16 - cardWidth) / (hand.length - 1)).clamp(12.0, cardWidth * 0.62);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: width,
            height: cardWidth * 1.42 + 28,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var index = 0; index < hand.length; index++)
                  Positioned(
                    left: 8 + gap * index,
                    bottom: 0,
                    child: PlayingCardView(card: hand[index], width: cardWidth),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text("10"), findsNWidgets(2));
    expect(find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is CardFacePainter), findsNWidgets(3));
  });
}
