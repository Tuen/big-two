import assert from "node:assert/strict";
import test from "node:test";
import { formatCard, fullDeck, parseCards } from "../../supabase/functions/_shared/rules/cards.ts";
import { identify } from "../../supabase/functions/_shared/rules/combo.ts";
import {
  applyPass,
  applyPlay,
  autoPassBlock,
  DEFAULT_SETTINGS,
  makeState,
  NO_PLAY_MESSAGE,
  serverAutomatic,
  shouldAutoPass,
  type Settings,
  type Step,
} from "../../supabase/functions/_shared/rules/game.ts";
import { recentActions, type RecentEvent } from "../../supabase/functions/_shared/recent.ts";

/** The stored rule variant that callers can change. Wrap is kept even though a straight still cannot pass the 2. */
const ruleSets = [false, true];

function rules(wrap: boolean, autoplay: boolean): Settings {
  return { ...DEFAULT_SETTINGS, straightsWrap: wrap, autoplay };
}

function facing(hand: string[], table: string[], earlier: string[] = [], wrap = false) {
  const used = new Set([...hand, ...table, ...earlier]);
  const rest = fullDeck().map(formatCard).filter((id) => !used.has(id));
  const take = (count: number) => {
    const ids = rest.splice(0, count);
    assert.equal(ids.length, count);
    return parseCards(ids);
  };
  const trick = identify(parseCards(table), wrap);
  assert.ok(trick, table.join(" "));
  return makeState({
    hands: [parseCards(hand), take(5), take(5), take(5)],
    turn: 0,
    trick,
    trickSeat: 3,
    trickCards: table,
    faceUp: [...earlier, ...table],
  });
}

function okState(step: Step) {
  assert.equal(step.ok, true);
  if (!step.ok) throw new Error(step.message);
  return step.state;
}

for (const wrap of ruleSets) {
  const off = rules(wrap, false);
  const on = rules(wrap, true);
  const label = wrap ? "straight wrap on" : "straight wrap off";

  test(`autoplay off leaves passes unchanged (${label})`, () => {
    const two = facing(["3D", "4D"], ["2S"], [], wrap);
    assert.equal(shouldAutoPass(two, 0, off), true);
    assert.equal(autoPassBlock(two, 0, off), null);
    assert.equal(serverAutomatic(two, off)?.kind, "pass");

    const short = facing(["3D"], ["8C", "8D"], [], wrap);
    const bestPair = facing(["3D", "4D", "5D", "6D", "7D"], ["2S", "2H"], [], wrap);
    const beaten = facing(["3D", "4D", "5D", "6D", "7D"], ["8C", "8D"], [], wrap);
    const heart = facing(["3D", "4D", "5D", "6D", "7D"], ["2H"], ["2S"], wrap);
    for (const state of [short, bestPair, beaten, heart]) {
      assert.equal(shouldAutoPass(state, 0, off), false);
      assert.equal(autoPassBlock(state, 0, off), "only the 2 of spades is auto-passed");
      assert.equal(serverAutomatic(state, off), null);
    }
    const lead = makeState({ hands: [parseCards(["2H"]), parseCards(["3D"]), parseCards(["4C"]), parseCards(["5H"])], turn: 0 });
    assert.equal(shouldAutoPass(lead, 0, on), false);
    assert.equal(autoPassBlock(lead, 0, on), "they are leading");
  });

  test(`(A) a short public count is passed only when autoplay is on (${label})`, () => {
    const pair = facing(["9S"], ["4C", "4D"], [], wrap);
    const pairWithDeuce = facing(["2S"], ["4C", "4D"], [], wrap);
    const enoughForPair = facing(["3D", "4D"], ["8C", "8D"], [], wrap);
    const triple = facing(["3D", "4D"], ["8C", "8D", "8H"], [], wrap);
    const enoughForTriple = facing(["3D", "4D", "5D"], ["8C", "8D", "8H"], [], wrap);
    const five = facing(["3D", "4D", "5D", "6D"], ["3C", "4C", "5C", "6C", "7C"], [], wrap);
    const enoughForFive = facing(["9D", "9C", "8D", "7D", "6D"], ["3C", "4C", "5C", "6C", "7C"], [], wrap);
    const oneAgainstSingle = facing(["3D"], ["5H"], [], wrap);

    for (const state of [pair, pairWithDeuce, triple, five]) {
      assert.equal(shouldAutoPass(state, 0, on), true);
      assert.equal(autoPassBlock(state, 0, on), null);
      assert.equal(serverAutomatic(state, on)?.kind, "pass");
      if (serverAutomatic(state, on)?.kind === "pass") {
        assert.equal(serverAutomatic(state, on)?.message, NO_PLAY_MESSAGE);
      }
    }
    assert.equal(shouldAutoPass(pair, 0, on), shouldAutoPass(pairWithDeuce, 0, on));
    for (const state of [enoughForPair, enoughForTriple, enoughForFive, oneAgainstSingle]) {
      assert.equal(shouldAutoPass(state, 0, on), false);
    }
  });

  test(`(B) the best play of its kind is passed under these rules (${label})`, () => {
    const pair = facing(["3D", "4D", "5D", "6D", "7D"], ["2S", "2C"], [], wrap);
    const lesserPair = facing(["3D", "4D", "5D", "6D", "7D"], ["2H", "2D"], [], wrap);
    const triple = facing(["3D", "4D", "5D", "6D", "7D"], ["2S", "2H", "2D"], [], wrap);
    const royal = facing(["3D", "4D", "5D", "6D", "7D"], ["TS", "JS", "QS", "KS", "AS"], [], wrap);
    const heartRoyal = facing(["3D", "4D", "5D", "6D", "7D"], ["TH", "JH", "QH", "KH", "AH"], [], wrap);
    const wheel = facing(["6D", "7D", "8D", "9D", "TD"], ["AS", "2S", "3S", "4S", "5S"], [], wrap);
    const topStraight = facing(["3D", "4D", "5D", "6D", "7D"], ["JS", "QS", "KS", "AS", "2S"], [], wrap);

    assert.equal(identify(parseCards(["AS", "2S", "3S", "4S", "5S"]), wrap)?.kind, "flush");
    assert.equal(shouldAutoPass(pair, 0, on), true);
    assert.equal(shouldAutoPass(lesserPair, 0, on), false);
    assert.equal(shouldAutoPass(triple, 0, on), true);
    assert.equal(shouldAutoPass(royal, 0, on), true);
    assert.equal(shouldAutoPass(heartRoyal, 0, on), false);
    assert.equal(shouldAutoPass(wheel, 0, on), false);
    assert.equal(shouldAutoPass(topStraight, 0, on), false);
  });

  test(`(C) a play is passed when the cards that beat it are already face-up (${label})`, () => {
    const heart = facing(["3D", "4D", "5D", "6D", "7D"], ["2H"], ["2S"], wrap);
    const heartStillOut = facing(["3D", "4D", "5D", "6D", "7D"], ["2H"], [], wrap);
    const lowPair = facing(["3D", "4D", "5D", "6D", "7D"], ["2C", "2D"], ["2S", "2H"], wrap);
    const lowPairLive = facing(["3D", "4D", "5D", "6D", "7D"], ["2C", "2D"], [], wrap);
    const lesserTriple = facing(["3D", "4D", "5D", "6D", "7D"], ["2D", "2C", "2H"], [], wrap);
    const heartRoyal = facing(
      ["3D", "4D", "5D", "6D", "7D"],
      ["TH", "JH", "QH", "KH", "AH"],
      ["TS", "JS", "QS", "KS", "AS"],
      wrap,
    );

    assert.equal(shouldAutoPass(heart, 0, on), true);
    assert.equal(shouldAutoPass(heartStillOut, 0, on), false);
    assert.equal(shouldAutoPass(lowPair, 0, on), true);
    assert.equal(shouldAutoPass(lowPairLive, 0, on), false);
    assert.equal(shouldAutoPass(lesserTriple, 0, on), true);
    assert.equal(shouldAutoPass(heartRoyal, 0, on), true);
    assert.equal(shouldAutoPass(heart, 0, off), false);
    assert.equal(shouldAutoPass(lowPair, 0, off), false);
  });

  test(`a skip uses the public count, not the hidden cards (${label})`, () => {
    const cannot = facing(["3D", "4D"], ["9C", "9D"], [], wrap);
    const can = facing(["2S", "2H"], ["9C", "9D"], [], wrap);
    assert.equal(shouldAutoPass(cannot, 0, on), false);
    assert.equal(shouldAutoPass(can, 0, on), false);

    const deuceOut = facing(["3D", "4D", "5D"], ["2H"], [], wrap);
    assert.equal(shouldAutoPass(deuceOut, 0, on), false);
  });

  test(`cards played on an earlier trick stay face-up (${label})`, () => {
    let state = makeState({
      hands: [
        parseCards(["2S", "2H", "3D", "4D", "5D"]),
        parseCards(["3C", "4C", "5C", "6C", "7C"]),
        parseCards(["8C", "8D", "8H", "9C", "9D"]),
        parseCards(["KC", "KD", "KH", "QC", "QD"]),
      ],
      turn: 0,
    });
    state = okState(applyPlay(state, 0, ["2S"], on));
    state = okState(applyPass(state, 1, on));
    state = okState(applyPass(state, 2, on));
    state = okState(applyPass(state, 3, on));
    assert.deepEqual(state.faceUp, ["2S"]);
    assert.equal(state.trick, null);
    state = okState(applyPlay(state, 0, ["2H"], on));
    assert.deepEqual(state.faceUp, ["2S", "2H"]);
    assert.equal(shouldAutoPass(state, state.turn, on), true);
    assert.equal(shouldAutoPass(state, state.turn, off), false);
    assert.equal(serverAutomatic(state, on)?.kind, "pass");
  });
}

test("an autoplay skip is labelled auto pass, and a lone 2 of spades is not", () => {
  const byId = new Map(fullDeck().map((card) => [formatCard(card), card]));
  const take = (ids: string[]) => ids.map((id) => {
    const card = byId.get(id);
    assert.ok(card, id);
    byId.delete(id);
    return card;
  });
  const seat0 = take(["TS", "JS", "QS", "KS", "AS", "3D", "4D", "5D", "6D", "7D", "8D", "9D", "TD"]);
  const seat1 = take(["3C", "4C", "5C", "6C", "7C", "8C", "9C", "TC", "JC", "QC", "KC", "AC", "2C"]);
  const seat2 = take(["3H", "4H", "5H", "6H", "7H", "8H", "9H", "TH", "JH", "QH", "KH", "AH", "2H"]);
  const seat3 = [...byId.values()];
  const deck = [...seat0, ...seat1, ...seat2, ...seat3];
  const events: RecentEvent[] = [
    { seq: 1, seat: 0, kind: "play", cards: ["TS", "JS", "QS", "KS", "AS"] },
    { seq: 2, seat: 1, kind: "pass", cards: [] },
  ];
  const on = recentActions(deck, [0, 0, 0, 0], false, 0, events, rules(false, true));
  assert.equal(on[1].label, NO_PLAY_MESSAGE);
  const off = recentActions(deck, [0, 0, 0, 0], false, 0, events, rules(false, false));
  assert.equal(off[1].label, "Pass");

  const two = new Map(fullDeck().map((card) => [formatCard(card), card]));
  const takeTwo = (ids: string[]) => ids.map((id) => {
    const card = two.get(id);
    assert.ok(card, id);
    two.delete(id);
    return card;
  });
  const lead = takeTwo(["2S", "3C", "4C", "5C", "6C", "7C", "8C", "9C", "TC", "JC", "QC", "KC", "AC"]);
  const follow = takeTwo(["3D", "4D", "5D", "6D", "7D", "8D", "9D", "TD", "JD", "QD", "KD", "AD", "2D"]);
  const twoDeck = [...lead, ...follow, ...two.values()];
  const twoRecent = recentActions(twoDeck, [0, 0, 0, 0], false, 0, [
    { seq: 1, seat: 0, kind: "play", cards: ["2S"] },
    { seq: 2, seat: 1, kind: "pass", cards: [] },
  ], rules(true, true));
  assert.equal(twoRecent[1].label, "Pass");
});
