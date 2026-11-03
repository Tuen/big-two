import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  SEEN_WRITE_MS,
  bundleRpcNeedsOldSignature,
  parseHistoryCursor,
  resultIncluded,
  seenIsFresh,
} from "../../supabase/functions/_shared/traffic.ts";

const now = Date.parse("2026-11-03T00:00:10.000Z");

test("a seat seen under ten seconds ago is not written again", () => {
  assert.equal(SEEN_WRITE_MS, 10_000);
  assert.equal(seenIsFresh("2026-11-03T00:00:00.001Z", now), true);
  assert.equal(seenIsFresh("2026-11-03T00:00:00.000Z", now), false);
  assert.equal(seenIsFresh(null, now), false);
  assert.equal(seenIsFresh("not-a-time", now), false);
});

test("the history cursor is the last hand the phone already has", () => {
  assert.deepEqual(parseHistoryCursor({ afterRound: 2, afterHand: 4 }), { round: 2, hand: 4 });
  assert.deepEqual(parseHistoryCursor({ afterRound: 1, afterHand: 0 }), { round: 1, hand: 0 });
  assert.equal(parseHistoryCursor({}), null);
  assert.equal(parseHistoryCursor({ afterRound: 0, afterHand: 1 }), null);
  assert.equal(parseHistoryCursor({ afterRound: 1.5, afterHand: 1 }), null);
  assert.equal(parseHistoryCursor({ afterRound: "1", afterHand: "2" }), null);
});

test("a repeat read returns only new hands, the cursor hand, and unfinished scores", () => {
  const cursor = { round: 2, hand: 3 };
  const row = (round: number, hand: number, status: string | null = "sent") => ({
    round_number: round,
    hand_number: hand,
    webhook_status: status,
  });
  assert.equal(resultIncluded(row(2, 2), cursor), false);
  assert.equal(resultIncluded(row(2, 3, "sent"), cursor), true);
  assert.equal(resultIncluded(row(2, 4), cursor), true);
  assert.equal(resultIncluded(row(3, 1), cursor), true);
  assert.equal(resultIncluded(row(1, 9, "pending"), cursor), true);
  assert.equal(resultIncluded(row(1, 8, "sending"), cursor), true);
  assert.equal(resultIncluded(row(1, 7, "failed"), cursor), true);
  assert.equal(resultIncluded(row(1, 6, "skipped"), cursor), false);
  assert.equal(resultIncluded(row(1, 1), null), true);
});

test("an older database function is detected without hiding other errors", () => {
  assert.equal(
    bundleRpcNeedsOldSignature("Could not find the function public.load_table_bundle(p_table, p_after_round) in the schema cache"),
    true,
  );
  assert.equal(bundleRpcNeedsOldSignature("permission denied for function load_table_bundle"), false);
});

test("the migration encodes the same incremental result rule", () => {
  const sql = readFileSync(
    new URL("../../supabase/migrations/009_incremental_results.sql", import.meta.url),
    "utf8",
  );
  assert.match(sql, /coalesce\(p_include_results, true\) is false/);
  assert.match(sql, /p_after_round is null/);
  assert.match(sql, /r\.round_number > p_after_round/);
  assert.match(sql, /r\.hand_number > coalesce\(p_after_hand, 0\)/);
  assert.match(sql, /r\.hand_number = p_after_hand/);
  assert.match(sql, /r\.webhook_status in \('pending', 'sending', 'failed'\)/);
  assert.match(sql, /drop function if exists public\.load_table_bundle\(uuid\)/);
});
