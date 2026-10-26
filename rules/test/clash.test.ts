import assert from "node:assert/strict";
import test from "node:test";
import { parseCards } from "../../supabase/functions/_shared/rules/cards.ts";
import { identify } from "../../supabase/functions/_shared/rules/combo.ts";
import {
  applyPass,
  applyPlay,
  applyTimeout,
  autoPassBlock,
  DEFAULT_SETTINGS,
  legalSelections,
  makeState,
  playIssue,
  timeoutBlock,
} from "../../supabase/functions/_shared/rules/game.ts";

const settings = DEFAULT_SETTINGS;
const filler = parseCards(["3C", "4C", "5C", "6C", "7C", "8C", "9C", "TC", "JC", "QC", "KC"]);

function hands(turnCards: string[], other = filler) {
  const mine = parseCards(turnCards);
  return [mine, other, other, other.slice(0, 11)];
}

function following(turnCards: string[], table: string[]) {
  const cards = parseCards(table);
  const trick = identify(cards, false);
  if (!trick) throw new Error(table.join(" "));
  return makeState({
    hands: hands(turnCards),
    turn: 0,
    trick,
    trickCards: table,
    trickSeat: 3,
  });
}

test("an auto-pass is refused when the player can beat a single", () => {
  assert.equal(autoPassBlock(following(["4D", "KD", "9H"], ["7S"]), 0, settings), "they can beat what is on the table");
});

test("the 2 of spades is not auto-passed against a single 2 of hearts, and it can be played", () => {
  const state = following(["2S", "3D", "4D"], ["2H"]);
  assert.equal(autoPassBlock(state, 0, settings), "they can beat what is on the table");
  assert.equal(playIssue(state, 0, parseCards(["2S"]), settings), null);
  const played = applyPlay(state, 0, ["2S"], settings);
  assert.equal(played.ok, true);
  if (!played.ok) return;
  assert.deepEqual(played.state.trickCards, ["2S"]);
});

test("a pair, a triple, or a five-card hand is never auto-passed", () => {
  assert.equal(autoPassBlock(following(["3D", "4D"], ["8C", "8D"]), 0, settings), "only a single card is auto-passed");
  assert.equal(autoPassBlock(following(["3D"], ["8C", "8D", "8H"]), 0, settings), "only a single card is auto-passed");
  assert.equal(
    autoPassBlock(following(["3D", "4D", "5D", "6D", "9C"], ["3C", "4C", "5C", "6C", "7C"]), 0, settings),
    "only a single card is auto-passed",
  );
  assert.equal(legalSelections(following(["3D", "4D"], ["8C", "8D"]), 0, settings).length, 0);
  assert.equal(autoPassBlock(following(["3D", "4D"], ["AS"]), 0, settings), null);
});

test("an auto-pass stands only while it is still that player's turn and they have no play", () => {
  const stuck = following(["3D", "4D"], ["AS"]);
  assert.equal(autoPassBlock(stuck, 0, settings), null);
  const played = applyPlay(stuck, 0, ["3D"], settings);
  assert.equal(played.ok, false);
  const moved = applyPass(stuck, 0, settings);
  assert.equal(moved.ok, true);
  if (!moved.ok) return;
  assert.equal(autoPassBlock(moved.state, 0, settings), "it is no longer their turn");
  assert.equal(timeoutBlock(moved.state, 0), "it is no longer their turn");
  assert.equal(timeoutBlock(stuck, 0), null);
});

test("a timeout clash must not be applied to the player who just received the turn", () => {
  const before = following(["KD", "3C"], ["5D"]);
  const clockSeat = before.turn;
  const landed = applyPlay(before, 0, ["KD"], settings);
  assert.equal(landed.ok, true);
  if (!landed.ok) return;
  assert.equal(timeoutBlock(landed.state, clockSeat), "it is no longer their turn");
  const wrong = applyTimeout(landed.state, settings);
  assert.equal(wrong.ok, true);
  if (!wrong.ok) return;
  assert.notEqual(wrong.state.turn, landed.state.turn);
});
