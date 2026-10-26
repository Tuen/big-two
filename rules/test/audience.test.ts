import assert from "node:assert/strict";
import test from "node:test";
import {
  chatText,
  clipSpectator,
  freshViewers,
  visibleChat,
  CHAT_LIMIT,
} from "../../supabase/functions/_shared/audience.ts";

test("chat stays short and a viewer never receives a hand", () => {
  assert.equal(chatText("  hello   table ").ok && chatText("  hello   table ").text, "hello table");
  assert.equal(chatText("   ").ok, false);
  assert.equal(chatText("x".repeat(CHAT_LIMIT + 1)).ok, false);
  assert.equal(chatText("x".repeat(CHAT_LIMIT)).ok, true);

  const clipped = clipSpectator({
    yourCards: ["AS", "KH"],
    counts: [13, 13, 13, 13],
    canUndo: true,
    canDeal: true,
    canNewRound: true,
    canEditSettings: true,
  }, true);
  assert.deepEqual(clipped.yourCards, []);
  assert.equal(clipped.watching, true);
  assert.equal(clipped.canUndo, false);
  assert.equal(clipped.canDeal, false);
  assert.equal(clipped.counts[0], 13);

  const player = clipSpectator({ yourCards: ["3D"], canUndo: true }, false);
  assert.deepEqual(player.yourCards, ["3D"]);
  assert.equal(player.watching, false);
});

test("chat clears when the round ends, and stale viewers drop off", () => {
  assert.deepEqual(visibleChat([{ id: 1, text: "hi" }], true), []);
  assert.equal(visibleChat([{ id: 1, text: "hi" }], false).length, 1);
  const now = Date.parse("2026-10-27T00:00:20.000Z");
  const rows = freshViewers([
    { name: "Ada", last_seen: "2026-10-27T00:00:10.000Z" },
    { name: "Gone", last_seen: "2026-10-27T00:00:00.000Z" },
  ], now);
  assert.deepEqual(rows.map((row) => row.name), ["Ada"]);
});
