import assert from "node:assert/strict";
import test from "node:test";
import { parseCards } from "../../supabase/functions/_shared/rules/cards.ts";
import { identify } from "../../supabase/functions/_shared/rules/combo.ts";
import {
  applyPass,
  applyPlay,
  applyTimeout,
  autoPassBlock,
  autoPassForHumans,
  DEFAULT_SETTINGS,
  makeState,
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

test("an auto-pass is refused when the player can beat a single or a pair", () => {
  assert.equal(autoPassBlock(following(["4D", "KD", "9H"], ["7S"]), 0, settings), "they can beat what is on the table");
  assert.equal(autoPassBlock(following(["8D", "8C", "3H"], ["5H", "5D"]), 0, settings), "they can beat what is on the table");
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

test("one human has no auto-pass, two humans keep it", () => {
  assert.equal(autoPassForHumans(1), false);
  assert.equal(autoPassForHumans(2), true);
  assert.equal(autoPassForHumans(4), true);
});
