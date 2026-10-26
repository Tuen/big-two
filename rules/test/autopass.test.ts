import assert from "node:assert/strict";
import test from "node:test";
import { chooseMove } from "../../supabase/functions/_shared/bots/choose.ts";
import { formatCard, fullDeck, parseCards } from "../../supabase/functions/_shared/rules/cards.ts";
import { identify } from "../../supabase/functions/_shared/rules/combo.ts";
import {
  applyPass,
  applyPlay,
  AUTO_PASS_WAIT_MS,
  DEFAULT_SETTINGS,
  legalSelections,
  makeState,
  NO_PLAY_MESSAGE,
  playIssue,
  passIssue,
  serverAutomatic,
  shouldAutoPass,
  stuckLeaderAction,
  stuckOnTwos,
  ONLY_TWOS_NOTE,
  type HandState,
} from "../../supabase/functions/_shared/rules/game.ts";
import { recentActions, type RecentEvent } from "../../supabase/functions/_shared/recent.ts";
import { isLoneTwoOfSpades } from "../../supabase/functions/_shared/undo.ts";

const settings = DEFAULT_SETTINGS;
const story: string[] = [];

function must<T>(value: T | null | undefined, label: string): T {
  assert.ok(value, label);
  return value as T;
}

function state(args: Parameters<typeof makeState>[0]): HandState {
  return makeState(args);
}

test("computer players: auto-pass, a leader left alone, and a pre-selected play", () => {
  const fillers = [
    parseCards(["QC", "4D"]),
    parseCards(["6H", "7H"]),
    parseCards(["8D", "TD"]),
  ];

  const stuck = state({
    hands: [parseCards(["3D", "4C", "5H", "6S", "9C"]), ...fillers],
    turn: 0,
    trick: must(identify(parseCards(["AS"])), "ace"),
    trickSeat: 3,
    trickCards: ["AS"],
  });
  const auto = serverAutomatic(stuck, settings);
  assert.equal(auto?.kind, "pass");
  if (auto?.kind === "pass") {
    assert.equal(auto.message, NO_PLAY_MESSAGE);
    assert.equal(auto.waitMs, AUTO_PASS_WAIT_MS);
    assert.equal(AUTO_PASS_WAIT_MS, 1000);
  }
  assert.equal(legalSelections(stuck, 0, settings).length, 0);
  const pair = state({
    ...stuck,
    trick: must(identify(parseCards(["8C", "8D"])), "pair"),
    trickCards: ["8C", "8D"],
  });
  assert.equal(serverAutomatic(pair, settings), null);
  assert.equal(shouldAutoPass(pair, 0, settings), false);
  const passed = applyPass(stuck, 0, settings);
  assert.equal(passed.ok, true);
  story.push("Auto-pass: seat 1 had nothing against an ace, so the server passed them after 1 second with \"No play – auto pass\". A pair of 8s was not auto-passed.");

  const leader = state({
    hands: [parseCards(["2H"]), ...fillers],
    turn: 0,
  });
  assert.equal(stuckOnTwos(leader, 0, settings), true);
  assert.equal(serverAutomatic(leader, settings), null);
  assert.equal(shouldAutoPass(leader, 0, settings), false);
  assert.equal(passIssue(leader, 0, settings), null);
  const manual = stuckLeaderAction(leader, settings, false);
  assert.equal(manual?.kind, "manual");
  if (manual?.kind === "manual") assert.equal(manual.note, ONLY_TWOS_NOTE);
  const botWait = stuckLeaderAction(leader, settings, true);
  assert.equal(botWait?.kind, "pass");
  if (botWait?.kind === "pass") assert.equal(botWait.waitMs, 1000);
  const botLead = chooseMove({
    seat: 0,
    hand: leader.hands[0],
    played: [],
    counts: leader.hands.map((hand) => hand.length),
    trick: null,
    trickSeat: null,
    firstLead: false,
    running: [0, 0, 0, 0],
    settings,
    difficulty: "normal",
    rng: () => 0,
  });
  assert.equal(botLead.kind, "pass");
  const passedLead = applyPass(leader, 0, settings);
  assert.equal(passedLead.ok, true);
  if (!passedLead.ok) return;
  assert.equal(passedLead.state.turn, 1);
  assert.equal(passedLead.state.trick, null);
  const nextLead = applyPlay(passedLead.state, 1, ["4D"], settings);
  assert.equal(nextLead.ok, true);
  const cameBack = state({
    hands: [parseCards(["2S"]), ...fillers],
    turn: 0,
  });
  assert.equal(stuckOnTwos(cameBack, 0, settings), true);
  assert.equal(serverAutomatic(cameBack, settings), null);
  const twoTwos = state({
    hands: [parseCards(["2H", "2C"]), ...fillers],
    turn: 0,
  });
  assert.equal(stuckOnTwos(twoTwos, 0, settings), false);
  assert.equal(passIssue(twoTwos, 0, settings), "You must lead — passing isn't allowed");
  story.push("Stuck leader: a person holding only the 2 of hearts was leading. They were not auto-passed. Pass was allowed, with \"Only 2s left – can't go out, please pass\". After they passed, the next player led the 4 of diamonds. A computer in that seat passes after 1 second. Two 2s can still be led one at a time, so Pass stays off.");

  const straight = state({
    hands: [parseCards(["JH", "QD", "KC", "AS", "2C"]), ...fillers],
    turn: 0,
    trick: must(identify(parseCards(["3C", "4D", "5H", "6S", "7C"])), "low straight"),
    trickSeat: 1,
    trickCards: ["3C", "4D", "5H", "6S", "7C"],
  });
  assert.equal(shouldAutoPass(straight, 0, settings), false);
  assert.equal(playIssue(straight, 0, parseCards(["JH", "QD", "KC", "AS", "2C"]), settings), null);

  const notAStraight = state({
    hands: [parseCards(["AH", "2D", "3C", "4S", "5H"]), ...fillers],
    turn: 0,
    trick: must(identify(parseCards(["9C", "9D"])), "nines"),
    trickSeat: 2,
    trickCards: ["9C", "9D"],
  });
  assert.equal(identify(parseCards(["AH", "2D", "3C", "4S", "5H"])), null);
  assert.equal(shouldAutoPass(notAStraight, 0, settings), false);

  const forced = state({
    hands: [
      parseCards(["3C", "AS"]),
      parseCards(["QS"]),
      parseCards(["4C", "5C"]),
      parseCards(["6D", "7D"]),
    ],
    turn: 0,
    trick: must(identify(parseCards(["5D"])), "five"),
    trickSeat: 3,
    trickCards: ["5D"],
  });
  assert.equal(shouldAutoPass(forced, 0, settings), false);

  const onlyTwo = state({
    hands: [parseCards(["2H"]), ...fillers],
    turn: 0,
    trick: must(identify(parseCards(["5D"])), "five"),
    trickSeat: 1,
    trickCards: ["5D"],
  });
  assert.equal(serverAutomatic(onlyTwo, settings)?.kind, "pass");

  let table = state({
    hands: [
      parseCards(["9C", "9D", "KH"]),
      parseCards(["3S", "4H", "5D", "6C", "7S"]),
      parseCards(["5H", "5C", "QD"]),
      parseCards(["3C", "4D", "6H"]),
    ],
    turn: 0,
  });
  assert.equal(serverAutomatic(table, settings), null);
  const lead = applyPlay(table, 0, ["KH"], settings);
  assert.equal(lead.ok, true);
  if (!lead.ok) return;
  table = lead.state;
  const notes: string[] = [];
  for (let guard = 0; guard < 6 && table.status === "playing"; guard++) {
    const decision = serverAutomatic(table, settings);
    if (decision?.kind === "pass") {
      assert.notEqual(table.trick, null);
      assert.equal(decision.waitMs, 1000);
      const step = applyPass(table, table.turn, settings);
      assert.equal(step.ok, true);
      if (!step.ok) return;
      notes.push(`seat ${table.turn + 1} ${decision.message}`);
      table = step.state;
      continue;
    }
    if (table.trick === null) {
      assert.notEqual(decision?.kind, "pass");
      notes.push(`seat ${table.turn + 1} leads and was not auto-passed`);
      break;
    }
    const move = chooseMove({
      seat: table.turn,
      hand: table.hands[table.turn],
      played: parseCards(["KH"]),
      counts: table.hands.map((hand) => hand.length),
      trick: table.trick,
      trickSeat: table.trickSeat,
      firstLead: false,
      running: table.running,
      settings,
      difficulty: "normal",
      rng: () => 0,
    });
    assert.equal(move.kind, "play");
    if (move.kind !== "play") return;
    const step = applyPlay(table, table.turn, move.cards, settings);
    assert.equal(step.ok, true);
    if (!step.ok) return;
    notes.push(`seat ${table.turn + 1} plays ${move.cards.join(" ")}`);
    table = step.state;
  }
  assert.ok(notes.some((line) => line.includes(NO_PLAY_MESSAGE)));
  assert.ok(notes.some((line) => line.includes("was not auto-passed")));
  story.push(`Computer-player trick: ${notes.join("; ")}.`);

  const selected = ["KH"];
  const early = state({
    hands: [
      parseCards(["KH", "4C", "9D"]),
      parseCards(["QS", "3C"]),
      parseCards(["6H", "7H"]),
      parseCards(["8D", "TD"]),
    ],
    turn: 1,
    trick: must(identify(parseCards(["5D"])), "five"),
    trickSeat: 3,
    trickCards: ["5D"],
  });
  assert.equal(early.turn === 0, false);
  const mine = state({ ...early, turn: 0 });
  assert.equal(playIssue(mine, 0, parseCards(selected), settings), null);
  const oneTap = applyPlay(mine, 0, selected, settings);
  assert.equal(oneTap.ok, true);
  if (oneTap.ok) assert.equal(oneTap.state.trickCards.includes("KH"), true);
  story.push("Pre-select: KH was chosen before the turn, still beat the 5, and went through on one Play.");

  const tooSmall = state({
    hands: mine.hands,
    turn: 0,
    trick: must(identify(parseCards(["AS"])), "ace"),
    trickSeat: 1,
    trickCards: ["AS"],
  });
  const blocked = playIssue(tooSmall, 0, parseCards(selected), settings);
  assert.equal(blocked, "Doesn't beat the current play");
  const refused = applyPlay(tooSmall, 0, selected, settings);
  assert.equal(refused.ok, false);
  assert.deepEqual(selected, ["KH"]);
  story.push("Pre-select stopped: the same KH was still highlighted, Play was refused because it does not beat the ace, and the cards stayed selected.");
  console.log(story.map((line) => `- ${line}`).join("\n"));
});

test("a no-play pass is labelled for everyone, and a lone 2 of spades is not", () => {
  const byId = new Map(fullDeck().map((card) => [formatCard(card), card]));
  const take = (ids: string[]) => ids.map((id) => {
    const card = byId.get(id);
    assert.ok(card, id);
    byId.delete(id);
    return card;
  });
  const seat0 = take(["2H", "3C", "4C", "5C", "6C", "7C", "8C", "9C", "TC", "JC", "QC", "KC", "AC"]);
  const seat1 = take(["3D", "4D", "5D", "6D", "7D", "8D", "9D", "TD", "JD", "QD", "KD", "AD", "2D"]);
  const rest = [...byId.values()];
  const deck = [...seat0, ...seat1, ...rest];
  assert.equal(deck.length, 52);
  assert.equal(new Set(deck.map(formatCard)).size, 52);
  const events: RecentEvent[] = [
    { seq: 1, seat: 0, kind: "play", cards: ["2H"] },
    { seq: 2, seat: 1, kind: "pass", cards: [] },
  ];
  const recent = recentActions(deck, [0, 0, 0, 0], false, 0, events, settings);
  assert.equal(recent[1].label, NO_PLAY_MESSAGE);
  const pairEvents: RecentEvent[] = [
    { seq: 1, seat: 0, kind: "play", cards: ["3C", "4C", "5C", "6C", "7C"] },
    { seq: 2, seat: 1, kind: "pass", cards: [] },
  ];
  const pairRecent = recentActions(deck, [0, 0, 0, 0], false, 0, pairEvents, settings);
  assert.equal(pairRecent[1].label, "Pass");
  assert.equal(isLoneTwoOfSpades(["2S"]), true);
  assert.equal(isLoneTwoOfSpades(["2S", "2H"]), false);
});

