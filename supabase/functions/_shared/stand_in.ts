import { viewerIsFresh } from "./audience.ts";

/**
 * A seat stays with whoever is in it until that person presses Exit.
 * Closing the app, dropping the connection, or going quiet does not free it.
 * There is no timeout.
 */
export function droppedConnectionFreesSeat(): boolean {
  return false;
}

export interface WatcherCandidate {
  user_id: string;
  display_name: string;
  last_seen: string;
  joined_at: string;
}

/** The watcher who started watching first, among people still here. */
export function nextWatcher<T extends WatcherCandidate>(rows: readonly T[], now = Date.now()): T | null {
  const fresh = rows.filter((row) => viewerIsFresh(row.last_seen, now));
  fresh.sort((a, b) => {
    const at = Date.parse(a.joined_at) - Date.parse(b.joined_at);
    if (at !== 0) return at;
    return a.user_id < b.user_id ? -1 : a.user_id > b.user_id ? 1 : 0;
  });
  return fresh[0] ?? null;
}

export function sameName(left: string, right: string): boolean {
  return left.trim().toLowerCase() === right.trim().toLowerCase();
}

/** `taker` is the watcher name, or null when a computer takes the seat. */
export function leaveNotice(leaver: string, taker: string | null): string {
  const who = taker ?? "A computer";
  return `${leaver} left. ${who} took their seat.`;
}

export function returnNotice(name: string): string {
  return `${name} is back in their seat.`;
}

export interface StandInReport {
  played: boolean;
  who: string | null;
}

const EMPTY_STAND_IN: StandInReport = { played: false, who: null };

export function emptyStandIns(): StandInReport[] {
  return [EMPTY_STAND_IN, EMPTY_STAND_IN, EMPTY_STAND_IN, EMPTY_STAND_IN].map((item) => ({ ...item }));
}

/** Names recorded while a hand is in progress. `who` is a list, in the order they sat. */
export function standInsAtDeal(
  seats: readonly { seat_index: number; stand_in?: string | null; stand_in_name?: string | null }[],
): ({ played: true; who: string[] } | null)[] {
  const slots: ({ played: true; who: string[] } | null)[] = [null, null, null, null];
  for (const seat of seats) {
    if (seat.seat_index < 0 || seat.seat_index > 3 || !seat.stand_in) continue;
    const who = seat.stand_in === "computer" ? "computer" : String(seat.stand_in_name || "watcher");
    slots[seat.seat_index] = { played: true, who: [who] };
  }
  return slots;
}

function namesFromSlot(slot: unknown): string[] {
  if (!slot || typeof slot !== "object") return [];
  const who = (slot as { who?: unknown }).who;
  if (Array.isArray(who)) {
    return who.map((name) => String(name ?? "").trim()).filter((name) => name.length > 0);
  }
  if (typeof who === "string" && who.trim()) return [who.trim()];
  return [];
}

/**
 * Public score shape. One entry per seat.
 * `who` is a watcher name, "computer", or several joined in the order they sat.
 * A stand-in does not change the player name on the score, and does not set hasBots.
 */
export function standInsForWebhook(
  recorded: unknown,
  seats: readonly { seat_index: number; stand_in?: string | null; stand_in_name?: string | null }[] = [],
): StandInReport[] {
  const names: string[][] = [[], [], [], []];
  const source = Array.isArray(recorded) ? recorded : [];
  for (let seat = 0; seat < 4; seat++) {
    for (const name of namesFromSlot(source[seat])) {
      if (!names[seat].includes(name)) names[seat].push(name);
    }
  }
  for (const seat of seats) {
    if (!seat.stand_in || seat.seat_index < 0 || seat.seat_index > 3) continue;
    const who = seat.stand_in === "computer" ? "computer" : String(seat.stand_in_name || "watcher");
    if (!names[seat.seat_index].includes(who)) names[seat.seat_index].push(who);
  }
  return names.map((list) => (list.length === 0 ? { played: false, who: null } : { played: true, who: list.join(", ") }));
}

/** Lobby computer players count toward practice. A stand-in computer does not. */
export function scoringBotNames(
  seats: readonly { seat_index: number; is_bot?: boolean; stand_in?: string | null; display_name?: string }[],
): string[] {
  return seats
    .filter((seat) => seat.is_bot && !seat.stand_in)
    .slice()
    .sort((a, b) => a.seat_index - b.seat_index)
    .map((seat) => String(seat.display_name ?? ""));
}
