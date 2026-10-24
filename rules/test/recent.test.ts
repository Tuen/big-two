import assert from "node:assert/strict";
import test from "node:test";
import { formatCard, fullDeck } from "../../supabase/functions/_shared/rules/cards.ts";
import {
  applyPass,
  applyPlay,
  applyTimeout,
  startHand,
  DEFAULT_SETTINGS,
  type HandState,
  type Step,
} from "../../supabase/functions/_shared/rules/game.ts";
import { recentActions, type RecentEvent } from "../../supabase/functions/_shared/recent.ts";

function ok(step: Step): HandState {
  assert.equal(step.ok, true);
  if (!step.ok) throw new Error(step.message);
  return step.state;
}

test("recent actions list plays and passes, including a timeout, and keep the last eight", () => {
  const deck = fullDeck();
  const running = [0, 0, 0, 0];
  let state = startHand(deck, running, true, null);
  const events: RecentEvent[] = [];
  let seq = 1;

  const play = (cards: string[]) => {
    const seat = state.turn;
    events.push({ seq: seq++, seat, kind: "play", cards });
    state = ok(applyPlay(state, seat, cards, DEFAULT_SETTINGS));
  };
  const pass = () => {
    const seat = state.turn;
    events.push({ seq: seq++, seat, kind: "pass", cards: [] });
    state = ok(applyPass(state, seat, DEFAULT_SETTINGS));
  };

  play(["3D"]);
  pass();
  pass();
  pass();
  assert.equal(state.trick, null);

  const lead = state.turn;
  events.push({ seq: seq++, seat: lead, kind: "timeout", cards: [] });
  state = ok(applyTimeout(state, DEFAULT_SETTINGS));
  const timed = events.length;

  while (events.length < 12 && state.status === "playing") {
    if (state.trick === null) play([formatCard(state.hands[state.turn][0])]);
    else pass();
  }
  assert.ok(events.length > 8);

  const recent = recentActions(deck, running, true, null, events, DEFAULT_SETTINGS);
  assert.equal(recent.length, 8);
  assert.deepEqual(recent.map((row) => row.seq), events.slice(-8).map((row) => row.seq));
  assert.equal(recent[0].seq, events[events.length - 8].seq);

  const first = recentActions(deck, running, true, null, events.slice(0, timed), DEFAULT_SETTINGS);
  assert.equal(first[0].kind, "play");
  assert.deepEqual(first[0].cards, ["3D"]);
  assert.equal(first[0].label, "3");
  assert.equal(first[1].kind, "pass");
  assert.equal(first[1].label, "Pass");
  assert.deepEqual(first[1].cards, []);
  assert.equal(first[2].kind, "pass");
  assert.equal(first[3].kind, "pass");
  assert.equal(first[4].kind, "play");
  assert.equal(first[4].cards.length, 1);
  assert.ok(first[4].label.length > 0);
});
