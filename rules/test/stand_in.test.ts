import assert from "node:assert/strict";
import test from "node:test";
import { watchingLine, watchingNames } from "../../supabase/functions/_shared/audience.ts";
import { webhookPayload } from "../../supabase/functions/_shared/rules/score.ts";
import {
  droppedConnectionFreesSeat,
  leaveNotice,
  nextWatcher,
  returnNotice,
  sameName,
  scoringBotNames,
  standInsAtDeal,
  standInsForWebhook,
} from "../../supabase/functions/_shared/stand_in.ts";

const now = Date.parse("2026-10-27T12:00:20.000Z");

test("a dropped connection does not free a seat", () => {
  assert.equal(droppedConnectionFreesSeat(), false);
});

test("the watcher who started first is offered the seat", () => {
  const rows = [
    {
      user_id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
      display_name: "Ada",
      joined_at: "2026-10-27T12:00:10.000Z",
      last_seen: "2026-10-27T12:00:19.000Z",
    },
    {
      user_id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      display_name: "Ralph",
      joined_at: "2026-10-27T12:00:05.000Z",
      last_seen: "2026-10-27T12:00:18.000Z",
    },
    {
      user_id: "cccccccc-cccc-cccc-cccc-cccccccccccc",
      display_name: "Gone",
      joined_at: "2026-10-27T12:00:01.000Z",
      last_seen: "2026-10-27T11:59:00.000Z",
    },
  ];
  assert.equal(nextWatcher(rows, now)?.display_name, "Ralph");
  assert.deepEqual(watchingNames(rows, now), ["Ralph", "Ada"]);
  assert.equal(watchingLine(watchingNames(rows, now)), "Watching: Ralph, Ada");
  assert.equal(watchingLine([]), null);
});

test("the same name ignores capitals", () => {
  assert.equal(sameName("mary", "Mary"), true);
  assert.equal(sameName(" Mary ", "mary"), true);
  assert.equal(sameName("Mary", "Maria"), false);
});

test("exit and return notices name the person and the stand-in", () => {
  assert.equal(leaveNotice("Mary", "Ralph"), "Mary left. Ralph took their seat.");
  assert.equal(leaveNotice("Mary", null), "Mary left. A computer took their seat.");
  assert.equal(returnNotice("Mary"), "Mary is back in their seat.");
});

test("a stand-in is named on the score without changing the old fields or hasBots", () => {
  const recorded = standInsAtDeal([
    { seat_index: 0, stand_in: null },
    { seat_index: 1, stand_in: "watcher", stand_in_name: "Ralph" },
    { seat_index: 2, stand_in: null },
    { seat_index: 3, stand_in: null },
  ]);
  const standIns = standInsForWebhook(recorded, [
    { seat_index: 1, stand_in: "watcher", stand_in_name: "Ralph" },
    { seat_index: 2, stand_in: "computer", stand_in_name: "computer" },
  ]);
  assert.deepEqual(standIns, [
    { played: false, who: null },
    { played: true, who: "Ralph" },
    { played: true, who: "computer" },
    { played: false, who: null },
  ]);

  const body = webhookPayload({
    handId: "hand-1",
    tableCode: "ABC123",
    season: 24,
    round: 11,
    hand: 3,
    date: "2026-10-23",
    players: ["Justin", "Mary", "Pauline", "Damien"],
    cardsLeft: [0, 11, 9, 4],
    handPoints: [8, 30, 17, 4],
    runningTotals: [28, 60, 55, 49],
    roundOver: true,
    bonuses: [{ seat: 3, kind: "straight_flush", combo: "straight flush", pointsEach: 8 }],
    standIns,
  });
  assert.equal(body.players[1], "Mary");
  assert.equal(body.hasBots, false);
  assert.deepEqual(body.bots, []);
  assert.equal(body.roundWinner, "Justin");
  assert.deepEqual(body.bonuses, [{ player: "Damien", combo: "straight flush", pointsEach: 8 }]);
  assert.deepEqual(body.standIns[1], { played: true, who: "Ralph" });
  assert.deepEqual(body.standIns[2], { played: true, who: "computer" });
  assert.deepEqual(Object.keys(body), [
    "handId",
    "tableCode",
    "season",
    "round",
    "hand",
    "date",
    "players",
    "cardsLeft",
    "handPoints",
    "bonuses",
    "runningTotals",
    "roundOver",
    "roundWinner",
    "hasBots",
    "bots",
    "standIns",
  ]);
});

test("a lobby computer still counts, and a stand-in computer does not", () => {
  assert.deepEqual(scoringBotNames([
    { seat_index: 1, is_bot: true, stand_in: "computer", display_name: "Mary" },
    { seat_index: 0, is_bot: true, display_name: "Bot Ruby" },
  ]), ["Bot Ruby"]);
});

test("two stand-ins on one seat stay in the order they sat", () => {
  const body = standInsForWebhook([
    null,
    { played: true, who: ["Ralph"] },
    null,
    null,
  ], [{ seat_index: 1, stand_in: "computer" }]);
  assert.equal(body[1].who, "Ralph, computer");
});
