import assert from "node:assert/strict";
import test from "node:test";
import { parseCards } from "../../supabase/functions/_shared/rules/cards.ts";
import { applyPass, applyPlay, makeState } from "../../supabase/functions/_shared/rules/game.ts";
import { isLoneTwoOfSpades, undoOutcome } from "../../supabase/functions/_shared/undo.ts";

const settings = {
  passLocks: false,
  straightsWrap: false,
  turnTimerSeconds: 0,
  season: 24,
  timezone: "Australia/Melbourne",
  firstRoundNumber: 1,
};

test("two approvals undo, two refusals or a timeout do not", () => {
  const opened = "2026-10-25T00:00:00.000Z";
  const start = Date.parse(opened);
  assert.equal(undoOutcome({ "1": true }, opened, start + 1000), "wait");
  assert.equal(undoOutcome({ "1": true, "2": true }, opened, start + 1000), "approved");
  assert.equal(undoOutcome({ "1": false, "2": false }, opened, start + 1000), "rejected");
  assert.equal(undoOutcome({ "1": true, "2": false, "3": false }, opened, start + 1000), "rejected");
  assert.equal(undoOutcome({ "1": true }, opened, start + 30_000), "rejected");
  assert.equal(undoOutcome({}, opened, start + 30_000), "rejected");
  assert.equal(undoOutcome({ "1": true, "2": true }, opened, start + 30_000), "approved");
});

test("a lone 2 of spades makes the other three pass and returns the lead", () => {
  assert.equal(isLoneTwoOfSpades(["2S"]), true);
  assert.equal(isLoneTwoOfSpades(["2H"]), false);
  assert.equal(isLoneTwoOfSpades(["2S", "2H"]), false);

  const state = makeState({
    hands: [
      parseCards(["2S", "3D"]),
      parseCards(["4C", "5C"]),
      parseCards(["6H", "7H"]),
      parseCards(["8D", "9D"]),
    ],
    turn: 0,
  });
  const played = applyPlay(state, 0, ["2S"], settings);
  assert.equal(played.ok, true);
  if (!played.ok) return;
  let step = played;
  for (let i = 0; i < 3; i++) {
    const next = applyPass(step.state, step.state.turn, settings);
    assert.equal(next.ok, true);
    if (!next.ok) return;
    step = next;
  }
  assert.equal(step.state.turn, 0);
  assert.equal(step.state.trick, null);
  assert.equal(step.state.hands[0].length, 1);
});
