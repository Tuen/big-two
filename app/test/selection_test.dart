import "package:big_two/online/selection.dart";
import "package:big_two/rules/cards.dart";
import "package:big_two/rules/combo.dart";
import "package:big_two/rules/game.dart";
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

  test("the private selection clears when the trick is won or the hand ends", () {
    expect(
      dropSelection(newHand: false, cardsChanged: false, trickWon: false, handEnded: false),
      isFalse,
    );
    expect(
      dropSelection(newHand: false, cardsChanged: false, trickWon: true, handEnded: false),
      isTrue,
    );
    expect(
      dropSelection(newHand: false, cardsChanged: false, trickWon: false, handEnded: true),
      isTrue,
    );
  });
}
