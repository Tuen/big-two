import "package:big_two/rules/cards.dart";
import "package:big_two/widgets/card_art.dart";
import "package:big_two/widgets/playing_card_view.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("ace to 10 use the usual number of pips, and courts have none", () {
    expect(pipSpots(14), hasLength(1));
    expect(pipSpots(15), hasLength(2));
    for (var rank = 3; rank <= 10; rank++) {
      expect(pipSpots(rank), hasLength(rank), reason: "rank $rank");
    }
    final seven = pipSpots(7);
    expect(seven.where((spot) => spot.invert), hasLength(2));
    expect(seven.where((spot) => !spot.invert && spot.x == 0.5), hasLength(1));
    expect(pipSpots(11), isEmpty);
    expect(pipSpots(12), isEmpty);
    expect(pipSpots(13), isEmpty);
  });

  testWidgets("7 of hearts, 10 of spades, and the courts show indices", (tester) async {
    Future<void> show(String id, int pips) async {
      await tester.pumpWidget(MaterialApp(home: Center(child: PlayingCardView(card: parseCard(id), width: 96))));
      expect(find.byType(PipMark), findsNWidgets(pips));
      expect(find.text(rankName(parseCard(id).rank)), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    }

    await show("7H", 7);
    await show("TS", 10);
    await show("JH", 0);
    await show("QD", 0);
    await show("KS", 0);
    expect(find.byType(CourtFace), findsOneWidget);
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
