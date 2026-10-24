import "package:big_two/rules/cards.dart";
import "package:big_two/widgets/playing_card_view.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  testWidgets("a card face stays inside the card", (tester) async {
    for (final width in [74.0, 78.0, 96.0]) {
      for (final selected in [false, true]) {
        for (final scale in [1.0, 1.5]) {
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Center(
                  child: PlayingCardView(card: parseCard("TD"), selected: selected, width: width),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
        }
      }
    }
  });
}
