import assert from "node:assert/strict";
import test from "node:test";
import { chooseMove, type BotView, type Difficulty } from "../../supabase/functions/_shared/bots/choose.ts";
import { formatCard, fullDeck, parseCards, type Card } from "../../supabase/functions/_shared/rules/cards.ts";
import { identify } from "../../supabase/functions/_shared/rules/combo.ts";
import { applyPass, applyPlay, DEFAULT_SETTINGS, resultOf, startHand, type HandState } from "../../supabase/functions/_shared/rules/game.ts";
import { shuffleInPlace } from "../../supabase/functions/_shared/rules/shuffle.ts";

function mulberryUint32(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state |= 0;
    state = (state + 0x6d2b79f5) | 0;
    let value = Math.imul(state ^ (state >>> 15), 1 | state);
    value = (value + Math.imul(value ^ (value >>> 7), 61 | value)) ^ value;
    return (value ^ (value >>> 14)) >>> 0;
  };
}

function view(patch: Partial<BotView> & Pick<BotView, "hand" | "difficulty">): BotView {
  return {
    seat: 0,
    played: [],
    counts: [patch.hand.length, 13, 13, 13],
    trick: null,
    trickSeat: null,
    firstLead: false,
    running: [0, 0, 0, 0],
    settings: DEFAULT_SETTINGS,
    rng: () => 0,
    ...patch,
  };
}

test("a bot plays twos before a last card that is not a two", () => {
  for (const difficulty of ["easy", "normal", "hard"] as const) {
    const single = chooseMove(view({ hand: parseCards(["2S", "9C"]), difficulty }));
    assert.equal(single.kind, "play");
    if (single.kind === "play") assert.deepEqual(single.cards, ["2S"]);

    const pair = chooseMove(view({ hand: parseCards(["2S", "2H", "9C"]), difficulty }));
    assert.equal(pair.kind, "play");
    if (pair.kind === "play") assert.deepEqual([...pair.cards].sort(), ["2H", "2S"]);
  }
});

test("normal and hard block a one-card opponent with the highest single", () => {
  const trick = identify(parseCards(["5D"]), false);
  assert.ok(trick);
  for (const difficulty of ["normal", "hard"] as const) {
    const move = chooseMove(view({
      hand: parseCards(["3D", "9C", "KS"]),
      difficulty,
      played: parseCards(["5D"]),
      counts: [3, 10, 1, 8],
      trick,
      trickSeat: 1,
    }));
    assert.equal(move.kind, "play");
    if (move.kind === "play") assert.deepEqual(move.cards, ["KS"]);
  }
});

test("hard keeps a higher sure stop when a lower card already beats every unseen card", () => {
  const hand = parseCards(["6C", "9C", "KS"]);
  const held = new Set(["6C", "9C", "KS"]);
  const played = fullDeck().filter((card) => {
    const id = formatCard(card);
    if (id === "5D") return true;
    if (held.has(id)) return false;
    if (card.r < 9) return false;
    if (card.r === 9 && card.s === "D") return false;
    return true;
  });
  const trick = identify(parseCards(["5D"]), false);
  assert.ok(trick);
  const shared = {
    hand,
    played,
    counts: [3, 10, 1, 8],
    trick,
    trickSeat: 1,
  };
  const hard = chooseMove(view({ ...shared, difficulty: "hard" }));
  const normal = chooseMove(view({ ...shared, difficulty: "normal" }));
  assert.equal(hard.kind, "play");
  assert.equal(normal.kind, "play");
  if (hard.kind === "play") assert.deepEqual(hard.cards, ["9C"]);
  if (normal.kind === "play") assert.deepEqual(normal.cards, ["KS"]);
});

test("bots play their highest single, not a lower one, when the next player has one card", () => {
  const trick = identify(parseCards(["5D"]), false);
  assert.ok(trick);
  for (const difficulty of ["easy", "normal", "hard"] as const) {
    const move = chooseMove(view({
      hand: parseCards(["6C", "9C", "KS"]),
      difficulty,
      played: parseCards(["5D"]),
      counts: [3, 1, 10, 8],
      trick,
      trickSeat: 3,
    }));
    assert.equal(move.kind, "play");
    if (move.kind === "play") assert.deepEqual(move.cards, ["KS"]);
  }

  const lead = chooseMove(view({
    hand: parseCards(["3D", "4C", "4H", "2C"]),
    difficulty: "easy",
    counts: [4, 1, 12, 11],
  }));
  assert.equal(lead.kind, "play");
  if (lead.kind === "play") assert.deepEqual(lead.cards, ["2C"]);
});

function playHand(seed: number, difficulties: readonly Difficulty[]): number[] {
  const deck = fullDeck();
  shuffleInPlace(deck, mulberryUint32(seed));
  let state: HandState = startHand(deck, [0, 0, 0, 0], true, null);
  const played: Card[] = [];
  const rng = mulberryUint32(seed ^ 0x9e3779b9);
  let guard = 0;
  while (state.status === "playing") {
    if (++guard > 400) throw new Error(`hand ${seed} did not finish`);
    const seat = state.turn;
    const move = chooseMove({
      seat,
      hand: state.hands[seat],
      played,
      counts: state.hands.map((cards) => cards.length),
      trick: state.trick,
      trickSeat: state.trickSeat,
      firstLead: state.firstLead,
      running: state.running,
      settings: DEFAULT_SETTINGS,
      difficulty: difficulties[seat],
      rng: () => rng() / 4294967296,
      locked: state.locked,
    });
    const step = move.kind === "play"
      ? applyPlay(state, seat, move.cards, DEFAULT_SETTINGS)
      : applyPass(state, seat, DEFAULT_SETTINGS);
    if (!step.ok) {
      const cards = move.kind === "play" ? move.cards.join(" ") : "";
      throw new Error(`seed ${seed} seat ${seat} ${difficulties[seat]} ${move.kind} ${cards}: ${step.message}`);
    }
    if (move.kind === "play") played.push(...parseCards(move.cards));
    state = step.state;
  }
  const result = resultOf(state);
  if (!result) throw new Error(`seed ${seed} has no score`);
  return result.runningTotals;
}

test("bots stay legal for 2000 shuffled hands", () => {
  const cycle: Difficulty[] = ["easy", "normal", "hard"];
  for (let seed = 1; seed <= 2000; seed++) {
    playHand(seed, [0, 1, 2, 3].map((seat) => cycle[(seed + seat) % 3]));
  }
});

test("normal beats easy on average over 1000 hands", () => {
  const totals = [0, 0, 0, 0];
  let normalHands = 0;
  let easyHands = 0;
  let ties = 0;
  for (let index = 0; index < 1000; index++) {
    const scores = playHand(50_000 + index, ["normal", "normal", "easy", "easy"]);
    for (let seat = 0; seat < 4; seat++) totals[seat] += scores[seat];
    const normal = scores[0] + scores[1];
    const easy = scores[2] + scores[3];
    if (normal < easy) normalHands += 1;
    else if (easy < normal) easyHands += 1;
    else ties += 1;
  }
  const normalMean = (totals[0] + totals[1]) / 2000;
  const easyMean = (totals[2] + totals[3]) / 2000;
  console.log(JSON.stringify({
    hands: 1000,
    seats: "0-1 normal, 2-3 easy",
    normalMean: Number(normalMean.toFixed(3)),
    easyMean: Number(easyMean.toFixed(3)),
    normalSeatMeans: [totals[0] / 1000, totals[1] / 1000].map((value) => Number(value.toFixed(3))),
    easySeatMeans: [totals[2] / 1000, totals[3] / 1000].map((value) => Number(value.toFixed(3))),
    handsNormalLower: normalHands,
    handsEasyLower: easyHands,
    ties,
  }));
  assert.ok(normalMean < easyMean, `normal ${normalMean} vs easy ${easyMean}`);
});
