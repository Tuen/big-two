/** Idle-traffic rules. Gameplay does not depend on these. */

export const SEEN_WRITE_MS = 10_000;

export type HistoryCursor = { round: number; hand: number };

export function parseHistoryCursor(body: Record<string, unknown>): HistoryCursor | null {
  if (typeof body.afterRound !== "number" || typeof body.afterHand !== "number") return null;
  const round = body.afterRound;
  const hand = body.afterHand;
  if (!Number.isInteger(round) || round < 1 || round > 9999) return null;
  if (!Number.isInteger(hand) || hand < 0 || hand > 9999) return null;
  return { round, hand };
}

/** True when a seat or watcher was written recently enough to skip another write. */
export function seenIsFresh(value: unknown, now = Date.now()): boolean {
  const at = value instanceof Date ? value.getTime() : Date.parse(String(value ?? ""));
  return Number.isFinite(at) && now - at < SEEN_WRITE_MS;
}

export type HandResultKey = {
  round_number: number;
  hand_number: number;
  webhook_status?: string | null;
};

/**
 * Which saved hands a repeat read needs.
 * The first read (no cursor) returns every hand.
 * A later read returns hands after the cursor, the cursor hand itself
 * (so a score status can change), and any hand still being reported.
 * Migration 009 applies the same rule inside load_table_bundle.
 */
export function resultIncluded(row: HandResultKey, cursor: HistoryCursor | null): boolean {
  if (!cursor) return true;
  if (row.round_number > cursor.round) return true;
  if (row.round_number === cursor.round && row.hand_number > cursor.hand) return true;
  if (cursor.hand > 0 && row.round_number === cursor.round && row.hand_number === cursor.hand) return true;
  const status = row.webhook_status ?? "";
  return status === "pending" || status === "sending" || status === "failed";
}

/** PostgREST says this when the deployed function does not take the new arguments yet. */
export function bundleRpcNeedsOldSignature(message: string): boolean {
  return /could not find the function/i.test(message) || /schema cache/i.test(message);
}
