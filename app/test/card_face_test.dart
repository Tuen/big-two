import "package:big_two/rules/cards.dart";
import "package:big_two/widgets/card_art.dart";
import "package:big_two/widgets/playing_card_view.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("only jack, queen, and king are court cards", () {
    for (var rank = 3; rank <= 10; rank++) {
      expect(isCourt(rank), isFalse, reason: "rank $rank");
    }
    expect(isCourt(14), isFalse);
    expect(isCourt(15), isFalse);
    expect(isCourt(11), isTrue);
    expect(isCourt(12), isTrue);
    expect(isCourt(13), isTrue);
  });

  testWidgets("ace to 10 keep one suit, and a jack uses the same index size", (tester) async {
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
    expect(find.text("J"), findsNWidgets(2));
    expect(find.text("♠"), findsNWidgets(3));
    expect(find.byType(CourtFace), findsOneWidget);
    final tenRank = tester.widget<Text>(find.text("10").first);
    final jackRank = tester.widget<Text>(find.text("J").first);
    expect(jackRank.style!.fontSize, tenRank.style!.fontSize);
    expect(jackRank.style!.fontWeight, tenRank.style!.fontWeight);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(MaterialApp(home: Center(child: PlayingCardView(card: parseCard("7H"), width: 96))));
    expect(find.byType(CourtFace), findsNothing);
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
    expect(find.text("K"), findsNWidgets(2));
  });
}
