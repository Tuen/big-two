import "package:big_two/rules/cards.dart";
import "package:big_two/rules/combo.dart";
import "package:big_two/rules/commit.dart";
import "package:big_two/rules/game.dart";
import "package:big_two/rules/score.dart";
import "package:flutter_test/flutter_test.dart";

const settings = defaultSettings;

Combo mustCombo(List<String> ids, {bool wrap = false}) {
  final found = identify(parseCards(ids), wrap: wrap);
  expect(found, isNotNull, reason: ids.join(" "));
  return found!;
}

void main() {
  test("card points: 9 stays 9, 10-12 double, 13 is 36", () {
    expect(cardPoints(0), 0);
    expect(cardPoints(1), 1);
    expect(cardPoints(8), 8);
    expect(cardPoints(9), 9);
    expect(cardPoints(10), 20);
    expect(cardPoints(11), 22);
    expect(cardPoints(12), 24);
    expect(cardPoints(13), 36);
  });

  test("singles, pairs and triples compare by rank, then suit", () {
    expect(beats(mustCombo(["2D"]), mustCombo(["AS"])), isTrue);
    expect(beats(mustCombo(["AS"]), mustCombo(["AH"])), isTrue);
    expect(beats(mustCombo(["7S", "7D"]), mustCombo(["7H", "7C"])), isTrue);
    expect(beats(mustCombo(["2S", "2H"]), mustCombo(["AS", "AH"])), isTrue);
    expect(beats(mustCombo(["7S"]), mustCombo(["7S", "7H"])), isFalse);
  });

  test("five-card categories and bonuses", () {
    final straight = ["3D", "4C", "5H", "6S", "7D"];
    final flush = ["3S", "5S", "7S", "8S", "9S"];
    final full = ["3D", "3C", "3H", "4S", "4D"];
    final four = ["3D", "3C", "3H", "3S", "9D"];
    final straightFlush = ["3H", "4H", "5H", "6H", "7H"];
    final royal = ["TD", "JD", "QD", "KD", "AD"];
    final ladder = [straight, flush, full, four, straightFlush, royal];
    for (var i = 1; i < ladder.length; i++) {
      expect(beats(mustCombo(ladder[i]), mustCombo(ladder[i - 1])), isTrue, reason: ladder[i].join(" "));
    }
    expect(mustCombo(four).bonusEach, 5);
    expect(mustCombo(straightFlush).bonusEach, 8);
    expect(mustCombo(royal).bonusEach, 10);
    expect(mustCombo(straightFlush).bonusName, "straight flush");
  });

  test("flushes rank by suit, then by cards", () {
    expect(
      beats(mustCombo(["3S", "4S", "5S", "6S", "8S"]), mustCombo(["9H", "JH", "QH", "KH", "AH"])),
      isTrue,
    );
    expect(
      beats(mustCombo(["TH", "JH", "QH", "KH", "AH"]), mustCombo(["3H", "4H", "5H", "6H", "8H"])),
      isTrue,
    );
    expect(
      beats(mustCombo(["3D", "4D", "5D", "6D", "8D"]), mustCombo(["9C", "TC", "JC", "QC", "KC"])),
      isFalse,
    );
  });

  test("straights run from 3-4-5-6-7 to J-Q-K-A-2 and never wrap past the 2", () {
    expect(mustCombo(["3C", "4D", "5H", "6S", "7D"]).kind, ComboKind.straight);
    expect(mustCombo(["3C", "4D", "5H", "6S", "7D"]).key[1], 2);
    expect(beats(mustCombo(["JC", "QD", "KH", "AS", "2D"]), mustCombo(["TC", "JH", "QD", "KS", "AD"])), isTrue);
    expect(beats(mustCombo(["JC", "QD", "KH", "AS", "2S"]), mustCombo(["JC", "QD", "KH", "AS", "2D"])), isTrue);
    expect(beats(mustCombo(["3D", "4C", "5H", "6D", "7S"]), mustCombo(["3C", "4D", "5C", "6C", "7H"])), isTrue);
    for (final wrap in [false, true]) {
      expect(identify(parseCards(["AD", "2C", "3H", "4S", "5D"]), wrap: wrap), isNull);
      expect(identify(parseCards(["2D", "3C", "4H", "5S", "6D"]), wrap: wrap), isNull);
      expect(identify(parseCards(["QD", "KC", "AH", "2S", "3D"]), wrap: wrap), isNull);
      expect(identify(parseCards(["KD", "AC", "2H", "3S", "4D"]), wrap: wrap), isNull);
    }
  });

  test("straight flushes rank by suit, then by the cards, and royals are higher", () {
    expect(beats(mustCombo(["3S", "4S", "5S", "6S", "7S"]), mustCombo(["9H", "TH", "JH", "QH", "KH"])), isTrue);
    expect(beats(mustCombo(["9H", "TH", "JH", "QH", "KH"]), mustCombo(["3S", "4S", "5S", "6S", "7S"])), isFalse);
    expect(
      beats(mustCombo(["TD", "JD", "QD", "KD", "AD"]), mustCombo(["3S", "4S", "5S", "6S", "7S"])),
      isTrue,
    );
    expect(mustCombo(["AD", "2D", "3D", "4D", "5D"]).kind, ComboKind.flush);
    expect(mustCombo(["AD", "2D", "3D", "4D", "5D"]).bonusEach, 0);
    expect(mustCombo(["2D", "3D", "4D", "5D", "6D"]).kind, ComboKind.flush);
    expect(mustCombo(["2D", "3D", "4D", "5D", "6D"]).bonusEach, 0);
    expect(identify(parseCards(["AD", "2D", "3D", "4D", "5D"]), wrap: true)?.kind, ComboKind.flush);
    expect(beats(mustCombo(["TS", "JS", "QS", "KS", "AS"]), mustCombo(["TD", "JD", "QD", "KD", "AD"])), isTrue);
    expect(mustCombo(["JH", "QH", "KH", "AH", "2H"]).kind, ComboKind.straightFlush);
    expect(mustCombo(["JS", "QS", "KS", "AS", "2S"]).kind, ComboKind.straightFlush);
    expect(beats(mustCombo(["JS", "QS", "KS", "AS", "2S"]), mustCombo(["JH", "QH", "KH", "AH", "2H"])), isTrue);
    expect(beats(mustCombo(["TD", "JD", "QD", "KD", "AD"]), mustCombo(["JH", "QH", "KH", "AH", "2H"])), isTrue);
    expect(beats(mustCombo(["TD", "JD", "QD", "KD", "AD"]), mustCombo(["JS", "QS", "KS", "AS", "2S"])), isTrue);
    expect(beats(mustCombo(["9S", "TS", "JS", "QS", "KS"]), mustCombo(["3S", "4S", "5S", "6S", "7S"])), isTrue);
    expect(beats(mustCombo(["9S", "TS", "JS", "QS", "KS"]), mustCombo(["9H", "TH", "JH", "QH", "KH"])), isTrue);
  });

  test("full houses use the triple and fours ignore the kicker", () {
    expect(beats(mustCombo(["2D", "2C", "2H", "3S", "3D"]), mustCombo(["AD", "AC", "AH", "KS", "KD"])), isTrue);
    expect(beats(mustCombo(["AD", "AC", "AH", "AS", "3D"]), mustCombo(["KD", "KC", "KH", "KS", "2S"])), isTrue);
    expect(
      beats(mustCombo(["5D", "5C", "5H", "5S", "3D"]), mustCombo(["5D", "5C", "5H", "5S", "2S"])),
      isFalse,
    );
  });

  test("invalid shapes are rejected", () {
    expect(identify(parseCards(const [])), isNull);
    expect(identify(parseCards(["3D", "3C", "4H", "4S"])), isNull);
    expect(identify(parseCards(["3D", "3C", "3H", "4S", "5D"])), isNull);
    expect(identify(parseCards(["3D", "4C", "5H", "6S", "8D"])), isNull);
  });

  test("the opening lead must include the 3 of diamonds", () {
    final state = makeState(hands: [
      parseCards(["3D", "4C"]),
      parseCards(["5H", "8C"]),
      parseCards(["6S"]),
      parseCards(["7D"]),
    ], turn: 0, firstLead: true);
    final missing = applyPlay(state, 0, ["4C"], settings);
    expect(missing, isA<StepBad>());
    expect((missing as StepBad).message, contains("3"));
    final ok = applyPlay(state, 0, ["3D"], settings) as StepOk;
    expect(ok.state.firstLead, isFalse);
  });

  test("you cannot go out on only 2s, but a five-card hand with a 2 can", () {
    final others = [parseCards(["3D"]), parseCards(["4C"]), parseCards(["5H"])];
    for (final ids in [
      ["2S"],
      ["2S", "2H"],
      ["2S", "2H", "2C"],
    ]) {
      final state = makeState(hands: [parseCards(ids), ...others], turn: 0);
      final blocked = applyPlay(state, 0, ids, settings);
      expect(blocked, isA<StepBad>());
      expect((blocked as StepBad).message, contains("2s"));
      expect(state.hands[0], hasLength(ids.length));
    }

    final four = makeState(hands: [parseCards(["2D", "2C", "2H", "2S"]), ...others], turn: 0);
    expect(applyPlay(four, 0, ["2D", "2C", "2H", "2S"], settings), isA<StepBad>());
    final keptOne = applyPlay(four, 0, ["2D", "2C", "2H"], settings) as StepOk;
    expect(keptOne.state.hands[0].map(formatCard).join(","), "2S");

    final withTwo = makeState(hands: [parseCards(["2S", "9C"]), ...others], turn: 0);
    final lead = applyPlay(withTwo, 0, ["2S"], settings) as StepOk;
    expect(lead.state.hands[0].map(formatCard).join(","), "9C");

    final five = makeState(hands: [parseCards(["JD", "QD", "KD", "AD", "2D"]), ...others], turn: 0);
    final won = applyPlay(five, 0, ["JD", "QD", "KD", "AD", "2D"], settings) as StepOk;
    expect(won.state.winner, 0);
    expect(won.result!.cardsLeft[0], 0);

    final fours = makeState(hands: [parseCards(["2D", "2C", "2H", "2S", "9D"]), ...others], turn: 0);
    final fourWon = applyPlay(fours, 0, ["2D", "2C", "2H", "2S", "9D"], settings) as StepOk;
    expect(fourWon.state.winner, 0);

    final house = makeState(hands: [parseCards(["2D", "2C", "2H", "5S", "5D"]), ...others], turn: 0);
    final houseWon = applyPlay(house, 0, ["2D", "2C", "2H", "5S", "5D"], settings) as StepOk;
    expect(houseWon.state.winner, 0);
    expect(houseWon.state.trick!.kind, ComboKind.fullHouse);
  });

  test("going out on only 2s is refused in every shape, and a five with a 2 can finish", () {
    final others = [parseCards(["3D", "4D"]), parseCards(["5C", "6C"]), parseCards(["7H", "8H"])];
    HandState seat(List<String> ids, {Combo? trick, int? trickSeat, List<String>? trickCards}) {
      return makeState(
        hands: [parseCards(ids), ...others],
        turn: 0,
        trick: trick,
        trickSeat: trickSeat,
        trickCards: trickCards,
      );
    }

    for (final ids in [
      ["2D"],
      ["2S"],
      ["2D", "2C"],
      ["2S", "2H"],
      ["2D", "2C", "2H"],
      ["2S", "2H", "2C"],
    ]) {
      final state = seat(ids);
      final blocked = applyPlay(state, 0, ids, settings);
      expect(blocked, isA<StepBad>(), reason: ids.join(" "));
      expect((blocked as StepBad).message, "You can't go out if you only have 2s");
      expect(playIssue(state, 0, parseCards(ids), settings), "You can't go out if you only have 2s");
    }

    final overSingle = seat(["2H"], trick: mustCombo(["KD"]), trickSeat: 3, trickCards: ["KD"]);
    final overPair = seat(["2S", "2D"], trick: mustCombo(["AH", "AC"]), trickSeat: 3, trickCards: ["AH", "AC"]);
    final overTriple = seat(
      ["2S", "2H", "2C"],
      trick: mustCombo(["AD", "AC", "AH"]),
      trickSeat: 3,
      trickCards: ["AD", "AC", "AH"],
    );
    for (final state in [overSingle, overPair, overTriple]) {
      final cards = state.hands[0].map(formatCard).toList();
      final blocked = applyPlay(state, 0, cards, settings);
      expect(blocked, isA<StepBad>(), reason: cards.join(" "));
      expect((blocked as StepBad).message, "You can't go out if you only have 2s");
    }

    final four = seat(["2D", "2C", "2H", "2S"]);
    expect(applyPlay(four, 0, ["2D", "2C", "2H", "2S"], settings), isA<StepBad>());
    final shed = applyPlay(four, 0, ["2D", "2C", "2H"], settings) as StepOk;
    final again = makeState(
      hands: shed.state.hands,
      turn: 0,
      running: shed.state.running,
    );
    expect(applyPlay(again, 0, ["2S"], settings), isA<StepBad>());
    expect(applyPass(again, 0, settings), isA<StepOk>());

    final three = seat(["2S", "2H", "2C"]);
    expect(passIssue(three, 0, settings), contains("must lead"));
    final oneOfThree = applyPlay(three, 0, ["2C"], settings) as StepOk;
    final back = makeState(hands: oneOfThree.state.hands, turn: 0, running: oneOfThree.state.running);
    expect(applyPlay(back, 0, ["2S", "2H"], settings), isA<StepBad>());

    expect(automaticLastCard(seat(["2S"]), 0, settings), isNull);
    expect(automaticLastCard(overSingle, 0, settings), isNull);
    expect(applyPass(seat(["2S"], trick: mustCombo(["9D"]), trickSeat: 3, trickCards: ["9D"]), 0, settings), isA<StepOk>());

    final finishes = <(List<String>, ComboKind)>[
      (["JH", "QD", "KC", "AS", "2D"], ComboKind.straight),
      (["2H", "4H", "6H", "8H", "TH"], ComboKind.flush),
      (["AH", "2H", "3H", "4H", "5H"], ComboKind.flush),
      (["2D", "3D", "4D", "5D", "6D"], ComboKind.flush),
      (["2D", "2C", "2H", "5S", "5D"], ComboKind.fullHouse),
      (["9D", "9C", "9H", "2S", "2D"], ComboKind.fullHouse),
      (["2D", "2C", "2H", "2S", "9D"], ComboKind.four),
      (["9D", "9C", "9H", "9S", "2C"], ComboKind.four),
      (["JD", "QD", "KD", "AD", "2D"], ComboKind.straightFlush),
      (["JS", "QS", "KS", "AS", "2S"], ComboKind.straightFlush),
    ];
    for (final row in finishes) {
      final ids = row.$1;
      final kind = row.$2;
      final won = applyPlay(seat(ids), 0, ids, settings) as StepOk;
      expect(won.state.winner, 0, reason: ids.join(" "));
      expect(won.state.hands[0], isEmpty);
      expect(won.state.trick!.kind, kind);
      expect(won.result!.cardsLeft[0], 0);
    }

    final followed = seat(
      ["JS", "QS", "KS", "AS", "2S"],
      trick: mustCombo(["3D", "4C", "5H", "6S", "7D"]),
      trickSeat: 3,
      trickCards: ["3D", "4C", "5H", "6S", "7D"],
    );
    final beatFive = applyPlay(followed, 0, ["JS", "QS", "KS", "AS", "2S"], settings) as StepOk;
    expect(beatFive.state.winner, 0);
  });

  test("pass lock lasts until the trick is won", () {
    var state = makeState(
      hands: [parseCards(["9C"]), parseCards(["4C"]), parseCards(["5H"]), parseCards(["6S"])],
      turn: 1,
      trick: mustCombo(["KS"]),
      trickSeat: 0,
      trickCards: ["KS"],
    );
    for (final seat in [1, 2, 3]) {
      final step = applyPass(state, seat, settings) as StepOk;
      state = step.state;
    }
    expect(state.trick, isNull);
    expect(state.turn, 0);

    final locked = settings.copyWith(passLocks: true);
    state = makeState(
      hands: [
        parseCards(["9C"]),
        parseCards(["AS", "3D"]),
        parseCards(["2S", "4C"]),
        parseCards(["5H"]),
      ],
      turn: 1,
      trick: mustCombo(["KS"]),
      trickSeat: 0,
      trickCards: ["KS"],
    );
    state = (applyPass(state, 1, locked) as StepOk).state;
    state = (applyPlay(state, 2, ["2S"], locked) as StepOk).state;
    state = (applyPass(state, 3, locked) as StepOk).state;
    state = (applyPass(state, 0, locked) as StepOk).state;
    expect(state.turn, 1);
    expect(state.locked, [1, 3, 0]);
    final retry = applyPlay(state, 1, ["AS"], locked) as StepBad;
    expect(retry.message.toLowerCase(), contains("passed"));
  });

  test("bonuses are immediate and the worked example scores the round", () {
    final state = makeState(
      hands: [
        parseCards(["9C"]),
        parseCards(["4C"]),
        parseCards(["5H"]),
        parseCards(["3D", "4D", "5D", "6D", "7D", "TC", "JC", "QC", "KC"]),
      ],
      turn: 3,
      running: [20, 30, 38, 45],
    );
    final played = applyPlay(state, 3, ["3D", "4D", "5D", "6D", "7D"], settings) as StepOk;
    expect(played.state.running, [28, 38, 46, 45]);
    expect(played.state.status, "playing");
    expect(played.result, isNull);

    final bonuses = [const Bonus(seat: 3, kind: "straight_flush", combo: "straight flush", pointsEach: 8)];
    final score = scoreCounts([0, 11, 9, 4], [28, 38, 46, 45], bonuses);
    expect(score.cardPointList, [0, 22, 9, 4]);
    expect(score.bonusReceived, [8, 8, 8, 0]);
    expect(score.handPoints, [8, 30, 17, 4]);
    expect(score.runningTotals, [28, 60, 55, 49]);
    expect(score.roundOver, isTrue);
    final body = webhookPayload(
      handId: "hand-1",
      tableCode: "ABC123",
      season: 24,
      round: 11,
      hand: 3,
      date: "2026-10-23",
      players: ["Justin", "Mary", "Pauline", "Damien"],
      cardsLeft: score.cardsLeft,
      handPoints: score.handPoints,
      runningTotals: score.runningTotals,
      roundOver: score.roundOver,
      bonuses: bonuses,
    );
    expect(body.tableCode, "ABC123");
    expect(body.roundWinner, "Justin");
    expect(body.hasBots, isFalse);
    expect(body.bots, isEmpty);
    expect(roundWinnerName(["Justin", "Mary"], [12, 12], false), isNull);
    expect(roundWinnerName(["Justin", "Mary"], [12, 12], true), "Justin, Mary");
    expect(body.bonuses, [
      {"player": "Damien", "combo": "straight flush", "pointsEach": 8},
    ]);
  });

  test("a finishing royal flush is scored before the round check", () {
    final state = makeState(
      hands: [
        parseCards(["9C", "TC", "JC"]),
        parseCards(["4C"]),
        parseCards(["5H"]),
        parseCards(["TD", "JD", "QD", "KD", "AD"]),
      ],
      turn: 3,
      running: [40, 10, 10, 10],
    );
    final won = applyPlay(state, 3, ["TD", "JD", "QD", "KD", "AD"], settings) as StepOk;
    expect(won.state.running, [50, 20, 20, 10]);
    expect(won.result!.handPoints, [13, 11, 11, 0]);
    expect(won.result!.runningTotals, [53, 21, 21, 10]);
    expect(won.result!.roundOver, isTrue);
  });

  test("49 does not end the round and a tie shares the win", () {
    final under = scoreCounts([1, 1, 1, 1], [10, 20, 30, 48], []);
    expect(under.runningTotals, [11, 21, 31, 49]);
    expect(under.roundOver, isFalse);
    expect(scoreCounts([0, 0, 0, 1], [50, 10, 10, 10], []).roundOver, isTrue);
    expect(roundWinners([12, 12, 40, 51]), [0, 1]);
    expect(cardPoints(13), 36);
    expect(scoreCounts([0, 13, 9, 10], [0, 0, 0, 0], []).cardPointList, [0, 36, 9, 20]);
  });

  test("a stuck deuce passes the lead, and four skips close the hand", () {
    final skip = applyPass(
      makeState(hands: [parseCards(["2S"]), parseCards(["3D"]), parseCards(["4C"]), parseCards(["5H"])], turn: 0),
      0,
      settings,
    ) as StepOk;
    expect(skip.state.turn, 1);
    expect(skip.state.status, "playing");

    var state = makeState(
      hands: [parseCards(["2D"]), parseCards(["2C"]), parseCards(["2H"]), parseCards(["2S"])],
      turn: 0,
    );
    for (var i = 0; i < 3; i++) {
      state = (applyPass(state, state.turn, settings) as StepOk).state;
      expect(state.status, "playing");
    }
    final closed = applyPass(state, state.turn, settings) as StepOk;
    expect(closed.state.closedReason, "stuck");
    expect(closed.result!.cardsLeft, [1, 1, 1, 1]);
    expect(closed.result!.winner, isNull);
  });

  test("the timer passes or leads the lowest single", () {
    final following = makeState(
      hands: [parseCards(["AS"]), parseCards(["3D"]), parseCards(["4C"]), parseCards(["5H"])],
      turn: 1,
      trick: mustCombo(["KS"]),
      trickSeat: 0,
      trickCards: ["KS"],
    );
    final passed = applyTimeout(following, settings.copyWith(turnTimerSeconds: 30)) as StepOk;
    expect(passed.state.turn, 2);

    final leading = makeState(
      hands: [parseCards(["9C", "AS", "3D"]), parseCards(["4C", "6H"]), parseCards(["5H"]), parseCards(["6S"])],
      turn: 0,
    );
    expect(lowestLegalPlay(leading, 0, settings), ["3D"]);
  });

  test("the deal gives 13 cards and later hands follow the previous winner", () {
    final deck = fullDeck();
    final state = startHand(deck, [0, 0, 0, 0], true, null);
    expect(state.hands.map((hand) => hand.length).toList(), [13, 13, 13, 13]);
    expect(state.hands[state.turn].any((card) => formatCard(card) == "3D"), isTrue);
    final later = startHand(deck, [1, 2, 3, 4], false, 2);
    expect(later.turn, 2);
    expect(later.firstLead, isFalse);
    final step = applyPlay(later, 2, [formatCard(later.hands[2].first)], settings);
    expect(step, isA<StepOk>());
  });

  test("shuffle rejection sampling and the commitment", () {
    var calls = 0;
    const values = [0xffffffff, 0];
    final index = indexBelow(3, () {
      calls += 1;
      return values[calls - 1];
    });
    expect(index, 0);
    expect(calls, 2);

    final items = ["A", "B", "C", "D"];
    const draws = [5, 0, 1];
    var cursor = 0;
    shuffleInPlace(items, () => draws[cursor++]);
    expect(items, ["C", "D", "A", "B"]);

    final deck = shuffleDeck();
    expect(deck.map(formatCard).toSet(), hasLength(52));
    final committed = commitDeck(deck);
    expect(committed.commitment, commitDeck(deck).commitment);
    expect(committed.commitment, hasLength(64));
    final sorted = sortCards(parseCards(committed.canonical.split(",")), "rank");
    expect(formatCard(sorted.first), "3D");
    expect(formatCard(sorted.last), "2S");
  });

  test("a single must be the highest card when the next player has one card", () {
    final ahead = makeState(
      hands: [
        parseCards(["3D", "9C", "KS", "AH", "4D", "4C"]),
        parseCards(["2S"]),
        parseCards(["5H", "6H"]),
        parseCards(["7D", "8D"]),
      ],
      turn: 0,
    );
    final low = applyPlay(ahead, 0, ["9C"], settings) as StepBad;
    expect(low.message, highestSingleMessage);
    expect(applyPlay(ahead, 0, ["KS"], settings), isA<StepBad>());
    final highest = applyPlay(ahead, 0, ["AH"], settings) as StepOk;
    expect(highest.state.trickCards, ["AH"]);
    expect(applyPlay(ahead, 0, ["4D", "4C"], settings), isA<StepOk>());

    final straight = makeState(
      hands: [
        parseCards(["5D", "6C", "7H", "8S", "9D", "3C"]),
        parseCards(["QS"]),
        parseCards(["4H", "TC"]),
        parseCards(["JD"]),
      ],
      turn: 0,
    );
    final five = applyPlay(straight, 0, ["5D", "6C", "7H", "8S", "9D"], settings) as StepOk;
    expect(five.state.trick!.kind, ComboKind.straight);

    final lead = makeState(
      hands: [
        parseCards(["7C", "AS", "2D"]),
        parseCards(["4S"]),
        parseCards(["5C", "6C"]),
        parseCards(["8H", "9H"]),
      ],
      turn: 0,
    );
    final lowLead = applyPlay(lead, 0, ["7C"], settings) as StepBad;
    expect(lowLead.message, contains("highest single"));
    expect(applyPlay(lead, 0, ["2D"], settings), isA<StepOk>());

    final quiet = makeState(
      hands: [
        parseCards(["3D", "9C", "KS"]),
        parseCards(["4C", "5C"]),
        parseCards(["2H"]),
        parseCards(["6D", "7D"]),
      ],
      turn: 0,
    );
    expect(applyPlay(quiet, 0, ["3D"], settings), isA<StepOk>());

    final elsewhere = makeState(
      hands: [
        parseCards(["3D", "9C"]),
        parseCards(["4C", "5C", "6C"]),
        parseCards(["2S"]),
        parseCards(["7H", "8H"]),
      ],
      turn: 0,
    );
    expect(applyPlay(elsewhere, 0, ["3D"], settings), isA<StepOk>());

    final following = makeState(
      hands: [
        parseCards(["6C", "AS", "4D", "4H"]),
        parseCards(["3S"]),
        parseCards(["9D", "TC"]),
        parseCards(["JD"]),
      ],
      turn: 0,
      trick: mustCombo(["5D"]),
      trickSeat: 3,
      trickCards: ["5D"],
    );
    final beatsButLow = applyPlay(following, 0, ["6C"], settings) as StepBad;
    expect(beatsButLow.message, highestSingleMessage);
    expect(applyPlay(following, 0, ["AS"], settings), isA<StepOk>());
    final passed = applyPass(following, 0, settings) as StepBad;
    expect(passed.message, mustPlayHighestMessage);
  });

  test("following a non-2 single forces the highest card when the next player has one", () {
    final state = makeState(
      hands: [
        parseCards(["3D", "KS", "2H"]),
        parseCards(["QS"]),
        parseCards(["4C", "5C"]),
        parseCards(["6D", "7D"]),
      ],
      turn: 0,
      trick: mustCombo(["8D"]),
      trickSeat: 3,
      trickCards: ["8D"],
    );
    expect((applyPlay(state, 0, ["KS"], settings) as StepBad).message, highestSingleMessage);
    expect(applyPlay(state, 0, ["2H"], settings), isA<StepOk>());
    expect((applyPass(state, 0, settings) as StepBad).message, mustPlayHighestMessage);

    final deuceOnly = makeState(
      hands: [
        parseCards(["2S"]),
        parseCards(["QS"]),
        parseCards(["4C", "5C"]),
        parseCards(["6D"]),
      ],
      turn: 0,
      trick: mustCombo(["8D"]),
      trickSeat: 3,
      trickCards: ["8D"],
    );
    expect(applyPass(deuceOnly, 0, settings), isA<StepOk>());
  });

  test("a 2 on the table may be passed, and a single played must still be the highest", () {
    final state = makeState(
      hands: [
        parseCards(["9C", "2C", "2S"]),
        parseCards(["QS"]),
        parseCards(["4C", "5C"]),
        parseCards(["6D", "7D"]),
      ],
      turn: 0,
      trick: mustCombo(["2D"]),
      trickSeat: 3,
      trickCards: ["2D"],
    );
    expect(applyPass(state, 0, settings), isA<StepOk>());
    expect((applyPlay(state, 0, ["2C"], settings) as StepBad).message, highestSingleMessage);
    expect(applyPlay(state, 0, ["2S"], settings), isA<StepOk>());
  });

  test("passing is allowed when the highest card cannot beat the single", () {
    final state = makeState(
      hands: [
        parseCards(["3D", "KH", "AH"]),
        parseCards(["QS"]),
        parseCards(["4C", "5C"]),
        parseCards(["6D", "7D"]),
      ],
      turn: 0,
      trick: mustCombo(["AS"]),
      trickSeat: 3,
      trickCards: ["AS"],
    );
    expect(applyPlay(state, 0, ["AH"], settings), isA<StepBad>());
    expect(applyPass(state, 0, settings), isA<StepOk>());
  });

  test("a normal single is not forced when the next player has more than one card", () {
    final state = makeState(
      hands: [
        parseCards(["3D", "7C", "AS"]),
        parseCards(["QS", "4C"]),
        parseCards(["2H"]),
        parseCards(["6D", "7D"]),
      ],
      turn: 0,
      trick: mustCombo(["5D"]),
      trickSeat: 3,
      trickCards: ["5D"],
    );
    expect(applyPlay(state, 0, ["7C"], settings), isA<StepOk>());
    expect(applyPass(state, 0, settings), isA<StepOk>());
  });

  test("a lone legal card is played automatically, and an illegal one is not", () {
    final others = [parseCards(["9C", "4C"]), parseCards(["6H", "7H"]), parseCards(["8D", "TD"])];
    final lead = makeState(hands: [parseCards(["5D"]), ...others], turn: 0);
    expect(automaticLastCard(lead, 0, settings), "5D");
    expect(lastCardMessage("Ada"), "Ada plays their last card");

    final two = makeState(hands: [parseCards(["2H"]), ...others], turn: 0);
    expect(automaticLastCard(two, 0, settings), isNull);

    final low = makeState(
      hands: [parseCards(["3D"]), ...others],
      turn: 0,
      trick: mustCombo(["KD"]),
      trickSeat: 1,
      trickCards: ["KD"],
    );
    expect(automaticLastCard(low, 0, settings), isNull);

    final againstPair = makeState(
      hands: [parseCards(["KD"]), ...others],
      turn: 0,
      trick: mustCombo(["4C", "4D"]),
      trickSeat: 1,
      trickCards: ["4C", "4D"],
    );
    expect(automaticLastCard(againstPair, 0, settings), isNull);

    final beat = makeState(
      hands: [parseCards(["AS"]), ...others],
      turn: 0,
      trick: mustCombo(["5D"]),
      trickSeat: 1,
      trickCards: ["5D"],
    );
    expect(automaticLastCard(beat, 0, settings), "AS");
    final won = applyPlay(beat, 0, ["AS"], settings) as StepOk;
    expect(won.state.status, "complete");
    expect(won.state.winner, 0);
  });

  test("a follower with no legal play is an auto-pass, and a leader is not", () {
    final others = [parseCards(["9C", "4C"]), parseCards(["6H", "7H"]), parseCards(["8D", "TD"])];
    final pair = makeState(
      hands: [parseCards(["3D", "4C", "5H", "6S", "9C"]), ...others],
      turn: 0,
      trick: mustCombo(["8C", "8D"]),
      trickSeat: 3,
      trickCards: ["8C", "8D"],
    );
    expect(shouldAutoPass(pair, 0, settings), isTrue);
    expect(legalSelections(pair, 0, settings), isEmpty);

    final straight = makeState(
      hands: [parseCards(["JH", "QD", "KC", "AS", "2C"]), ...others],
      turn: 0,
      trick: mustCombo(["3C", "4D", "5H", "6S", "7C"]),
      trickSeat: 1,
      trickCards: ["3C", "4D", "5H", "6S", "7C"],
    );
    expect(shouldAutoPass(straight, 0, settings), isFalse);
    expect(playIssue(straight, 0, parseCards(["JH", "QD", "KC", "AS", "2C"]), settings), isNull);

    final wrapped = makeState(
      hands: [parseCards(["AH", "2D", "3C", "4S", "5H"]), ...others],
      turn: 0,
      trick: mustCombo(["9C", "9D"]),
      trickSeat: 2,
      trickCards: ["9C", "9D"],
    );
    expect(identify(parseCards(["AH", "2D", "3C", "4S", "5H"])), isNull);
    expect(shouldAutoPass(wrapped, 0, settings), isTrue);

    final lead = makeState(hands: [parseCards(["2S", "2H"]), ...others], turn: 0);
    expect(shouldAutoPass(lead, 0, settings), isFalse);

    final onlyTwo = makeState(
      hands: [parseCards(["2H"]), ...others],
      turn: 0,
      trick: mustCombo(["5D"]),
      trickSeat: 1,
      trickCards: ["5D"],
    );
    expect(automaticLastCard(onlyTwo, 0, settings), isNull);
    expect(shouldAutoPass(onlyTwo, 0, settings), isTrue);

    final forced = makeState(
      hands: [parseCards(["3C", "AS"]), parseCards(["QS"]), parseCards(["4C", "5C"]), parseCards(["6D", "7D"])],
      turn: 0,
      trick: mustCombo(["5D"]),
      trickSeat: 3,
      trickCards: ["5D"],
    );
    expect(mustPlayHighestSingle(forced, 0, settings), isTrue);
    expect(shouldAutoPass(forced, 0, settings), isFalse);

    final stuckLead = makeState(hands: [parseCards(["2H"]), ...others], turn: 0);
    expect(stuckOnTwos(stuckLead, 0, settings), isTrue);
    expect(shouldAutoPass(stuckLead, 0, settings), isFalse);
    expect(passIssue(stuckLead, 0, settings), isNull);
    final passedLead = applyPass(stuckLead, 0, settings) as StepOk;
    expect(passedLead.state.turn, 1);
    expect(passedLead.state.trick, isNull);
    final nextLead = applyPlay(passedLead.state, 1, ["4C"], settings);
    expect(nextLead.ok, isTrue);

    final twoTwos = makeState(hands: [parseCards(["2H", "2D"]), ...others], turn: 0);
    expect(stuckOnTwos(twoTwos, 0, settings), isFalse);
    expect(passIssue(twoTwos, 0, settings), "You must lead — passing isn't allowed");
  });
}
