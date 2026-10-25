import assert from "node:assert/strict";
import test from "node:test";
import { formatCard, fullDeck, parseCards, sortCards } from "../../supabase/functions/_shared/rules/cards.ts";
import { beats, identify } from "../../supabase/functions/_shared/rules/combo.ts";
import {
  applyPass,
  applyPlay,
  applyTimeout,
  automaticLastCard,
  HIGHEST_SINGLE_MESSAGE,
  lastCardMessage,
  MUST_PLAY_HIGHEST_MESSAGE,
  lowestLegalPlay,
  makeState,
  passIssue,
  playIssue,
  replay,
  roundWinners,
  startHand,
} from "../../supabase/functions/_shared/rules/game.ts";
import { DEFAULT_SETTINGS, type Settings } from "../../supabase/functions/_shared/rules/game.ts";
import { cardPoints, roundWinnerName, scoreCounts, webhookPayload } from "../../supabase/functions/_shared/rules/score.ts";
import { commitDeck, indexBelow, shuffleDeck, shuffleInPlace } from "../../supabase/functions/_shared/rules/shuffle.ts";

const settings: Settings = { ...DEFAULT_SETTINGS };

function combo(ids: string[], wrap = false) {
  const found = identify(parseCards(ids), wrap);
  assert.ok(found, ids.join(" "));
  return found;
}

function key(ids: string[], wrap = false): number[] {
  return combo(ids, wrap).key;
}

test("card points: 9 stays 9, 10-12 double, 13 is 36", () => {
  assert.equal(cardPoints(0), 0);
  assert.equal(cardPoints(1), 1);
  assert.equal(cardPoints(8), 8);
  assert.equal(cardPoints(9), 9);
  assert.equal(cardPoints(10), 20);
  assert.equal(cardPoints(11), 22);
  assert.equal(cardPoints(12), 24);
  assert.equal(cardPoints(13), 36);
});

test("singles, pairs and triples compare by rank, then suit", () => {
  assert.ok(beats(combo(["2D"]), combo(["AS"])));
  assert.ok(beats(combo(["AS"]), combo(["AH"])));
  assert.ok(beats(combo(["AH"]), combo(["AC"])));
  assert.ok(beats(combo(["AC"]), combo(["AD"])));
  assert.equal(beats(combo(["7H"]), combo(["7S"])), false);
  assert.ok(beats(combo(["7S", "7D"]), combo(["7H", "7C"])));
  assert.ok(beats(combo(["2S", "2H"]), combo(["AS", "AH"])));
  assert.ok(beats(combo(["KS", "KH", "KD"]), combo(["QS", "QH", "QC"])));
  assert.equal(beats(combo(["7S"]), combo(["7S", "7H"])), false);
});

test("five-card categories rank straight < flush < full house < four < straight flush < royal", () => {
  const straight = ["3D", "4C", "5H", "6S", "7D"];
  const flush = ["3S", "5S", "7S", "8S", "9S"];
  const full = ["3D", "3C", "3H", "4S", "4D"];
  const four = ["3D", "3C", "3H", "3S", "9D"];
  const straightFlush = ["3H", "4H", "5H", "6H", "7H"];
  const royal = ["TD", "JD", "QD", "KD", "AD"];
  const ladder = [straight, flush, full, four, straightFlush, royal];
  for (let i = 1; i < ladder.length; i++) {
    assert.ok(beats(combo(ladder[i]), combo(ladder[i - 1])), ladder[i].join(" "));
  }
  assert.equal(combo(four).bonusEach, 5);
  assert.equal(combo(straightFlush).bonusEach, 8);
  assert.equal(combo(royal).bonusEach, 10);
  assert.equal(combo(straightFlush).bonusName, "straight flush");
  assert.equal(combo(full).bonusEach, 0);
});

test("flushes rank by suit, and only then by cards", () => {
  const lowSpades = ["3S", "4S", "5S", "6S", "8S"];
  const highHearts = ["9H", "JH", "QH", "KH", "AH"];
  assert.equal(combo(lowSpades).kind, "flush");
  assert.ok(beats(combo(lowSpades), combo(highHearts)));
  const highHearts2 = ["TH", "JH", "QH", "KH", "AH"];
  const lowHearts = ["3H", "4H", "5H", "6H", "8H"];
  assert.ok(beats(combo(highHearts2), combo(lowHearts)));
  assert.equal(beats(combo(["3D", "4D", "5D", "6D", "8D"]), combo(["9C", "TC", "JC", "QC", "KC"])), false);
});

test("straights run from 3-4-5-6-7 to J-Q-K-A-2 and never wrap past the 2", () => {
  const low = ["3C", "4D", "5H", "6S", "7D"];
  const aceHigh = ["TC", "JH", "QD", "KS", "AD"];
  const twoHigh = ["JC", "QD", "KH", "AS", "2D"];
  const twoHighSpade = ["JC", "QD", "KH", "AS", "2S"];
  assert.equal(combo(low).kind, "straight");
  assert.equal(key(low)[1], 2);
  assert.ok(beats(combo(aceHigh), combo(low)));
  assert.ok(beats(combo(twoHigh), combo(aceHigh)));
  assert.ok(beats(combo(twoHighSpade), combo(twoHigh)));
  const sevenSpades = ["3D", "4C", "5H", "6D", "7S"];
  const sevenHearts = ["3C", "4D", "5C", "6C", "7H"];
  assert.ok(beats(combo(sevenSpades), combo(sevenHearts)));
  for (const wrap of [false, true]) {
    assert.equal(identify(parseCards(["AD", "2C", "3H", "4S", "5D"]), wrap), null);
    assert.equal(identify(parseCards(["2D", "3C", "4H", "5S", "6D"]), wrap), null);
    assert.equal(identify(parseCards(["QD", "KC", "AH", "2S", "3D"]), wrap), null);
    assert.equal(identify(parseCards(["KD", "AC", "2H", "3S", "4D"]), wrap), null);
  }
});

test("straight flushes rank by suit, then by the cards; royals are higher", () => {
  const lowSpade = ["3S", "4S", "5S", "6S", "7S"];
  const highHeart = ["9H", "TH", "JH", "QH", "KH"];
  const highDiamond = ["TD", "JD", "QD", "KD", "AD"];
  assert.equal(combo(lowSpade).kind, "straight_flush");
  assert.equal(combo(highHeart).kind, "straight_flush");
  assert.equal(combo(highDiamond).kind, "royal_flush");
  assert.ok(beats(combo(lowSpade), combo(highHeart)));
  assert.equal(beats(combo(highHeart), combo(lowSpade)), false);
  assert.ok(beats(combo(highDiamond), combo(lowSpade)));
  const wheelFlush = ["AD", "2D", "3D", "4D", "5D"];
  assert.equal(combo(wheelFlush).kind, "flush");
  assert.equal(combo(wheelFlush).bonusEach, 0);
  const lowWrapFlush = ["2D", "3D", "4D", "5D", "6D"];
  assert.equal(combo(lowWrapFlush).kind, "flush");
  assert.equal(combo(lowWrapFlush).bonusEach, 0);
  assert.equal(identify(parseCards(wheelFlush), true)?.kind, "flush");
  assert.equal(identify(parseCards(lowWrapFlush), true)?.kind, "flush");
  const diamondRoyal = ["TD", "JD", "QD", "KD", "AD"];
  const spadeRoyal = ["TS", "JS", "QS", "KS", "AS"];
  assert.ok(beats(combo(spadeRoyal), combo(diamondRoyal)));
  const twoHighHearts = ["JH", "QH", "KH", "AH", "2H"];
  const twoHighSpades = ["JS", "QS", "KS", "AS", "2S"];
  assert.equal(combo(twoHighHearts).kind, "straight_flush");
  assert.equal(combo(twoHighSpades).kind, "straight_flush");
  assert.ok(beats(combo(twoHighSpades), combo(twoHighHearts)));
  assert.ok(beats(combo(diamondRoyal), combo(twoHighHearts)));
  assert.ok(beats(combo(diamondRoyal), combo(twoHighSpades)));
  const highSpade = ["9S", "TS", "JS", "QS", "KS"];
  const lowSpadeAgain = ["3S", "4S", "5S", "6S", "7S"];
  assert.ok(beats(combo(highSpade), combo(lowSpadeAgain)));
  assert.ok(beats(combo(highSpade), combo(["9H", "TH", "JH", "QH", "KH"])));
});

test("full houses use the triple, fours use the four, kickers do not matter", () => {
  assert.ok(beats(combo(["2D", "2C", "2H", "3S", "3D"]), combo(["AD", "AC", "AH", "KS", "KD"])));
  assert.ok(beats(combo(["AD", "AC", "AH", "AS", "3D"]), combo(["KD", "KC", "KH", "KS", "2S"])));
  assert.equal(
    beats(combo(["5D", "5C", "5H", "5S", "3D"]), combo(["5D", "5C", "5H", "5S", "2S"])),
    false,
  );
});

test("invalid shapes are rejected", () => {
  assert.equal(identify(parseCards([])), null);
  assert.equal(identify(parseCards(["3D", "3C", "4H", "4S"])), null);
  assert.equal(identify(parseCards(["3D", "4D", "5D", "6D"])), null);
  assert.equal(identify(parseCards(["3D", "3C", "3H", "4S", "5D"])), null);
  assert.equal(identify(parseCards(["3D", "3D"])), null);
  assert.equal(identify(parseCards(["3D", "4C", "5H", "6S", "8D"])), null);
});

test("the opening lead must include the 3 of diamonds", () => {
  const state = makeState({
    hands: [parseCards(["3D", "4C"]), parseCards(["5H", "8C"]), parseCards(["6S"]), parseCards(["7D"])],
    turn: 0,
    firstLead: true,
  });
  const missing = applyPlay(state, 0, ["4C"], settings);
  assert.equal(missing.ok, false);
  if (!missing.ok) assert.match(missing.message, /3/);
  const played = applyPlay(state, 0, ["3D", "4C"], settings);
  assert.equal(played.ok, false);
  const ok = applyPlay(state, 0, ["3D"], settings);
  assert.equal(ok.ok, true);
  if (ok.ok) assert.equal(ok.state.firstLead, false);
});

test("you cannot go out on only 2s, but a five-card hand with a 2 can", () => {
  const others = [parseCards(["3D"]), parseCards(["4C"]), parseCards(["5H"])];
  for (const ids of [["2S"], ["2S", "2H"], ["2S", "2H", "2C"]]) {
    const state = makeState({ hands: [parseCards(ids), ...others], turn: 0 });
    const blocked = applyPlay(state, 0, ids, settings);
    assert.equal(blocked.ok, false);
    if (!blocked.ok) assert.match(blocked.message, /2s/);
    assert.equal(state.hands[0].length, ids.length);
  }

  const four = makeState({
    hands: [parseCards(["2D", "2C", "2H", "2S"]), ...others],
    turn: 0,
  });
  const notACombo = applyPlay(four, 0, ["2D", "2C", "2H", "2S"], settings);
  assert.equal(notACombo.ok, false);
  const keptOne = applyPlay(four, 0, ["2D", "2C", "2H"], settings);
  assert.equal(keptOne.ok, true);
  if (keptOne.ok) assert.equal(keptOne.state.hands[0].map(formatCard).join(","), "2S");

  const withTwo = makeState({
    hands: [parseCards(["2S", "9C"]), ...others],
    turn: 0,
  });
  const leadTwo = applyPlay(withTwo, 0, ["2S"], settings);
  assert.equal(leadTwo.ok, true);
  if (leadTwo.ok) assert.equal(leadTwo.state.hands[0].map(formatCard).join(","), "9C");

  const five = makeState({
    hands: [parseCards(["JD", "QD", "KD", "AD", "2D"]), ...others],
    turn: 0,
  });
  const won = applyPlay(five, 0, ["JD", "QD", "KD", "AD", "2D"], settings);
  assert.equal(won.ok, true);
  if (won.ok) {
    assert.equal(won.state.winner, 0);
    assert.equal(won.result?.cardsLeft[0], 0);
  }

  const fours = makeState({
    hands: [parseCards(["2D", "2C", "2H", "2S", "9D"]), ...others],
    turn: 0,
  });
  const fourWon = applyPlay(fours, 0, ["2D", "2C", "2H", "2S", "9D"], settings);
  assert.equal(fourWon.ok, true);
  if (fourWon.ok) assert.equal(fourWon.state.winner, 0);

  const house = makeState({
    hands: [parseCards(["2D", "2C", "2H", "5S", "5D"]), ...others],
    turn: 0,
  });
  const houseWon = applyPlay(house, 0, ["2D", "2C", "2H", "5S", "5D"], settings);
  assert.equal(houseWon.ok, true);
  if (houseWon.ok) {
    assert.equal(houseWon.state.winner, 0);
    assert.equal(houseWon.state.trick?.kind, "full_house");
  }
});

test("going out on only 2s is refused in every shape, and a five-card hand with a 2 can still finish", () => {
  const others = [parseCards(["3D", "4D"]), parseCards(["5C", "6C"]), parseCards(["7H", "8H"])];
  const seat = (ids: string[], extra: Record<string, unknown> = {}) =>
    makeState({ hands: [parseCards(ids), ...others], turn: 0, ...extra });

  for (const ids of [["2D"], ["2S"], ["2D", "2C"], ["2S", "2H"], ["2D", "2C", "2H"], ["2S", "2H", "2C"]]) {
    const state = seat(ids);
    const blocked = applyPlay(state, 0, ids, settings);
    assert.equal(blocked.ok, false, ids.join(" "));
    if (!blocked.ok) assert.equal(blocked.message, "You can't go out if you only have 2s");
    assert.equal(playIssue(state, 0, parseCards(ids), settings), "You can't go out if you only have 2s");
  }

  const overSingle = seat(["2H"], { trick: combo(["KD"]), trickSeat: 3, trickCards: ["KD"] });
  const overPair = seat(["2S", "2D"], { trick: combo(["AH", "AC"]), trickSeat: 3, trickCards: ["AH", "AC"] });
  const overTriple = seat(["2S", "2H", "2C"], {
    trick: combo(["AD", "AC", "AH"]),
    trickSeat: 3,
    trickCards: ["AD", "AC", "AH"],
  });
  for (const state of [overSingle, overPair, overTriple]) {
    const cards = state.hands[0].map(formatCard);
    const blocked = applyPlay(state, 0, cards, settings);
    assert.equal(blocked.ok, false, cards.join(" "));
    if (!blocked.ok) assert.equal(blocked.message, "You can't go out if you only have 2s");
    assert.equal(state.status, "playing");
  }

  const onlyTwos = [
    ["2S"],
    ["2S", "2H"],
    ["2S", "2H", "2C"],
    ["2D", "2C", "2H", "2S"],
  ];
  for (const ids of onlyTwos) {
    let state = seat(ids);
    const seen = new Set<string>();
    const pending = [state];
    while (pending.length > 0) {
      state = pending.pop()!;
      const key = `${state.hands[0].map(formatCard).sort().join(".")}:${(state.trickCards ?? []).join(".")}`;
      if (seen.has(key)) continue;
      seen.add(key);
      assert.notEqual(state.hands[0].length, 0);
      if (state.turn !== 0 || state.status !== "playing") continue;
      const hand = state.hands[0].map(formatCard);
      for (let mask = 1; mask < 1 << hand.length; mask++) {
        const play: string[] = [];
        for (let index = 0; index < hand.length; index++) if (mask & (1 << index)) play.push(hand[index]);
        if (![1, 2, 3, 5].includes(play.length)) continue;
        const step = applyPlay(state, 0, play, settings);
        if (!step.ok) continue;
        assert.notEqual(step.state.hands[0].length, 0, `${ids.join(" ")} via ${play.join(" ")}`);
        assert.ok(step.state.hands[0].every((card) => card.r === 15));
        pending.push({
          ...step.state,
          turn: 0,
          trick: null,
          trickSeat: null,
          trickCards: [],
          consecutivePasses: 0,
          status: "playing",
          winner: null,
        });
      }
    }
  }

  const four = seat(["2D", "2C", "2H", "2S"]);
  assert.equal(applyPlay(four, 0, ["2D", "2C", "2H", "2S"], settings).ok, false);
  const shed = applyPlay(four, 0, ["2D", "2C", "2H"], settings);
  assert.equal(shed.ok, true);
  if (shed.ok) {
    const again = { ...shed.state, turn: 0, trick: null, trickSeat: null, trickCards: [], consecutivePasses: 0 };
    assert.equal(applyPlay(again, 0, ["2S"], settings).ok, false);
    assert.equal(applyPass(again, 0, settings).ok, true);
  }

  const three = seat(["2S", "2H", "2C"]);
  assert.match(passIssue(three, 0, settings) ?? "", /must lead/);
  const oneOfThree = applyPlay(three, 0, ["2C"], settings);
  assert.equal(oneOfThree.ok, true);
  if (oneOfThree.ok) {
    const back = { ...oneOfThree.state, turn: 0, trick: null, trickSeat: null, trickCards: [], consecutivePasses: 0 };
    assert.equal(applyPlay(back, 0, ["2S", "2H"], settings).ok, false);
  }

  assert.equal(automaticLastCard(seat(["2S"]), 0, settings), null);
  assert.equal(automaticLastCard(overSingle, 0, settings), null);
  const stuck = seat(["2S"], { trick: combo(["9D"]), trickSeat: 3, trickCards: ["9D"] });
  assert.equal(applyPass(stuck, 0, settings).ok, true);

  const finishes: Array<[string[], string]> = [
    [["JH", "QD", "KC", "AS", "2D"], "straight"],
    [["2H", "4H", "6H", "8H", "TH"], "flush"],
    [["AH", "2H", "3H", "4H", "5H"], "flush"],
    [["2D", "3D", "4D", "5D", "6D"], "flush"],
    [["2D", "2C", "2H", "5S", "5D"], "full_house"],
    [["9D", "9C", "9H", "2S", "2D"], "full_house"],
    [["2D", "2C", "2H", "2S", "9D"], "four"],
    [["9D", "9C", "9H", "9S", "2C"], "four"],
    [["JD", "QD", "KD", "AD", "2D"], "straight_flush"],
    [["JS", "QS", "KS", "AS", "2S"], "straight_flush"],
  ];
  for (const [ids, kind] of finishes) {
    const won = applyPlay(seat(ids), 0, ids, settings);
    assert.equal(won.ok, true, ids.join(" "));
    if (!won.ok) continue;
    assert.equal(won.state.winner, 0);
    assert.equal(won.state.hands[0].length, 0);
    assert.equal(won.state.trick?.kind, kind);
    assert.equal(won.result?.cardsLeft[0], 0);
  }

  const followed = seat(["JS", "QS", "KS", "AS", "2S"], {
    trick: combo(["3D", "4C", "5H", "6S", "7D"]),
    trickSeat: 3,
    trickCards: ["3D", "4C", "5H", "6S", "7D"],
  });
  const beatFive = applyPlay(followed, 0, ["JS", "QS", "KS", "AS", "2S"], settings);
  assert.equal(beatFive.ok, true);
  if (beatFive.ok) assert.equal(beatFive.state.winner, 0);
});

test("three passes hand the lead back, and pass-lock lasts until that happens", () => {
  const state = makeState({
    hands: [parseCards(["9C"]), parseCards(["4C"]), parseCards(["5H"]), parseCards(["6S"])],
    turn: 1,
    trick: combo(["KS"]),
    trickSeat: 0,
    trickCards: ["KS"],
  });
  const first = applyPass(state, 1, settings);
  const second = first.ok ? applyPass(first.state, 2, settings) : first;
  const third = second.ok ? applyPass(second.state, 3, settings) : second;
  assert.equal(third.ok, true);
  if (!third.ok) return;
  assert.equal(third.state.trick, null);
  assert.equal(third.state.turn, 0);
  assert.deepEqual(third.state.locked, []);

  const lockedSettings = { ...settings, passLocks: true };
  const held = makeState({
    hands: [
      parseCards(["9C"]),
      parseCards(["AS", "3D"]),
      parseCards(["2S", "4C"]),
      parseCards(["5H"]),
    ],
    turn: 1,
    trick: combo(["KS"]),
    trickSeat: 0,
    trickCards: ["KS"],
  });
  const pass = applyPass(held, 1, lockedSettings);
  assert.equal(pass.ok, true);
  if (!pass.ok) return;
  const higher = applyPlay(pass.state, 2, ["2S"], lockedSettings);
  assert.equal(higher.ok, true);
  if (!higher.ok) return;
  const pass3 = applyPass(higher.state, 3, lockedSettings);
  assert.equal(pass3.ok, true);
  if (!pass3.ok) return;
  const pass0 = applyPass(pass3.state, 0, lockedSettings);
  assert.equal(pass0.ok, true);
  if (!pass0.ok) return;
  assert.equal(pass0.state.turn, 1);
  assert.deepEqual(pass0.state.locked, [1, 3, 0]);
  const retry = applyPlay(pass0.state, 1, ["AS"], lockedSettings);
  assert.equal(retry.ok, false);
  if (!retry.ok) assert.match(retry.message, /passed/i);
  const free = applyPass(pass0.state, 1, lockedSettings);
  assert.equal(free.ok, true);
  if (!free.ok) return;
  assert.equal(free.state.trick, null);
  assert.equal(free.state.turn, 2);
  const after = applyPlay(free.state, 2, ["4C"], lockedSettings);
  assert.equal(after.ok, true);
});

test("three passes clear the trick and the last player to play leads", () => {
  let state = makeState({
    hands: [
      parseCards(["3D", "9C", "4D"]),
      parseCards(["4C", "8D"]),
      parseCards(["5H", "7C"]),
      parseCards(["6S", "7S"]),
    ],
    turn: 0,
    firstLead: true,
  });
  const lead = applyPlay(state, 0, ["3D"], settings);
  assert.equal(lead.ok, true);
  if (!lead.ok) return;
  state = lead.state;
  for (const seat of [1, 2, 3]) {
    const step = applyPass(state, seat, settings);
    assert.equal(step.ok, true);
    if (!step.ok) return;
    state = step.state;
  }
  assert.equal(state.trick, null);
  assert.equal(state.turn, 0);
  const free = applyPlay(state, 0, ["9C"], settings);
  assert.equal(free.ok, true);
});

test("bonuses hit the other players immediately and do not end the round mid-hand", () => {
  const state = makeState({
    hands: [
      parseCards(["9C"]),
      parseCards(["4C"]),
      parseCards(["5H"]),
      parseCards(["3D", "4D", "5D", "6D", "7D", "TC", "JC", "QC", "KC"]),
    ],
    turn: 3,
    running: [20, 30, 38, 45],
  });
  const played = applyPlay(state, 3, ["3D", "4D", "5D", "6D", "7D"], settings);
  assert.equal(played.ok, true);
  if (!played.ok) return;
  assert.deepEqual(played.state.running, [28, 38, 46, 45]);
  assert.equal(played.state.status, "playing");
  assert.equal(played.result, null);
  assert.equal(played.state.bonuses[0].combo, "straight flush");
  assert.equal(played.state.bonuses[0].pointsEach, 8);
});

test("the worked example: straight flush, then the hand scores and the round ends", () => {
  const bonuses = [
    { seat: 3, kind: "straight_flush" as const, combo: "straight flush", pointsEach: 8 },
  ];
  const score = scoreCounts([0, 11, 9, 4], [28, 38, 46, 45], bonuses);
  assert.deepEqual(score.cardPoints, [0, 22, 9, 4]);
  assert.deepEqual(score.bonusReceived, [8, 8, 8, 0]);
  assert.deepEqual(score.handPoints, [8, 30, 17, 4]);
  assert.deepEqual(score.runningTotals, [28, 60, 55, 49]);
  assert.equal(score.roundOver, true);

  const body = webhookPayload({
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
    bonuses,
  });
  assert.equal(body.tableCode, "ABC123");
  assert.equal(body.season, 24);
  assert.deepEqual(body.bonuses, [{ player: "Damien", combo: "straight flush", pointsEach: 8 }]);
  assert.deepEqual(body.runningTotals, [28, 60, 55, 49]);
  assert.equal(body.roundOver, true);
  assert.equal(body.roundWinner, "Justin");
  assert.equal(body.hasBots, false);
  assert.deepEqual(body.bots, []);
  assert.equal(roundWinnerName(["Justin", "Mary"], [12, 12], false), null);
  assert.equal(roundWinnerName(["Justin", "Mary"], [12, 12], true), "Justin, Mary");
});

test("a finishing bonus is included before the 50-point check", () => {
  const state = makeState({
    hands: [
      parseCards(["9C", "TC", "JC"]),
      parseCards(["4C"]),
      parseCards(["5H"]),
      parseCards(["TD", "JD", "QD", "KD", "AD"]),
    ],
    turn: 3,
    running: [40, 10, 10, 10],
  });
  const won = applyPlay(state, 3, ["TD", "JD", "QD", "KD", "AD"], settings);
  assert.equal(won.ok, true);
  if (!won.ok || !won.result) return;
  assert.equal(won.state.winner, 3);
  assert.deepEqual(won.state.running, [50, 20, 20, 10]);
  assert.deepEqual(won.result.cardsLeft, [3, 1, 1, 0]);
  assert.deepEqual(won.result.handPoints, [13, 11, 11, 0]);
  assert.deepEqual(won.result.runningTotals, [53, 21, 21, 10]);
  assert.equal(won.result.roundOver, true);
});

test("49 does not end the round, 50 does, and a tie shares the win", () => {
  const under = scoreCounts([1, 1, 1, 1], [10, 20, 30, 48], []);
  assert.deepEqual(under.runningTotals, [11, 21, 31, 49]);
  assert.equal(under.roundOver, false);
  const exact = scoreCounts([0, 0, 0, 1], [50, 10, 10, 10], []);
  assert.equal(exact.roundOver, true);
  assert.deepEqual(roundWinners([12, 12, 40, 51]), [0, 1]);
  assert.deepEqual(roundWinners([5, 9, 4, 4]), [2, 3]);
});

test("thirteen cards left score 36 for a player who never played", () => {
  const score = scoreCounts([0, 13, 9, 10], [0, 0, 0, 0], []);
  assert.deepEqual(score.cardPoints, [0, 36, 9, 20]);
  assert.deepEqual(score.handPoints, [0, 36, 9, 20]);
});

test("a player stuck with a single 2 passes the lead, and four skips close the hand", () => {
  let state = makeState({
    hands: [parseCards(["2S"]), parseCards(["3D"]), parseCards(["4C"]), parseCards(["5H"])],
    turn: 0,
  });
  const skip = applyPass(state, 0, settings);
  assert.equal(skip.ok, true);
  if (!skip.ok) return;
  assert.equal(skip.state.turn, 1);
  assert.equal(skip.state.status, "playing");
  const won = applyPlay(skip.state, 1, ["3D"], settings);
  assert.equal(won.ok, true);

  state = makeState({
    hands: [parseCards(["2D"]), parseCards(["2C"]), parseCards(["2H"]), parseCards(["2S"])],
    turn: 0,
  });
  for (let i = 0; i < 3; i++) {
    const step = applyPass(state, state.turn, settings);
    assert.equal(step.ok, true);
    if (!step.ok) return;
    state = step.state;
    assert.equal(state.status, "playing");
  }
  const closed = applyPass(state, state.turn, settings);
  assert.equal(closed.ok, true);
  if (!closed.ok || !closed.result) return;
  assert.equal(closed.state.closedReason, "stuck");
  assert.deepEqual(closed.result.cardsLeft, [1, 1, 1, 1]);
  assert.equal(closed.result.winner, null);
});

test("the disconnected-player timer passes, or leads the lowest single", () => {
  const following = makeState({
    hands: [parseCards(["AS"]), parseCards(["3D"]), parseCards(["4C"]), parseCards(["5H"])],
    turn: 1,
    trick: combo(["KS"]),
    trickSeat: 0,
    trickCards: ["KS"],
  });
  const passed = applyTimeout(following, { ...settings, turnTimerSeconds: 30 });
  assert.equal(passed.ok, true);
  if (passed.ok) assert.equal(passed.state.turn, 2);

  const leading = makeState({
    hands: [parseCards(["9C", "AS", "3D"]), parseCards(["4C", "6H"]), parseCards(["5H"]), parseCards(["6S"])],
    turn: 0,
  });
  assert.deepEqual(lowestLegalPlay(leading, 0, settings), ["3D"]);
  const led = applyTimeout(leading, settings);
  assert.equal(led.ok, true);
  if (led.ok) assert.deepEqual(led.state.trickCards, ["3D"]);
});

test("dealing gives 13 cards each and the 3 of diamonds leads the first hand", () => {
  const deck = fullDeck();
  const state = startHand(deck, [0, 0, 0, 0], true, null);
  assert.deepEqual(state.hands.map((hand) => hand.length), [13, 13, 13, 13]);
  const leader = state.turn;
  assert.equal(state.hands[leader].some((card) => formatCard(card) === "3D"), true);
  const replayed = replay(deck, [0, 0, 0, 0], true, null, [], settings);
  assert.equal(replayed.ok, true);
  if (replayed.ok) assert.equal(replayed.state.turn, leader);
});

test("later hands are led by the previous winner and 3 of diamonds is not required", () => {
  const deck = fullDeck();
  const state = startHand(deck, [1, 2, 3, 4], false, 2);
  assert.equal(state.turn, 2);
  assert.equal(state.firstLead, false);
  const card = formatCard(state.hands[2][0]);
  const step = applyPlay(state, 2, [card], settings);
  assert.equal(step.ok, true);
});

test("shuffle is unbiased and the commitment matches the revealed deck", async () => {
  let calls = 0;
  const values = [0xffffffff, 0];
  const index = indexBelow(3, () => {
    calls += 1;
    return values[calls - 1];
  });
  assert.equal(index, 0);
  assert.equal(calls, 2);

  const items = ["A", "B", "C", "D"];
  const draws = [5, 0, 1];
  let cursor = 0;
  shuffleInPlace(items, () => draws[cursor++]);
  assert.deepEqual(items, ["C", "D", "A", "B"]);

  const deck = shuffleDeck();
  assert.equal(deck.length, 52);
  assert.equal(new Set(deck.map(formatCard)).size, 52);
  const committed = await commitDeck(deck);
  const again = await commitDeck(deck);
  assert.equal(committed.commitment, again.commitment);
  assert.equal(committed.commitment.length, 64);
  const sorted = sortCards(parseCards(committed.canonical.split(",")), "rank");
  assert.equal(sorted.length, 52);
  assert.equal(formatCard(sorted[0]), "3D");
  assert.equal(formatCard(sorted[51]), "2S");
});

test("a single must be the highest card when the next player has one card", () => {
  const ahead = makeState({
    hands: [
      parseCards(["3D", "9C", "KS", "AH", "4D", "4C"]),
      parseCards(["2S"]),
      parseCards(["5H", "6H"]),
      parseCards(["7D", "8D"]),
    ],
    turn: 0,
  });
  const low = applyPlay(ahead, 0, ["9C"], settings);
  assert.equal(low.ok, false);
  if (!low.ok) assert.equal(low.message, HIGHEST_SINGLE_MESSAGE);
  const lowerSuit = applyPlay(ahead, 0, ["KS"], settings);
  assert.equal(lowerSuit.ok, false);
  const highest = applyPlay(ahead, 0, ["AH"], settings);
  assert.equal(highest.ok, true);
  if (highest.ok) assert.deepEqual(highest.state.trickCards, ["AH"]);

  const pair = applyPlay(ahead, 0, ["4D", "4C"], settings);
  assert.equal(pair.ok, true);
  const straight = makeState({
    hands: [
      parseCards(["5D", "6C", "7H", "8S", "9D", "3C"]),
      parseCards(["QS"]),
      parseCards(["4H", "TC"]),
      parseCards(["JD"]),
    ],
    turn: 0,
  });
  const five = applyPlay(straight, 0, ["5D", "6C", "7H", "8S", "9D"], settings);
  assert.equal(five.ok, true);
  if (five.ok) assert.equal(five.state.trick?.kind, "straight");

  const lead = makeState({
    hands: [
      parseCards(["7C", "AS", "2D"]),
      parseCards(["4S"]),
      parseCards(["5C", "6C"]),
      parseCards(["8H", "9H"]),
    ],
    turn: 0,
  });
  const lowLead = applyPlay(lead, 0, ["7C"], settings);
  assert.equal(lowLead.ok, false);
  if (!lowLead.ok) assert.match(lowLead.message, /highest single/);
  const highLead = applyPlay(lead, 0, ["2D"], settings);
  assert.equal(highLead.ok, true);

  const quiet = makeState({
    hands: [
      parseCards(["3D", "9C", "KS"]),
      parseCards(["4C", "5C"]),
      parseCards(["2H"]),
      parseCards(["6D", "7D"]),
    ],
    turn: 0,
  });
  const normal = applyPlay(quiet, 0, ["3D"], settings);
  assert.equal(normal.ok, true);

  const elsewhere = makeState({
    hands: [
      parseCards(["3D", "9C"]),
      parseCards(["4C", "5C", "6C"]),
      parseCards(["2S"]),
      parseCards(["7H", "8H"]),
    ],
    turn: 0,
  });
  const otherSeat = applyPlay(elsewhere, 0, ["3D"], settings);
  assert.equal(otherSeat.ok, true);

  const following = makeState({
    hands: [
      parseCards(["6C", "AS", "4D", "4H"]),
      parseCards(["3S"]),
      parseCards(["9D", "TC"]),
      parseCards(["JD"]),
    ],
    turn: 0,
    trick: identify(parseCards(["5D"])) ,
    trickSeat: 3,
    trickCards: ["5D"],
  });
  const beatsButLow = applyPlay(following, 0, ["6C"], settings);
  assert.equal(beatsButLow.ok, false);
  if (!beatsButLow.ok) assert.equal(beatsButLow.message, HIGHEST_SINGLE_MESSAGE);
  const answering = applyPlay(following, 0, ["AS"], settings);
  assert.equal(answering.ok, true);
  const stillPair = applyPlay(following, 0, ["4D", "4H"], settings);
  assert.equal(stillPair.ok, false);

  const passed = applyPass(following, 0, settings);
  assert.equal(passed.ok, false);
  if (!passed.ok) assert.match(passed.message, /must play your highest card/);
});

function singleTrick(card: string) {
  const trick = identify(parseCards([card]));
  if (!trick) throw new Error(card);
  return trick;
}

test("following a non-2 single forces the highest card when the next player has one", () => {
  const state = makeState({
    hands: [
      parseCards(["3D", "KS", "2H"]),
      parseCards(["QS"]),
      parseCards(["4C", "5C"]),
      parseCards(["6D", "7D"]),
    ],
    turn: 0,
    trick: singleTrick("8D"),
    trickSeat: 3,
    trickCards: ["8D"],
  });
  const low = applyPlay(state, 0, ["KS"], settings);
  assert.equal(low.ok, false);
  const forced = applyPlay(state, 0, ["2H"], settings);
  assert.equal(forced.ok, true);
  const passed = applyPass(state, 0, settings);
  assert.equal(passed.ok, false);
  if (!passed.ok) assert.equal(passed.message, MUST_PLAY_HIGHEST_MESSAGE);

  const deuceOnly = makeState({
    hands: [
      parseCards(["2S"]),
      parseCards(["QS"]),
      parseCards(["4C", "5C"]),
      parseCards(["6D"]),
    ],
    turn: 0,
    trick: singleTrick("8D"),
    trickSeat: 3,
    trickCards: ["8D"],
  });
  const cannotFinish = applyPass(deuceOnly, 0, settings);
  assert.equal(cannotFinish.ok, true);

  const pairTrick = makeState({
    hands: [
      parseCards(["9D", "9C", "2S"]),
      parseCards(["QS"]),
      parseCards(["4C", "5C"]),
      parseCards(["6D", "7D"]),
    ],
    turn: 0,
    trick: identify(parseCards(["4H", "4S"])),
    trickSeat: 3,
    trickCards: ["4H", "4S"],
  });
  assert.equal(applyPass(pairTrick, 0, settings).ok, true);
  assert.equal(applyPlay(pairTrick, 0, ["9D", "9C"], settings).ok, true);
});

test("a 2 on the table may be passed, and a single played must still be the highest", () => {
  const state = makeState({
    hands: [
      parseCards(["9C", "2C", "2S"]),
      parseCards(["QS"]),
      parseCards(["4C", "5C"]),
      parseCards(["6D", "7D"]),
    ],
    turn: 0,
    trick: singleTrick("2D"),
    trickSeat: 3,
    trickCards: ["2D"],
  });
  assert.equal(applyPass(state, 0, settings).ok, true);
  const lowerTwo = applyPlay(state, 0, ["2C"], settings);
  assert.equal(lowerTwo.ok, false);
  if (!lowerTwo.ok) assert.equal(lowerTwo.message, HIGHEST_SINGLE_MESSAGE);
  assert.equal(applyPlay(state, 0, ["2S"], settings).ok, true);
});

test("passing is allowed when the highest card cannot beat the single", () => {
  const state = makeState({
    hands: [
      parseCards(["3D", "KH", "AH"]),
      parseCards(["QS"]),
      parseCards(["4C", "5C"]),
      parseCards(["6D", "7D"]),
    ],
    turn: 0,
    trick: singleTrick("AS"),
    trickSeat: 3,
    trickCards: ["AS"],
  });
  assert.equal(applyPlay(state, 0, ["AH"], settings).ok, false);
  assert.equal(applyPass(state, 0, settings).ok, true);
});

test("a normal single is not forced when the next player has more than one card", () => {
  const state = makeState({
    hands: [
      parseCards(["3D", "7C", "AS"]),
      parseCards(["QS", "4C"]),
      parseCards(["2H"]),
      parseCards(["6D", "7D"]),
    ],
    turn: 0,
    trick: singleTrick("5D"),
    trickSeat: 3,
    trickCards: ["5D"],
  });
  assert.equal(applyPlay(state, 0, ["7C"], settings).ok, true);
  assert.equal(applyPass(state, 0, settings).ok, true);
});

test("a lone legal card is played automatically, and an illegal one is not", () => {
  const others = [parseCards(["9C", "4C"]), parseCards(["6H", "7H"]), parseCards(["8D", "TD"])];
  const lead = makeState({ hands: [parseCards(["5D"]), ...others], turn: 0, firstLead: false });
  assert.equal(automaticLastCard(lead, 0, settings), "5D");
  assert.equal(lastCardMessage("Ada"), "Ada plays their last card");

  const two = makeState({ hands: [parseCards(["2H"]), ...others], turn: 0, firstLead: false });
  assert.equal(automaticLastCard(two, 0, settings), null);

  const low = makeState({
    hands: [parseCards(["3D"]), ...others],
    turn: 0,
    firstLead: false,
    trick: singleTrick("KD"),
    trickSeat: 1,
    trickCards: ["KD"],
  });
  assert.equal(automaticLastCard(low, 0, settings), null);

  const againstPair = makeState({
    hands: [parseCards(["KD"]), ...others],
    turn: 0,
    firstLead: false,
    trick: identify(parseCards(["4C", "4D"])),
    trickSeat: 1,
    trickCards: ["4C", "4D"],
  });
  assert.equal(automaticLastCard(againstPair, 0, settings), null);

  const beat = makeState({
    hands: [parseCards(["AS"]), ...others],
    turn: 0,
    firstLead: false,
    trick: singleTrick("5D"),
    trickSeat: 1,
    trickCards: ["5D"],
  });
  assert.equal(automaticLastCard(beat, 0, settings), "AS");
  const won = applyPlay(beat, 0, ["AS"], settings);
  assert.equal(won.ok, true);
  if (won.ok) {
    assert.equal(won.state.status, "complete");
    assert.equal(won.state.winner, 0);
  }
});

