/** Viewers and table chat. A viewer is not a seat and never receives a hand. */

export const CHAT_LIMIT = 200;
export const VIEWER_WINDOW_MS = 20_000;
export const VIEWER_CAP = 30;

export interface ChatLine {
  id: number;
  name: string;
  viewer: boolean;
  text: string;
  notice?: boolean;
}

export interface WatcherListed {
  user_id?: string;
  display_name?: string;
  last_seen: string;
  joined_at?: string;
}

/** Fresh watchers, earliest first. Empty when nobody is watching. */
export function watchingNames(rows: readonly WatcherListed[], now = Date.now()): string[] {
  return rows
    .filter((row) => viewerIsFresh(row.last_seen, now) && String(row.display_name ?? "").trim())
    .slice()
    .sort((a, b) => {
      const at = (Date.parse(a.joined_at ?? "") || 0) - (Date.parse(b.joined_at ?? "") || 0);
      if (at !== 0) return at;
      return String(a.user_id ?? "").localeCompare(String(b.user_id ?? ""));
    })
    .map((row) => String(row.display_name).trim());
}

/** "Watching: Ralph, Ada", or null when the list is empty. */
export function watchingLine(names: readonly string[]): string | null {
  if (names.length === 0) return null;
  return `Watching: ${names.join(", ")}`;
}

export function chatText(value: unknown): { ok: true; text: string } | { ok: false; message: string } {
  const text = String(value ?? "").replace(/[\u0000-\u001F]/g, "").replace(/\s+/g, " ").trim();
  if (!text) return { ok: false, message: "Enter a message" };
  if (text.length > CHAT_LIMIT) return { ok: false, message: "Keep it to 200 characters" };
  return { ok: true, text };
}

export function viewerIsFresh(lastSeen: string, now = Date.now()): boolean {
  const at = new Date(lastSeen).getTime();
  return Number.isFinite(at) && now - at < VIEWER_WINDOW_MS;
}

export function freshViewers<T extends { last_seen: string }>(rows: readonly T[], now = Date.now()): T[] {
  return rows.filter((row) => viewerIsFresh(row.last_seen, now));
}

/** The chat belongs to this round. It is gone once the round is over. */
export function visibleChat<T>(lines: readonly T[], roundOver: boolean): T[] {
  return roundOver ? [] : [...lines];
}

/**
 * What a watcher is allowed to receive. Hands stay on the server.
 * Play, pass, undo, dealing, and the next round stay with the four seats.
 */
export function clipSpectator<T extends Record<string, unknown>>(view: T, watching: boolean): T {
  if (!watching) return { ...view, watching: false };
  return {
    ...view,
    watching: true,
    yourCards: [],
    canUndo: false,
    canDeal: false,
    canNewRound: false,
    canEditSettings: false,
  };
}
