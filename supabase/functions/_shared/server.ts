import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { chooseMove, type Difficulty } from "./bots/choose.ts";
import { formatCard, parseCards, type Card } from "./rules/cards.ts";
import {
  applyPass,
  applyPlay,
  applyTimeout,
  AUTO_PASS_WAIT_MS,
  automaticLastCard,
  lastCardMessage,
  NO_PLAY_MESSAGE,
  replay,
  roundWinners,
  serverAutomatic,
  shouldAutoPass,
  stuckLeaderAction,
  autoPassBlock,
  autoPassForHumans,
  timeoutBlock,
  type HandState,
  type ReplayEvent,
  type Settings,
  type StepOk,
  DEFAULT_SETTINGS,
} from "./rules/game.ts";
import { commitDeck, cryptoUint32, shuffleDeck, shuffleInPlace } from "./rules/shuffle.ts";
import { formatDate, webhookPayload, type WebhookPayload } from "./rules/score.ts";
import { recentActions, type RecentEvent } from "./recent.ts";
import {
  chatText,
  clipSpectator,
  freshViewers,
  VIEWER_CAP,
  visibleChat,
  type ChatLine,
} from "./audience.ts";
import {
  isLoneTwoOfSpades,
  MOVE_UNDONE,
  TWO_SPADES_MESSAGE,
  UNDO_REJECTED,
  undoOutcome,
  type UndoOpen,
} from "./undo.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const TIMEZONES = [
  "Australia/Melbourne",
  "Australia/Sydney",
  "Australia/Brisbane",
  "Australia/Adelaide",
  "Australia/Perth",
  "Pacific/Auckland",
  "UTC",
];

export class HttpError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function serveAction(action: (req: Request) => Promise<Response>): void {
  Deno.serve(async (req) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    try {
      return await action(req);
    } catch (error) {
      if (error instanceof HttpError) return json({ error: error.message }, error.status);
      console.error(error);
      return json({ error: "Something went wrong on the server" }, 500);
    }
  });
}

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new HttpError(500, `Missing server setting ${name}`);
  return value;
}

export function adminClient(): SupabaseClient {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

async function requireUser(req: Request): Promise<string> {
  const header = req.headers.get("Authorization");
  if (!header) throw new HttpError(401, "Sign in first");
  const client = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: header } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) throw new HttpError(401, "Sign in first");
  return data.user.id;
}

async function readBody(req: Request): Promise<Record<string, unknown>> {
  if (req.method === "GET") return {};
  try {
    const body = await req.json();
    if (!body || typeof body !== "object" || Array.isArray(body)) return {};
    return body as Record<string, unknown>;
  } catch {
    throw new HttpError(400, "Send a JSON body");
  }
}

function cleanName(value: unknown): string {
  const name = String(value ?? "").replace(/\s+/g, " ").trim();
  if (!name) throw new HttpError(400, "Enter your name");
  if (name.length > 24) throw new HttpError(400, "Use a name of 24 characters or fewer");
  return name;
}

function cleanSettings(value: unknown, fallback: Settings = DEFAULT_SETTINGS): Settings {
  const raw = (value && typeof value === "object" ? value : {}) as Record<string, unknown>;
  const timer = Number(raw.turnTimerSeconds ?? fallback.turnTimerSeconds);
  const season = Number(raw.season ?? fallback.season);
  const firstRound = Number(raw.firstRoundNumber ?? fallback.firstRoundNumber);
  const timezone = String(raw.timezone ?? fallback.timezone);
  return {
    passLocks: Boolean(raw.passLocks ?? fallback.passLocks),
    straightsWrap: Boolean(raw.straightsWrap ?? fallback.straightsWrap),
    turnTimerSeconds: [0, 15, 30, 45, 60].includes(timer) ? timer : 0,
    season: Number.isInteger(season) && season >= 1 && season <= 99 ? season : fallback.season,
    timezone: TIMEZONES.includes(timezone) ? timezone : fallback.timezone,
    firstRoundNumber: Number.isInteger(firstRound) && firstRound >= 1 && firstRound <= 999
      ? firstRound
      : fallback.firstRoundNumber,
  };
}

function roomCode(): string {
  const bytes = new Uint8Array(6);
  crypto.getRandomValues(bytes);
  return [...bytes].map((byte) => ALPHABET[byte % ALPHABET.length]).join("");
}

type Row = Record<string, any>;

async function must<T>(promise: PromiseLike<{ data: T; error: { message: string } | null }>): Promise<T> {
  const { data, error } = await promise;
  if (error) throw new HttpError(500, error.message);
  return data;
}

function settingsOf(table: Row): Settings {
  return cleanSettings(table.settings);
}

function rulesV13(table: Row): boolean {
  return table.settings?.v13 === true;
}

/** v1.4 pass rules apply to every table, including ones opened from the live page. */
function rulesV14(_table: Row): boolean {
  return true;
}

function humanCount(seats: Row[]): number {
  return seats.filter((seat) => !seat.is_bot).length;
}

function playerName(seats: Row[], seat: number): string {
  return String(seats.find((item) => item.seat_index === seat)?.display_name ?? `Seat ${seat + 1}`);
}

/**
 * Auto-pass stays on for a normal table.
 * A test-page table with only one human does not auto-pass: that person presses
 * Pass, and the computer players choose for themselves.
 */
function passesAutomatically(table: Row, seats: Row[]): boolean {
  if (!rulesV14(table)) return false;
  if (table.settings?.v14 === true && !autoPassForHumans(humanCount(seats))) return false;
  return true;
}

async function patchSetting(
  admin: SupabaseClient,
  tableId: string,
  key: "hold" | "botWaitUntil",
  value: unknown,
  match: string | null,
): Promise<void> {
  const { error } = await admin.rpc("patch_table_setting", {
    p_table: tableId,
    p_key: key,
    p_value: value,
    p_match: match,
  });
  if (error) throw new HttpError(500, error.message);
}

async function traceMove(
  admin: SupabaseClient,
  table: Row,
  hand: Row | null,
  player: string,
  kind: string,
  tableCards: string,
  reason: string,
): Promise<void> {
  const line = {
    kind,
    table: table.code,
    hand: hand?.hand_number ?? null,
    player,
    tableCards,
    reason,
  };
  console.log(JSON.stringify(line));
  const { error } = await admin.from("move_log").insert({
    table_code: String(table.code ?? ""),
    hand_number: hand?.hand_number ?? null,
    player,
    kind,
    table_cards: tableCards,
    reason,
  });
  if (error) console.error(error.message);
}

function storedSettings(value: unknown, previous?: Row): Row {
  const cleaned = cleanSettings(value, previous ? settingsOf(previous) : DEFAULT_SETTINGS);
  const raw = (value && typeof value === "object" ? value : {}) as Record<string, unknown>;
  const v13 = raw.v13 === true || previous?.settings?.v13 === true;
  const v14 = raw.v14 === true || previous?.settings?.v14 === true;
  const undo = previous?.settings?.undo;
  const hold = previous?.settings?.hold;
  return {
    ...cleaned,
    ...(v13 ? { v13: true } : {}),
    ...(v14 ? { v14: true } : {}),
    ...(undo ? { undo } : {}),
    ...(hold ? { hold } : {}),
  };
}

function undoOf(table: Row): UndoOpen | null {
  const raw = table.settings?.undo;
  if (!raw || typeof raw !== "object" || typeof raw.handId !== "string") return null;
  return {
    handId: raw.handId,
    seq: Number(raw.seq),
    seat: Number(raw.seat),
    name: String(raw.name ?? "A player"),
    openedAt: String(raw.openedAt ?? ""),
    votes: raw.votes && typeof raw.votes === "object" ? { ...raw.votes } : {},
  };
}

async function setUndo(admin: SupabaseClient, table: Row, undo: UndoOpen | null): Promise<void> {
  const settings = { ...table.settings };
  if (undo) settings.undo = undo;
  else delete settings.undo;
  const { error } = await admin.from("game_tables").update({ settings }).eq("id", table.id);
  if (error) throw new HttpError(500, error.message);
  table.settings = settings;
}

async function settleUndo(admin: SupabaseClient, table: Row): Promise<void> {
  const open = undoOf(table);
  if (!open) return;
  const outcome = undoOutcome(open.votes, open.openedAt, Date.now());
  if (outcome === "wait") return;
  if (outcome === "rejected") {
    await setUndo(admin, table, null);
    await admin.from("hands").update({ last_message: UNDO_REJECTED }).eq("id", open.handId);
    return;
  }
  const hand = await latestHand(admin, table.id);
  if (!hand || hand.id !== open.handId || hand.status !== "playing" || hand.webhook_status) {
    await setUndo(admin, table, null);
    return;
  }
  await revertMove(admin, table, hand, open.seq);
}

function held(table: Row, now = Date.now()): boolean {
  const raw = table.settings?.hold;
  if (!raw || typeof raw !== "object") return false;
  const at = Date.parse(String(raw.at ?? ""));
  return Number.isFinite(at) && now - at < 5_000;
}

async function setHold(
  admin: SupabaseClient,
  table: Row,
  hold: { handId: string; at: string } | null,
): Promise<void> {
  if (hold) {
    await patchSetting(admin, table.id, "hold", hold, null);
    table.settings = { ...table.settings, hold };
    return;
  }
  const match = String(table.settings?.hold?.at ?? "");
  await patchSetting(admin, table.id, "hold", null, match || null);
  if (!match || table.settings?.hold?.at === match) {
    const settings = { ...table.settings };
    delete settings.hold;
    table.settings = settings;
  }
}

async function clearStaleHold(admin: SupabaseClient, table: Row): Promise<void> {
  if (table.settings?.hold && !held(table)) await setHold(admin, table, null);
}

async function revertMove(admin: SupabaseClient, table: Row, hand: Row, seq: number): Promise<void> {
  if (hand.status !== "playing" || hand.webhook_status) {
    throw new HttpError(400, "That move ended the hand");
  }
  const { error } = await admin.from("events").delete().eq("hand_id", hand.id).eq("seq", seq);
  if (error) throw new HttpError(500, error.message);
  await setUndo(admin, table, null);
  const seats = await loadSeats(admin, table.id);
  const replayed = await replayHand(admin, hand, settingsOf(table));
  await saveProjection(admin, table, hand, seats, replayed.step, replayed.deckText);
  await admin.from("hands").update({ last_message: MOVE_UNDONE }).eq("id", hand.id);
  await maybeAutoLastCard(admin, table.id);
  await maybeAutoPass(admin, table.id);
  await maybePassStuckBot(admin, table.id);
}

async function openUndo(admin: SupabaseClient, table: Row, seats: Row[], me: Row): Promise<void> {
  await settleUndo(admin, table);
  const fresh = await loadTable(admin, table.id);
  await clearStaleHold(admin, fresh);
  if (undoOf(fresh)) throw new HttpError(400, "An undo vote is already open");
  if (held(fresh)) throw new HttpError(400, "Please wait a moment");
  if (!rulesV13(fresh)) throw new HttpError(400, "Undo is not used at this table");
  const hand = await latestHand(admin, table.id);
  if (!hand || hand.status !== "playing" || hand.webhook_status) {
    throw new HttpError(400, "There is no move to undo");
  }
  const played = await replayHand(admin, hand, settingsOf(fresh));
  const last = played.events[played.events.length - 1];
  if (!last || Number(last.seat_index) !== me.seat_index || (last.kind !== "play" && last.kind !== "pass")) {
    throw new HttpError(400, "You can only undo your own last move, before the next player acts");
  }
  const votes: Record<string, boolean> = {};
  for (const seat of seats) {
    if (seat.seat_index === me.seat_index) continue;
    if (seat.is_bot) votes[String(seat.seat_index)] = true;
  }
  const opened: UndoOpen = {
    handId: hand.id,
    seq: Number(last.seq),
    seat: me.seat_index,
    name: String(me.display_name),
    openedAt: new Date().toISOString(),
    votes,
  };
  const outcome = undoOutcome(opened.votes, opened.openedAt, Date.now());
  if (outcome === "approved") {
    await revertMove(admin, fresh, hand, opened.seq);
    return;
  }
  if (outcome === "rejected") {
    await admin.from("hands").update({ last_message: UNDO_REJECTED }).eq("id", hand.id);
    return;
  }
  await setUndo(admin, fresh, opened);
  await admin.from("hands").update({ last_message: `${opened.name} wants to undo their last move` }).eq("id", hand.id);
}

async function castUndoVote(admin: SupabaseClient, table: Row, me: Row, approve: boolean): Promise<void> {
  const open = undoOf(table);
  if (!open) throw new HttpError(400, "There is no undo to answer");
  if (open.seat === me.seat_index) throw new HttpError(400, "You cannot vote on your own undo");
  const key = String(me.seat_index);
  if (key in open.votes) throw new HttpError(400, "You already answered");
  open.votes[key] = approve;
  await setUndo(admin, table, open);
  await settleUndo(admin, table);
}

async function passTheRest(admin: SupabaseClient, tableId: string): Promise<void> {
  for (let i = 0; i < 3; i++) {
    const table = await loadTable(admin, tableId);
    const hand = await latestHand(admin, tableId);
    if (!hand || hand.status !== "playing") return;
    const played = await replayHand(admin, hand, settingsOf(table));
    const state = played.step.state;
    if (state.status !== "playing") return;
    const step = applyPass(state, state.turn, settingsOf(table));
    if (!step.ok) return;
    const { error } = await admin.from("events").insert({
      hand_id: hand.id,
      seq: played.eventCount + 1,
      seat_index: state.turn,
      kind: "pass",
      payload: { cards: [] },
    });
    if (error) throw new HttpError(500, error.message);
    const seats = await loadSeats(admin, tableId);
    await saveProjection(admin, table, hand, seats, step, played.deckText);
  }
  const hand = await latestHand(admin, tableId);
  if (hand) await admin.from("hands").update({ last_message: TWO_SPADES_MESSAGE }).eq("id", hand.id);
}

function namesOf(seats: Row[]): (string | null)[] {
  const names: (string | null)[] = [null, null, null, null];
  for (const seat of seats) names[seat.seat_index] = seat.display_name;
  return names;
}

async function touch(admin: SupabaseClient, tableId: string, userId: string): Promise<void> {
  const { error } = await admin
    .from("seats")
    .update({ last_seen: new Date().toISOString() })
    .eq("table_id", tableId)
    .eq("user_id", userId);
  if (error) throw new HttpError(500, error.message);
}

async function loadTable(admin: SupabaseClient, tableId: string): Promise<Row> {
  const { data, error } = await admin.from("game_tables").select("*").eq("id", tableId).maybeSingle();
  if (error) throw new HttpError(500, error.message);
  if (!data) throw new HttpError(404, "That table does not exist");
  return data;
}

async function loadSeats(admin: SupabaseClient, tableId: string): Promise<Row[]> {
  return await must(admin.from("seats").select("*").eq("table_id", tableId).order("seat_index"));
}

function requireSeat(seats: Row[], userId: string): Row {
  const seat = seats.find((item) => item.user_id === userId);
  if (!seat) throw new HttpError(403, "You are not at this table");
  return seat;
}

async function viewerRow(admin: SupabaseClient, tableId: string, userId: string): Promise<Row | null> {
  const { data, error } = await admin.from("table_viewers").select("*").eq("table_id", tableId).eq("user_id", userId).maybeSingle();
  if (error) throw new HttpError(500, error.message);
  return data;
}

async function touchViewer(admin: SupabaseClient, tableId: string, userId: string): Promise<void> {
  const { error } = await admin
    .from("table_viewers")
    .update({ last_seen: new Date().toISOString() })
    .eq("table_id", tableId)
    .eq("user_id", userId);
  if (error) throw new HttpError(500, error.message);
}

async function audienceOf(admin: SupabaseClient, table: Row): Promise<{ viewerCount: number; chat: ChatLine[] }> {
  const { data: viewers, error } = await admin.from("table_viewers").select("last_seen").eq("table_id", table.id);
  if (error) throw new HttpError(500, error.message);
  const { data: messages, error: messageError } = await admin
    .from("table_messages")
    .select("id, display_name, viewer, body")
    .eq("table_id", table.id)
    .eq("round_number", table.round_number)
    .order("id", { ascending: false })
    .limit(40);
  if (messageError) throw new HttpError(500, messageError.message);
  const lines = ((messages ?? []) as Row[]).reverse().map((row) => ({
    id: Number(row.id),
    name: String(row.display_name),
    viewer: Boolean(row.viewer),
    text: String(row.body),
  }));
  return {
    viewerCount: freshViewers((viewers ?? []) as { last_seen: string }[]).length,
    chat: visibleChat(lines, table.status === "round_end"),
  };
}

async function clearChat(admin: SupabaseClient, tableId: string): Promise<void> {
  const { error } = await admin.from("table_messages").delete().eq("table_id", tableId);
  if (error) throw new HttpError(500, error.message);
}

function withAudience<T extends Record<string, unknown>>(
  view: T,
  watching: boolean,
  audience: { viewerCount: number; chat: ChatLine[] },
): T {
  const shared = { ...view, viewerCount: audience.viewerCount, chat: audience.chat };
  if (!watching) return clipSpectator(shared, false);
  const seats = Array.isArray(shared.seats)
    ? shared.seats.map((seat) => ({ ...(seat as Row), userId: null }))
    : shared.seats;
  return clipSpectator({ ...shared, seats }, true);
}

async function latestHand(admin: SupabaseClient, tableId: string): Promise<Row | null> {
  const { data, error } = await admin
    .from("hands")
    .select("*")
    .eq("table_id", tableId)
    .order("round_number", { ascending: false })
    .order("hand_number", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw new HttpError(500, error.message);
  return data;
}

async function replayHand(admin: SupabaseClient, hand: Row, settings: Settings) {
  const { data: secret, error } = await admin.from("hand_secrets").select("deck").eq("hand_id", hand.id).single();
  if (error) throw new HttpError(500, error.message);
  const events = await must(
    admin.from("events").select("seq, seat_index, kind, payload").eq("hand_id", hand.id).order("seq"),
  );
  const deck = parseCards(String(secret.deck).split(","));
  const log: ReplayEvent[] = (events as Row[]).map((event) => ({
    kind: event.kind,
    seat: event.seat_index,
    cards: event.payload?.cards ?? [],
  }));
  const step = replay(deck, hand.running_at_start, hand.first_hand, hand.previous_winner, log, settings);
  if (!step.ok) throw new HttpError(500, step.message);
  return { step, eventCount: log.length, deckText: String(secret.deck), events: events as Row[] };
}

function connected(seat: Row): boolean {
  return Date.now() - new Date(seat.last_seen).getTime() < 20_000;
}

async function historyFor(admin: SupabaseClient, tableId: string, roundNumber: number) {
  const rows = await must(
    admin
      .from("hand_results")
      .select("*")
      .eq("table_id", tableId)
      .order("round_number")
      .order("hand_number"),
  );
  const history = (rows as Row[])
    .filter((row) => row.round_number === roundNumber)
    .map(resultJson);
  const archive = (rows as Row[])
    .filter((row) => row.round_over && row.round_number !== roundNumber)
    .map((row) => ({
      round: row.round_number,
      players: row.players,
      runningTotals: row.running_totals,
      winners: roundWinners(row.running_totals),
    }));
  return { history, archive };
}

function resultJson(row: Row) {
  return {
    hand: row.hand_number,
    round: row.round_number,
    players: row.players,
    cardsLeft: row.cards_left,
    handPoints: row.hand_points,
    runningTotals: row.running_totals,
    bonuses: row.bonuses,
    winner: row.winner_seat,
    roundOver: row.round_over,
    date: row.played_on,
    commitment: row.commitment,
    deckReveal: row.deck_reveal,
    scoreStatus: row.webhook_status ?? null,
    hasBots: Boolean(row.has_bots),
    bots: Array.isArray(row.bots) ? row.bots.map((name: unknown) => String(name)) : [],
  };
}

export async function buildView(admin: SupabaseClient, tableId: string, userId: string) {
  await touch(admin, tableId, userId);
  let table = await loadTable(admin, tableId);
  await clearStaleHold(admin, table);
  await settleUndo(admin, table);
  table = await loadTable(admin, tableId);
  const seats = await loadSeats(admin, tableId);
  const me = seats.find((item) => item.user_id === userId) ?? null;
  if (!me) {
    const viewer = await viewerRow(admin, tableId, userId);
    if (!viewer) throw new HttpError(403, "You are not at this table");
    await touchViewer(admin, tableId, userId);
  }
  const audience = await audienceOf(admin, table);
  const watching = me == null;
  const seatIndex = me?.seat_index ?? 0;
  const finish = <T extends Record<string, unknown>>(view: T) => withAudience(view, watching, audience);
  const settings = settingsOf(table);
  const hand = await latestHand(admin, tableId);
  const { history, archive } = await historyFor(admin, tableId, table.round_number);
  const base = {
    tableId: table.id,
    code: table.code,
    status: table.status,
    hostId: table.host_id,
    you: seatIndex,
    season: table.season,
    round: table.round_number,
    settings,
    seats: [0, 1, 2, 3].map((index) => {
      const seat = seats.find((item) => item.seat_index === index);
      return seat
        ? {
            seat: index,
            name: seat.display_name,
            connected: Boolean(seat.is_bot) || connected(seat),
            userId: seat.user_id,
            isBot: Boolean(seat.is_bot),
            difficulty: seat.is_bot ? seat.bot_difficulty : null,
          }
        : { seat: index, name: null, connected: false, userId: null, isBot: false, difficulty: null };
    }),
    history,
    archive,
    canDeal: seats.length === 4 && (table.status === "lobby" || table.status === "hand_end"),
    canNewRound: table.status === "round_end",
    canEditSettings: table.status === "lobby" && !hand,
  };

  if (table.status === "lobby") {
    const message = seats.length === 4
      ? hand
        ? `Round ${table.round_number}. Set the seating, then deal. Seat 1 leads.`
        : "Everyone is here. Seat 1 leads, then play goes to the left."
      : "Waiting for four players.";
    return finish({
      ...base,
      hand: 0,
      yourCards: [] as string[],
      counts: [0, 0, 0, 0],
      turn: null,
      firstLead: false,
      trick: null,
      consecutivePasses: 0,
      locked: [] as number[],
      running: [0, 0, 0, 0],
      commitment: null,
      deckReveal: null,
      message,
      result: null,
      turnStartedAt: null,
      roundOver: false,
      recent: [] as RecentEvent[],
      canUndo: false,
      undo: null,
    });
  }

  if (!hand) {
    return finish({
      ...base,
      hand: 0,
      yourCards: [] as string[],
      counts: [0, 0, 0, 0],
      turn: null,
      firstLead: false,
      trick: null,
      consecutivePasses: 0,
      locked: [] as number[],
      running: [0, 0, 0, 0],
      commitment: null,
      deckReveal: null,
      message: seats.length === 4 ? "Everyone is here. Deal the first hand." : "Waiting for four players.",
      result: null,
      turnStartedAt: null,
      roundOver: false,
      recent: [] as RecentEvent[],
      canUndo: false,
      undo: null,
    });
  }

  const { step, deckText, events } = await replayHand(admin, hand, settings);
  const state = step.state;
  const score = step.result;
  const names = namesOf(seats).map((name, index) => name ?? `Seat ${index + 1}`);
  const recent = recentActions(
    parseCards(deckText.split(",")),
    hand.running_at_start,
    Boolean(hand.first_hand),
    hand.previous_winner ?? null,
    (events as Row[]).map((event) => ({
      seq: Number(event.seq),
      seat: Number(event.seat_index),
      kind: String(event.kind),
      cards: Array.isArray(event.payload?.cards) ? event.payload.cards.map((card: unknown) => String(card)) : [],
    })),
    settings,
    rulesV14(table),
  );
  const open = undoOf(table);
  const last = events.length > 0 ? events[events.length - 1] : null;
  const canUndo = !!me
    && rulesV13(table)
    && hand.status === "playing"
    && !open
    && !held(table)
    && !!last
    && Number(last.seat_index) === me.seat_index
    && (last.kind === "play" || last.kind === "pass");
  const undo = open && open.handId === hand.id
    ? {
        seat: open.seat,
        name: open.name,
        openedAt: open.openedAt,
        youVoted: !!me && Object.prototype.hasOwnProperty.call(open.votes, String(me.seat_index)),
      }
    : null;
  return finish({
    ...base,
    hand: hand.hand_number,
    yourCards: me ? state.hands[me.seat_index].map(formatCard) : [],
    counts: state.hands.map((cards) => cards.length),
    turn: state.status === "playing" ? state.turn : null,
    firstLead: state.firstLead,
    trick: state.trick
      ? { seat: state.trickSeat, cards: state.trickCards, label: state.trick.label }
      : null,
    consecutivePasses: state.consecutivePasses,
    locked: state.locked,
    running: score ? score.runningTotals : state.running,
    commitment: hand.commitment,
    deckReveal: hand.deck_reveal,
    message: hand.last_message ?? step.message,
    result: score
      ? {
          cardsLeft: score.cardsLeft,
          cardPoints: score.cardPoints,
          bonusReceived: score.bonusReceived,
          handPoints: score.handPoints,
          runningTotals: score.runningTotals,
          roundOver: score.roundOver,
          winner: score.winner,
          closedReason: score.closedReason,
          bonuses: score.bonuses.map((bonus) => ({
            seat: bonus.seat,
            player: names[bonus.seat],
            combo: bonus.combo,
            pointsEach: bonus.pointsEach,
          })),
        }
      : null,
    turnStartedAt: hand.turn_started_at,
    roundOver: Boolean(hand.round_over),
    recent,
    canUndo,
    undo,
    holding: held(table),
  });
}

async function saveProjection(
  admin: SupabaseClient,
  table: Row,
  hand: Row,
  seats: Row[],
  step: StepOk,
  deckText: string,
) {
  const state = step.state;
  const names = namesOf(seats).map((name, index) => name ?? `Seat ${index + 1}`);
  const now = new Date().toISOString();
  const patch: Row = {
    status: state.status === "complete" ? "complete" : "playing",
    turn_seat: state.status === "playing" ? state.turn : null,
    turn_started_at: now,
    last_message: step.message,
    winner_seat: state.winner,
  };

  if (state.status === "complete" && step.result) {
    const result = step.result;
    const date = formatDate(new Date(), settingsOf(table).timezone);
    const bots = botNames(seats);
    const body: WebhookPayload = webhookPayload({
      handId: hand.id,
      tableCode: table.code,
      season: table.season,
      round: hand.round_number,
      hand: hand.hand_number,
      date,
      players: names,
      cardsLeft: result.cardsLeft,
      handPoints: result.handPoints,
      runningTotals: result.runningTotals,
      roundOver: result.roundOver,
      bonuses: result.bonuses,
      hasBots: bots.length > 0,
      bots,
    });
    patch.deck_reveal = deckText;
    patch.round_over = result.roundOver;
    patch.webhook_status = "pending";
    patch.webhook_body = body;
    const { error: resultError } = await admin.from("hand_results").upsert({
      hand_id: hand.id,
      table_id: table.id,
      round_number: hand.round_number,
      hand_number: hand.hand_number,
      players: names,
      cards_left: result.cardsLeft,
      hand_points: result.handPoints,
      running_totals: result.runningTotals,
      bonuses: body.bonuses,
      winner_seat: result.winner,
      round_over: result.roundOver,
      played_on: date,
      commitment: hand.commitment,
      deck_reveal: deckText,
      webhook_status: "pending",
      has_bots: body.hasBots,
      bots: body.bots,
    });
    if (resultError) throw new HttpError(500, resultError.message);
    const { error: tableError } = await admin
      .from("game_tables")
      .update({ status: result.roundOver ? "round_end" : "hand_end" })
      .eq("id", table.id);
    if (tableError) throw new HttpError(500, tableError.message);
    if (result.roundOver) await clearChat(admin, table.id);
  }

  const { error } = await admin.from("hands").update(patch).eq("id", hand.id);
  if (error) throw new HttpError(500, error.message);
  for (let seat = 0; seat < 4; seat++) {
    const { error: holdingError } = await admin.from("holdings").upsert({
      hand_id: hand.id,
      seat_index: seat,
      cards: state.hands[seat].map(formatCard),
    });
    if (holdingError) throw new HttpError(500, holdingError.message);
  }
  if (state.status === "complete") await sendWebhook(admin, hand.id);
}

const WEBHOOK_BURST = 5;
const WEBHOOK_CAP = 15;
const WEBHOOK_CLAIM_MS = 60_000;

function webhookHeaders(): Record<string, string> {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  const key = Deno.env.get("SCORE_WEBHOOK_KEY") || Deno.env.get("SCORE_WEBHOOK_SECRET") || "";
  const named = Deno.env.get("SCORE_WEBHOOK_KEY_HEADER")?.trim() ?? "";
  const namedOk = /^[A-Za-z0-9-]{1,64}$/.test(named);
  const legacyOnly = Boolean(Deno.env.get("SCORE_WEBHOOK_SECRET")) && !Deno.env.get("SCORE_WEBHOOK_KEY");
  const headerName = namedOk ? named : legacyOnly ? "X-Score-Secret" : "X-Score-Key";
  if (key) headers[headerName] = key;
  return headers;
}

async function markWebhook(admin: SupabaseClient, handId: string, status: string, attempts?: number) {
  const patch: Row = { webhook_status: status };
  if (attempts != null) patch.webhook_attempts = attempts;
  if (status === "sent" || status === "failed" || status === "skipped") patch.webhook_claimed_at = null;
  await admin.from("hands").update(patch).eq("id", handId);
  await admin.from("hand_results").update({ webhook_status: status }).eq("hand_id", handId);
}

async function sendWebhook(admin: SupabaseClient, handId: string): Promise<void> {
  const url = Deno.env.get("SCORE_WEBHOOK_URL");
  const { data: hand, error } = await admin
    .from("hands")
    .select("webhook_status, webhook_attempts, webhook_body, webhook_claimed_at")
    .eq("id", handId)
    .single();
  if (error || !hand) return;
  const status = String(hand.webhook_status ?? "");
  if (!url) {
    if (status === "pending") await markWebhook(admin, handId, "skipped");
    return;
  }
  if (status !== "pending" && status !== "failed" && status !== "sending") return;
  let tries = Number(hand.webhook_attempts ?? 0);
  if (tries >= WEBHOOK_CAP) {
    await markWebhook(admin, handId, "failed", tries);
    return;
  }

  const now = new Date().toISOString();
  let claimed = false;
  if (status === "pending" || status === "failed") {
    const { data, error: claimError } = await admin
      .from("hands")
      .update({ webhook_status: "sending", webhook_claimed_at: now })
      .eq("id", handId)
      .in("webhook_status", ["pending", "failed"])
      .select("id");
    claimed = !claimError && Boolean(data?.length);
  } else {
    const claimedAt = hand.webhook_claimed_at ? new Date(hand.webhook_claimed_at).getTime() : 0;
    if (hand.webhook_claimed_at && Date.now() - claimedAt < WEBHOOK_CLAIM_MS) return;
    let claim = admin
      .from("hands")
      .update({ webhook_status: "sending", webhook_claimed_at: now })
      .eq("id", handId)
      .eq("webhook_status", "sending");
    claim = hand.webhook_claimed_at ? claim.eq("webhook_claimed_at", hand.webhook_claimed_at) : claim.is("webhook_claimed_at", null);
    const { data, error: claimError } = await claim.select("id");
    claimed = !claimError && Boolean(data?.length);
  }
  if (!claimed) return;

  const later = status === "failed";
  const budget = later ? 1 : Math.min(WEBHOOK_BURST, WEBHOOK_CAP - tries);
  const limit = tries + budget;
  const headers = webhookHeaders();
  const started = tries;
  const body = JSON.stringify(hand.webhook_body);
  let sent = false;
  while (tries < limit && !sent) {
    tries += 1;
    await admin.from("hands").update({ webhook_status: "sending", webhook_attempts: tries }).eq("id", handId);
    let statusCode: number | null = null;
    let detail = "";
    try {
      const response = await fetch(url, { method: "POST", headers, body });
      statusCode = response.status;
      sent = response.ok;
      if (!sent) detail = `HTTP ${response.status}`;
    } catch (error) {
      detail = String(error instanceof Error ? error.message : error).slice(0, 200);
    }
    await admin.from("webhook_log").insert({
      hand_id: handId,
      ok: sent,
      status_code: statusCode,
      detail: detail || null,
    });
    if (!sent && tries < limit) {
      await new Promise((resolve) => setTimeout(resolve, 400 * 2 ** (tries - started - 1)));
    }
  }
  await markWebhook(admin, handId, sent ? "sent" : "failed", tries);
}

async function claimLobby(admin: SupabaseClient, tableId: string) {
  const { data, error } = await admin
    .from("game_tables")
    .update({ status: "playing" })
    .eq("id", tableId)
    .eq("status", "lobby")
    .select("id");
  if (error) throw new HttpError(500, error.message);
  if (!data || data.length === 0) throw new HttpError(409, "The table changed. Try that again.");
}

async function releaseLobby(admin: SupabaseClient, tableId: string) {
  await admin.from("game_tables").update({ status: "lobby" }).eq("id", tableId).eq("status", "playing");
}

async function dealHand(admin: SupabaseClient, table: Row, seats: Row[], userId: string) {
  if (seats.length !== 4) throw new HttpError(400, "Wait until four players are seated");
  requireSeat(seats, userId);
  const settings = settingsOf(table);
  const previous = await latestHand(admin, table.id);
  let roundNumber = table.round_number;
  let handNumber = 1;
  let firstHand = true;
  let previousWinner: number | null = null;
  let running = [0, 0, 0, 0];
  let lobbyDeal = false;

  if (!previous || previous.round_number !== table.round_number) {
    if (table.status !== "lobby") throw new HttpError(400, "The table is not ready to deal");
    lobbyDeal = true;
  } else if (previous.status !== "complete") {
    throw new HttpError(400, "The current hand is still going");
  } else if (previous.round_over) {
    throw new HttpError(400, "Start a new round before dealing");
  } else {
    const { step } = await replayHand(admin, previous, settings);
    if (!step.result) throw new HttpError(500, "The last hand has no score");
    roundNumber = previous.round_number;
    handNumber = previous.hand_number + 1;
    firstHand = false;
    previousWinner = step.result.winner;
    running = step.result.runningTotals;
  }

  if (lobbyDeal) {
    await claimLobby(admin, table.id);
    seats = await loadSeats(admin, table.id);
    if (seats.length !== 4) {
      await releaseLobby(admin, table.id);
      throw new HttpError(400, "Wait until four players are seated");
    }
    requireSeat(seats, userId);
  }

  const deck: Card[] = shuffleDeck();
  const committed = await commitDeck(deck);
  const { data: hand, error } = await admin
    .from("hands")
    .insert({
      table_id: table.id,
      round_number: roundNumber,
      hand_number: handNumber,
      first_hand: firstHand,
      previous_winner: previousWinner,
      running_at_start: running,
      commitment: committed.commitment,
      status: "playing",
      last_message: "Deal",
    })
    .select("*")
    .single();
  if (error) {
    if (lobbyDeal) await releaseLobby(admin, table.id);
    throw new HttpError(400, "The hand was already dealt");
  }
  const { error: secretError } = await admin.from("hand_secrets").insert({ hand_id: hand.id, deck: committed.canonical });
  if (secretError) {
    await admin.from("hands").delete().eq("id", hand.id);
    if (lobbyDeal) await releaseLobby(admin, table.id);
    throw new HttpError(500, secretError.message);
  }
  const { error: tableError } = await admin.from("game_tables").update({ status: "playing" }).eq("id", table.id);
  if (tableError) throw new HttpError(500, tableError.message);
  const dealt = await replayHand(admin, hand, settings);
  await saveProjection(
    admin,
    table,
    hand,
    seats,
    { ok: true, state: dealt.step.state, result: null, message: "Deal" },
    committed.canonical,
  );
}

async function playHeldLastCard(
  admin: SupabaseClient,
  tableId: string,
  seat: number,
  card: string,
): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, 1000));
  const table = await loadTable(admin, tableId);
  if (!rulesV13(table) || undoOf(table)) return;
  const hand = await latestHand(admin, tableId);
  if (!hand || hand.status !== "playing" || hand.webhook_status) return;
  const played = await replayHand(admin, hand, settingsOf(table));
  if (played.step.state.turn !== seat) return;
  if (automaticLastCard(played.step.state, seat, settingsOf(table)) !== card) return;
  const seats = await loadSeats(admin, tableId);
  const who = seats.find((item) => item.seat_index === seat);
  if (!who) return;
  await act(admin, tableId, who.user_id, "play", [card], undefined, true);
}

/** About a second after the turn starts, play a lone legal card. One completion, one score. */
async function maybeAutoLastCard(admin: SupabaseClient, tableId: string): Promise<void> {
  const table = await loadTable(admin, tableId);
  if (!rulesV13(table) || undoOf(table) || held(table)) return;
  const hand = await latestHand(admin, tableId);
  if (!hand || hand.status !== "playing" || hand.webhook_status) return;
  const played = await replayHand(admin, hand, settingsOf(table));
  const card = automaticLastCard(played.step.state, played.step.state.turn, settingsOf(table));
  if (!card) return;
  await setHold(admin, table, { handId: hand.id, at: new Date().toISOString() });
  try {
    await playHeldLastCard(admin, tableId, played.step.state.turn, card);
  } catch (error) {
    console.error(error);
  } finally {
    const fresh = await loadTable(admin, tableId);
    if (fresh.settings?.hold) await setHold(admin, fresh, null);
  }
}

async function resumeAutomaticLastCard(admin: SupabaseClient, tableId: string): Promise<void> {
  const table = await loadTable(admin, tableId);
  if (!rulesV13(table) || undoOf(table) || held(table)) return;
  const hand = await latestHand(admin, tableId);
  if (!hand || hand.status !== "playing" || hand.webhook_status) return;
  const started = Date.parse(String(hand.turn_started_at ?? ""));
  if (!Number.isFinite(started) || Date.now() - started < 1000) return;
  const played = await replayHand(admin, hand, settingsOf(table));
  const card = automaticLastCard(played.step.state, played.step.state.turn, settingsOf(table));
  if (!card) return;
  const seats = await loadSeats(admin, tableId);
  const who = seats.find((item) => item.seat_index === played.step.state.turn);
  if (!who) return;
  try {
    await act(admin, tableId, who.user_id, "play", [card], undefined, true);
  } catch (error) {
    console.error(error);
  }
}

/** Pass the current seat after the wait, then follow the chain. The phone does not choose this. */
async function autoPassCurrent(admin: SupabaseClient, tableId: string, wait: boolean, depth: number): Promise<void> {
  if (wait) await new Promise((resolve) => setTimeout(resolve, AUTO_PASS_WAIT_MS));
  const table = await loadTable(admin, tableId);
  const seats = await loadSeats(admin, tableId);
  if (!passesAutomatically(table, seats) || undoOf(table)) return;
  const hand = await latestHand(admin, tableId);
  if (!hand || hand.status !== "playing" || hand.webhook_status) return;
  const played = await replayHand(admin, hand, settingsOf(table));
  const state = played.step.state;
  const who = seats.find((item) => item.seat_index === state.turn);
  const block = autoPassBlock(state, state.turn, settingsOf(table));
  if (block || !who) {
    await traceMove(
      admin,
      table,
      hand,
      who ? String(who.display_name) : `Seat ${state.turn + 1}`,
      "auto-pass",
      state.trickCards.join(" "),
      `skipped: ${block ?? "empty seat"}`,
    );
    return;
  }
  await act(
    admin,
    tableId,
    who.user_id,
    "pass",
    [],
    who.is_bot ? who.seat_index : undefined,
    false,
    true,
    depth,
  );
}

async function maybeAutoPass(admin: SupabaseClient, tableId: string): Promise<void> {
  const table = await loadTable(admin, tableId);
  const seats = await loadSeats(admin, tableId);
  if (!passesAutomatically(table, seats) || undoOf(table) || held(table)) return;
  const hand = await latestHand(admin, tableId);
  if (!hand || hand.status !== "playing" || hand.webhook_status) return;
  const played = await replayHand(admin, hand, settingsOf(table));
  if (serverAutomatic(played.step.state, settingsOf(table))?.kind !== "pass") return;
  await setHold(admin, table, { handId: hand.id, at: new Date().toISOString() });
  try {
    await autoPassCurrent(admin, tableId, true, 1);
  } catch (error) {
    console.error(error);
  } finally {
    const fresh = await loadTable(admin, tableId);
    if (fresh.settings?.hold) await setHold(admin, fresh, null);
  }
}

async function resumeAutoPass(admin: SupabaseClient, tableId: string): Promise<void> {
  const table = await loadTable(admin, tableId);
  const seats = await loadSeats(admin, tableId);
  if (!passesAutomatically(table, seats) || undoOf(table)) return;
  if (held(table)) {
    const at = Date.parse(String(table.settings?.hold?.at ?? ""));
    if (!Number.isFinite(at) || Date.now() - at < AUTO_PASS_WAIT_MS) return;
  }
  const hand = await latestHand(admin, tableId);
  if (!hand || hand.status !== "playing" || hand.webhook_status) return;
  const started = Date.parse(String(hand.turn_started_at ?? ""));
  if (!Number.isFinite(started) || Date.now() - started < AUTO_PASS_WAIT_MS) return;
  const played = await replayHand(admin, hand, settingsOf(table));
  if (serverAutomatic(played.step.state, settingsOf(table))?.kind !== "pass") return;
  await setHold(admin, table, { handId: hand.id, at: new Date().toISOString() });
  try {
    await autoPassCurrent(admin, tableId, false, 1);
  } catch (error) {
    console.error(error);
  } finally {
    const fresh = await loadTable(admin, tableId);
    if (fresh.settings?.hold) await setHold(admin, fresh, null);
  }
}

function stuckBotTurn(state: HandState, settings: Settings, seats: Row[]): boolean {
  const seat = seats.find((item) => item.seat_index === state.turn);
  if (!seat?.is_bot) return false;
  return stuckLeaderAction(state, settings, true)?.kind === "pass";
}

/** A computer player who can only lead 2s passes after one second. A person does not. */
async function passStuckBot(admin: SupabaseClient, tableId: string, wait: boolean, depth: number): Promise<void> {
  if (wait) await new Promise((resolve) => setTimeout(resolve, AUTO_PASS_WAIT_MS));
  const table = await loadTable(admin, tableId);
  if (!rulesV14(table) || undoOf(table)) return;
  const hand = await latestHand(admin, tableId);
  if (!hand || hand.status !== "playing" || hand.webhook_status) return;
  const played = await replayHand(admin, hand, settingsOf(table));
  const state = played.step.state;
  const seats = await loadSeats(admin, tableId);
  if (!stuckBotTurn(state, settingsOf(table), seats)) return;
  const who = seats.find((item) => item.seat_index === state.turn);
  if (!who) return;
  await act(admin, tableId, who.user_id, "pass", [], who.seat_index, false, false, depth, true);
}

async function maybePassStuckBot(admin: SupabaseClient, tableId: string): Promise<void> {
  const table = await loadTable(admin, tableId);
  if (!rulesV14(table) || undoOf(table) || held(table)) return;
  const hand = await latestHand(admin, tableId);
  if (!hand || hand.status !== "playing" || hand.webhook_status) return;
  const played = await replayHand(admin, hand, settingsOf(table));
  const seats = await loadSeats(admin, tableId);
  if (!stuckBotTurn(played.step.state, settingsOf(table), seats)) return;
  await setHold(admin, table, { handId: hand.id, at: new Date().toISOString() });
  try {
    await passStuckBot(admin, tableId, true, 1);
  } catch (error) {
    console.error(error);
  } finally {
    const fresh = await loadTable(admin, tableId);
    if (fresh.settings?.hold) await setHold(admin, fresh, null);
  }
}

async function resumeStuckBot(admin: SupabaseClient, tableId: string): Promise<void> {
  const table = await loadTable(admin, tableId);
  if (!rulesV14(table) || undoOf(table) || held(table)) return;
  const hand = await latestHand(admin, tableId);
  if (!hand || hand.status !== "playing" || hand.webhook_status) return;
  const started = Date.parse(String(hand.turn_started_at ?? ""));
  if (!Number.isFinite(started) || Date.now() - started < AUTO_PASS_WAIT_MS) return;
  const played = await replayHand(admin, hand, settingsOf(table));
  const seats = await loadSeats(admin, tableId);
  if (!stuckBotTurn(played.step.state, settingsOf(table), seats)) return;
  await setHold(admin, table, { handId: hand.id, at: new Date().toISOString() });
  try {
    await passStuckBot(admin, tableId, false, 1);
  } catch (error) {
    console.error(error);
  } finally {
    const fresh = await loadTable(admin, tableId);
    if (fresh.settings?.hold) await setHold(admin, fresh, null);
  }
}

async function act(
  admin: SupabaseClient,
  tableId: string,
  userId: string,
  kind: "play" | "pass" | "timeout",
  cards: string[],
  botSeat?: number,
  autoLast = false,
  autoPass = false,
  depth = 0,
  allowHeld = false,
  expectSeat?: number,
): Promise<boolean> {
  let table = await loadTable(admin, tableId);
  await clearStaleHold(admin, table);
  await settleUndo(admin, table);
  table = await loadTable(admin, tableId);
  if (undoOf(table) || (!autoLast && !autoPass && !allowHeld && held(table))) throw new HttpError(400, "Wait for the undo vote");
  const seats = await loadSeats(admin, tableId);
  const settings = settingsOf(table);
  const seated = seats.find((item) => item.user_id === userId) ?? null;
  if (botSeat == null && !seated && kind !== "timeout") throw new HttpError(403, "You are not at this table");
  if (botSeat == null && !seated && kind === "timeout" && !(await viewerRow(admin, tableId, userId))) {
    throw new HttpError(403, "You are not at this table");
  }
  const me = botSeat == null
    ? (seated ?? { seat_index: -1, display_name: "", is_bot: false, user_id: userId })
    : seats.find((seat) => seat.seat_index === botSeat);
  if (!me) throw new HttpError(400, "That seat is empty");
  if (botSeat != null && !me.is_bot) throw new HttpError(400, "Only a computer player can be moved this way");
  for (let attempt = 0; attempt < 3; attempt++) {
    const hand = await latestHand(admin, tableId);
    if (!hand || hand.status !== "playing") throw new HttpError(400, "There is no hand to play");
    const played = await replayHand(admin, hand, settings);
    if (played.step.state.status !== "playing") throw new HttpError(400, "This hand is over");
    if (kind === "timeout") {
      const timed = expectSeat ?? played.step.state.turn;
      const block = timeoutBlock(played.step.state, timed);
      if (block) {
        await traceMove(admin, table, hand, playerName(seats, timed), "timeout", played.step.state.trickCards.join(" "), `skipped: ${block}`);
        return false;
      }
    }
    if (autoPass) {
      const block = autoPassBlock(played.step.state, me.seat_index, settings);
      if (block) {
        await traceMove(admin, table, hand, String(me.display_name ?? ""), "auto-pass", played.step.state.trickCards.join(" "), `skipped: ${block}`);
        return false;
      }
    }
    if (kind !== "timeout" && played.step.state.turn !== me.seat_index) throw new HttpError(400, "Not your turn");
    const step = kind === "play"
      ? applyPlay(played.step.state, me.seat_index, cards, settings)
      : kind === "pass"
      ? applyPass(played.step.state, me.seat_index, settings)
      : applyTimeout(played.step.state, settings);
    if (!step.ok) throw new HttpError(400, step.message);
    const seat = kind === "timeout" ? played.step.state.turn : me.seat_index;
    const { error } = await admin.from("events").insert({
      hand_id: hand.id,
      seq: played.eventCount + 1,
      seat_index: seat,
      kind,
      payload: { cards: kind === "play" ? step.state.trickCards : [] },
    });
    if (error) {
      if (String(error.code) === "23505" && (kind === "timeout" || autoPass)) {
        await traceMove(
          admin,
          table,
          hand,
          kind === "timeout" ? playerName(seats, expectSeat ?? played.step.state.turn) : String(me.display_name ?? ""),
          kind === "timeout" ? "timeout" : "auto-pass",
          played.step.state.trickCards.join(" "),
          "skipped: two moves clashed",
        );
        return false;
      }
      if (String(error.code) === "23505" && attempt < 2) continue;
      throw new HttpError(500, error.message);
    }
    const sweep = kind === "play"
      && rulesV13(table)
      && step.state.status === "playing"
      && isLoneTwoOfSpades(step.state.trickCards);
    const auto = !sweep && step.state.status === "playing" ? serverAutomatic(step.state, settings) : null;
    const nextCard = !autoLast && !sweep && rulesV13(table) && auto?.kind === "last-card" ? auto.card : null;
    const allowPass = passesAutomatically(table, seats);
    const nextPass = !sweep && nextCard == null && allowPass && auto?.kind === "pass" && depth < 3;
    const nextStuck = !sweep && nextCard == null && !nextPass && rulesV14(table) && depth < 4
      && stuckBotTurn(step.state, settings, seats);
    if (sweep || nextCard || nextPass || nextStuck) await setHold(admin, table, { handId: hand.id, at: new Date().toISOString() });
    let swept = false;
    try {
      const noPlay = allowPass && (autoPass || (kind === "pass" && shouldAutoPass(played.step.state, seat, settings)));
      const loneTwo = isLoneTwoOfSpades(played.step.state.trickCards);
      const shown = autoLast
        ? lastCardMessage(String(me.display_name ?? ""))
        : noPlay && !loneTwo
        ? NO_PLAY_MESSAGE
        : step.message;
      await saveProjection(admin, table, hand, seats, { ...step, message: shown }, played.deckText);
      if (autoPass) {
        await traceMove(admin, table, hand, String(me.display_name ?? ""), "auto-pass", played.step.state.trickCards.join(" "), "no legal play");
      }
      if (kind === "timeout") {
        await traceMove(admin, table, hand, playerName(seats, seat), "timeout", played.step.state.trickCards.join(" "), "turn timer");
      }
      if (sweep) {
        await new Promise((resolve) => setTimeout(resolve, 1000));
        await passTheRest(admin, tableId);
        const paused = await loadTable(admin, tableId);
        await patchSetting(admin, tableId, "botWaitUntil", new Date(Date.now() + 2200).toISOString(), null);
        if (paused.settings?.hold) await setHold(admin, paused, null);
        swept = true;
      }
    } finally {
      if (sweep) {
        const fresh = await loadTable(admin, tableId);
        if (fresh.settings?.hold) await setHold(admin, fresh, null);
      }
    }
    if (nextCard) {
      try {
        await playHeldLastCard(admin, tableId, step.state.turn, nextCard);
      } catch (error) {
        console.error(error);
      } finally {
        const fresh = await loadTable(admin, tableId);
        if (fresh.settings?.hold) await setHold(admin, fresh, null);
      }
    } else if (nextPass) {
      try {
        await autoPassCurrent(admin, tableId, true, depth + 1);
      } catch (error) {
        console.error(error);
      } finally {
        const fresh = await loadTable(admin, tableId);
        if (fresh.settings?.hold) await setHold(admin, fresh, null);
      }
    } else if (nextStuck) {
      try {
        await passStuckBot(admin, tableId, true, depth + 1);
      } catch (error) {
        console.error(error);
      } finally {
        const fresh = await loadTable(admin, tableId);
        if (fresh.settings?.hold) await setHold(admin, fresh, null);
      }
    } else if (swept) {
      await maybeAutoLastCard(admin, tableId);
      await maybeAutoPass(admin, tableId);
      await maybePassStuckBot(admin, tableId);
    }
    return swept;
  }
  throw new HttpError(409, "The table changed. Try that again.");
}

const BOT_NAMES = ["Bot Ruby", "Bot Jade", "Bot Pearl", "Bot Amber"];
const BOT_LOOP = 16;
const BOT_SLEEP_BUDGET = 8_000;

function botNames(seats: Row[]): string[] {
  return seats
    .filter((seat) => seat.is_bot)
    .sort((a, b) => a.seat_index - b.seat_index)
    .map((seat) => String(seat.display_name));
}

function nextBotName(seats: Row[]): string {
  const used = new Set(seats.map((seat) => seat.display_name));
  return BOT_NAMES.find((name) => !used.has(name)) ?? `Bot ${seats.length + 1}`;
}

function botWaiting(table: Row, now = Date.now()): boolean {
  const at = Date.parse(String(table.settings?.botWaitUntil ?? ""));
  return Number.isFinite(at) && now < at;
}

function thinkDelay(handId: string, seq: number): number {
  let hash = 2166136261;
  const text = `${handId}:${seq}`;
  for (let index = 0; index < text.length; index++) {
    hash ^= text.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return 800 + ((hash >>> 0) % 701);
}

async function cardsPlayed(admin: SupabaseClient, handId: string): Promise<Card[]> {
  const events = await must(
    admin.from("events").select("kind, payload").eq("hand_id", handId).order("seq"),
  );
  const ids: string[] = [];
  for (const event of events as Row[]) {
    if (event.kind === "play" && Array.isArray(event.payload?.cards)) {
      for (const card of event.payload.cards) ids.push(String(card));
    }
  }
  return parseCards(ids);
}

async function runBots(admin: SupabaseClient, tableId: string): Promise<void> {
  let slept = 0;
  try {
    const first = await loadTable(admin, tableId);
    if (botWaiting(first)) return;
    if (first.settings?.botWaitUntil) {
      await patchSetting(admin, tableId, "botWaitUntil", null, null);
    }
    for (let step = 0; step < BOT_LOOP; step++) {
      const table = await loadTable(admin, tableId);
      if (table.status !== "playing") return;
      const hand = await latestHand(admin, tableId);
      if (!hand || hand.status !== "playing") return;
      const seats = await loadSeats(admin, tableId);
      const settings = settingsOf(table);
      const played = await replayHand(admin, hand, settings);
      const state = played.step.state;
      if (state.status !== "playing") return;
      if (held(table) || undoOf(table)) return;
      if (rulesV13(table) && automaticLastCard(state, state.turn, settings)) return;
      if (passesAutomatically(table, seats) && serverAutomatic(state, settings)?.kind === "pass") return;
      const seat = seats.find((item) => item.seat_index === state.turn);
      if (!seat?.is_bot) return;
      if (rulesV14(table) && stuckLeaderAction(state, settings, true)?.kind === "pass") return;

      let liveHand = hand;
      let liveState = state;
      const delay = thinkDelay(liveHand.id, played.eventCount);
      const elapsed = Date.now() - new Date(liveHand.turn_started_at).getTime();
      const wait = Math.max(0, delay - elapsed);
      if (wait > 0 && slept + wait <= BOT_SLEEP_BUDGET) {
        await new Promise((resolve) => setTimeout(resolve, wait));
        slept += wait;
        const refreshed = await latestHand(admin, tableId);
        if (!refreshed || refreshed.status !== "playing") return;
        const again = await replayHand(admin, refreshed, settings);
        if (again.step.state.status !== "playing" || again.step.state.turn !== seat.seat_index) continue;
        liveHand = refreshed;
        liveState = again.step.state;
      }

      const difficulty = String(seat.bot_difficulty ?? "normal");
      const level: Difficulty = difficulty === "easy" || difficulty === "hard" ? difficulty : "normal";
      const move = chooseMove({
        seat: seat.seat_index,
        hand: liveState.hands[seat.seat_index],
        played: await cardsPlayed(admin, liveHand.id),
        counts: liveState.hands.map((cards) => cards.length),
        trick: liveState.trick,
        trickSeat: liveState.trickSeat,
        firstLead: liveState.firstLead,
        running: liveState.running,
        settings,
        difficulty: level,
        rng: () => {
          const buffer = new Uint32Array(1);
          crypto.getRandomValues(buffer);
          return buffer[0] / 4294967296;
        },
        locked: liveState.locked,
      });
      try {
        const swept = await act(
          admin,
          tableId,
          seat.user_id,
          move.kind,
          move.kind === "play" ? move.cards : [],
          seat.seat_index,
        );
        if (swept) return;
      } catch (error) {
        console.error(error);
        return;
      }
    }
  } catch (error) {
    console.error(error);
  }
}

function shuffledSeatOrder(seats: Row[]): (string | null)[] {
  const order: (string | null)[] = [null, null, null, null];
  for (const seat of seats) order[seat.seat_index] = seat.user_id;
  shuffleInPlace(order, cryptoUint32);
  return order;
}

function seatOrder(seats: Row[], requested: unknown): (string | null)[] {
  if (!Array.isArray(requested) || requested.length !== 4) throw new HttpError(400, "Give all four seats");
  const current = new Set(seats.map((seat) => seat.user_id));
  const seen = new Set<string>();
  const order: (string | null)[] = [];
  for (const item of requested) {
    if (item == null || item === "") {
      order.push(null);
      continue;
    }
    const id = String(item);
    if (!current.has(id) || seen.has(id)) throw new HttpError(400, "That seating does not match the players here");
    seen.add(id);
    order.push(id);
  }
  if (seen.size !== current.size) throw new HttpError(400, "That seating does not match the players here");
  return order;
}

async function writeSeatOrder(admin: SupabaseClient, tableId: string, order: (string | null)[]) {
  const { error } = await admin.rpc("reorder_seats", { p_table: tableId, p_order: order });
  if (!error) return;
  const message = String(error.message ?? "");
  const known = [
    "Seats can change only before a hand is dealt",
    "That seating does not match the players here",
    "Give all four seats",
  ].find((item) => message.includes(item));
  throw new HttpError(known ? 400 : 500, known ?? "Could not change the seating. Try again.");
}

export async function handleTable(req: Request): Promise<Response> {
  const userId = await requireUser(req);
  const body = await readBody(req);
  const admin = adminClient();
  const action = String(body.action ?? "state");

  if (action === "create") {
    const name = cleanName(body.name);
    const settings = storedSettings(body.settings);
    let table: Row | null = null;
    for (let attempt = 0; attempt < 5 && !table; attempt++) {
      const { data, error } = await admin
        .from("game_tables")
        .insert({
          code: roomCode(),
          host_id: userId,
          settings,
          season: settings.season,
          round_number: settings.firstRoundNumber,
        })
        .select("*")
        .single();
      if (!error) table = data;
      else if (String(error.code) !== "23505") throw new HttpError(500, error.message);
    }
    if (!table) throw new HttpError(500, "Could not make a room code");
    const { error } = await admin.from("seats").insert({
      table_id: table.id,
      seat_index: 0,
      user_id: userId,
      display_name: name,
    });
    if (error) throw new HttpError(500, error.message);
    return json({ view: await buildView(admin, table.id, userId) });
  }

  if (action === "join") {
    const name = cleanName(body.name);
    const code = String(body.code ?? "").trim().toUpperCase();
    if (!/^[A-Z0-9]{6}$/.test(code)) throw new HttpError(400, "Enter the 6-character code");
    const { data: table, error } = await admin.from("game_tables").select("*").eq("code", code).maybeSingle();
    if (error) throw new HttpError(500, error.message);
    if (!table) throw new HttpError(404, "No table uses that code");
    const seats = await loadSeats(admin, table.id);
    const mine = seats.find((seat) => seat.user_id === userId);
    if (mine && table.status === "lobby" && mine.display_name !== name) {
      const { error: renameError } = await admin
        .from("seats")
        .update({ display_name: name })
        .eq("table_id", table.id)
        .eq("user_id", userId);
      if (renameError) throw new HttpError(500, renameError.message);
    }
    if (!mine) {
      if (table.status !== "lobby") throw new HttpError(400, "That table has already started");
      if (seats.length >= 4) throw new HttpError(400, "That table is full");
      const taken = new Set(seats.map((seat) => seat.seat_index));
      const seatIndex = [0, 1, 2, 3].find((index) => !taken.has(index));
      const { error: insertError } = await admin.from("seats").insert({
        table_id: table.id,
        seat_index: seatIndex,
        user_id: userId,
        display_name: name,
      });
      if (insertError) throw new HttpError(400, "That seat was just taken. Try again.");
    }
    return json({ view: await buildView(admin, table.id, userId) });
  }

  if (action === "watch") {
    const name = cleanName(body.name);
    const code = String(body.code ?? "").trim().toUpperCase();
    if (!/^[A-Z0-9]{6}$/.test(code)) throw new HttpError(400, "Enter the 6-character code");
    const { data: table, error } = await admin.from("game_tables").select("*").eq("code", code).maybeSingle();
    if (error) throw new HttpError(500, error.message);
    if (!table) throw new HttpError(404, "No table uses that code");
    const seats = await loadSeats(admin, table.id);
    if (seats.some((seat) => seat.user_id === userId)) {
      const { error: dropError } = await admin.from("table_viewers").delete().eq("table_id", table.id).eq("user_id", userId);
      if (dropError) throw new HttpError(500, dropError.message);
      return json({ view: await buildView(admin, table.id, userId) });
    }
    if (seats.length < 4 && table.status === "lobby") throw new HttpError(400, "There is still a seat at that table");
    const existing = await viewerRow(admin, table.id, userId);
    if (!existing) {
      const { count, error: countError } = await admin
        .from("table_viewers")
        .select("user_id", { count: "exact", head: true })
        .eq("table_id", table.id);
      if (countError) throw new HttpError(500, countError.message);
      if ((count ?? 0) >= VIEWER_CAP) throw new HttpError(400, "Too many people are watching");
    }
    const { error: watchError } = await admin.from("table_viewers").upsert({
      table_id: table.id,
      user_id: userId,
      display_name: name,
      last_seen: new Date().toISOString(),
    }, { onConflict: "table_id,user_id" });
    if (watchError) throw new HttpError(500, watchError.message);
    return json({ view: await buildView(admin, table.id, userId) });
  }

  const tableId = String(body.tableId ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(tableId)) throw new HttpError(400, "Missing table");

  if (action === "state" || action === "heartbeat") {
    return json({ view: await buildView(admin, tableId, userId) });
  }

  if (action === "chat") {
    const table = await loadTable(admin, tableId);
    const seats = await loadSeats(admin, tableId);
    const seat = seats.find((item) => item.user_id === userId) ?? null;
    const viewer = seat ? null : await viewerRow(admin, tableId, userId);
    if (!seat && !viewer) throw new HttpError(403, "You are not at this table");
    if (table.status === "round_end") throw new HttpError(400, "This game is over");
    const text = chatText(body.text);
    if (!text.ok) throw new HttpError(400, text.message);
    if (viewer) await touchViewer(admin, tableId, userId);
    const { error } = await admin.from("table_messages").insert({
      table_id: tableId,
      round_number: table.round_number,
      display_name: String(seat?.display_name ?? viewer?.display_name ?? "Player"),
      viewer: !seat,
      body: text.text,
    });
    if (error) throw new HttpError(500, error.message);
    return json({ view: await buildView(admin, tableId, userId) });
  }

  if (action === "undo" || action === "undo_vote") {
    const table = await loadTable(admin, tableId);
    const seats = await loadSeats(admin, tableId);
    const me = requireSeat(seats, userId);
    if (!rulesV13(table)) throw new HttpError(400, "Undo is not used at this table");
    if (action === "undo") await openUndo(admin, table, seats, me);
    else await castUndoVote(admin, table, me, body.approve === true);
    return json({ view: await buildView(admin, tableId, userId) });
  }

  if (action === "settings") {
    const table = await loadTable(admin, tableId);
    if (table.host_id !== userId) throw new HttpError(403, "Only the host can change settings");
    if (table.status !== "lobby") throw new HttpError(400, "Settings can change before the first hand");
    const settings = storedSettings(body.settings, table);
    const existing = await latestHand(admin, tableId);
    if (existing) throw new HttpError(400, "Settings can change before the first hand");
    const { error } = await admin
      .from("game_tables")
      .update({
        settings,
        season: settings.season,
        ...(existing ? {} : { round_number: settings.firstRoundNumber }),
      })
      .eq("id", tableId);
    if (error) throw new HttpError(500, error.message);
    return json({ view: await buildView(admin, tableId, userId) });
  }

  if (action === "shuffle" || action === "order") {
    const table = await loadTable(admin, tableId);
    const seats = await loadSeats(admin, tableId);
    requireSeat(seats, userId);
    if (table.host_id !== userId) throw new HttpError(403, "Only the host can change the seating");
    if (table.status !== "lobby") throw new HttpError(400, "Seats can change only before a hand is dealt");
    const order = action === "shuffle" ? shuffledSeatOrder(seats) : seatOrder(seats, body.order);
    await writeSeatOrder(admin, table.id, order);
    return json({ view: await buildView(admin, tableId, userId) });
  }

  if (action === "add_bot") {
    const table = await loadTable(admin, tableId);
    const seats = await loadSeats(admin, tableId);
    requireSeat(seats, userId);
    if (table.host_id !== userId) throw new HttpError(403, "Only the host can add a computer player");
    if (table.status !== "lobby") throw new HttpError(400, "Computer players can be added before the deal");
    const seatIndex = Number(body.seat);
    if (!Number.isInteger(seatIndex) || seatIndex < 0 || seatIndex > 3) throw new HttpError(400, "Choose a seat");
    if (seats.some((seat) => seat.seat_index === seatIndex)) throw new HttpError(400, "That seat is taken");
    const difficulty = String(body.difficulty ?? "normal").toLowerCase();
    if (difficulty !== "easy" && difficulty !== "normal" && difficulty !== "hard") {
      throw new HttpError(400, "Choose Easy, Normal, or Hard");
    }
    const { error } = await admin.from("seats").insert({
      table_id: tableId,
      seat_index: seatIndex,
      user_id: crypto.randomUUID(),
      display_name: nextBotName(seats),
      is_bot: true,
      bot_difficulty: difficulty,
    });
    if (error) throw new HttpError(400, "That seat was just taken. Try again.");
    return json({ view: await buildView(admin, tableId, userId) });
  }

  if (action === "remove_bot") {
    const table = await loadTable(admin, tableId);
    const seats = await loadSeats(admin, tableId);
    requireSeat(seats, userId);
    if (table.host_id !== userId) throw new HttpError(403, "Only the host can remove a computer player");
    if (table.status !== "lobby") throw new HttpError(400, "Computer players can be removed before the deal");
    const seatIndex = Number(body.seat);
    if (!Number.isInteger(seatIndex) || seatIndex < 0 || seatIndex > 3) throw new HttpError(400, "Choose a seat");
    const seat = seats.find((item) => item.seat_index === seatIndex);
    if (!seat) throw new HttpError(400, "That seat is empty");
    if (!seat.is_bot) throw new HttpError(400, "Only a computer player can be removed this way");
    const { error } = await admin.from("seats").delete().eq("table_id", tableId).eq("seat_index", seatIndex).eq("is_bot", true);
    if (error) throw new HttpError(500, error.message);
    return json({ view: await buildView(admin, tableId, userId) });
  }

  if (action === "rename") {
    const table = await loadTable(admin, tableId);
    const seats = await loadSeats(admin, tableId);
    requireSeat(seats, userId);
    if (table.host_id !== userId) throw new HttpError(403, "Only the host can change names");
    if (table.status !== "lobby") throw new HttpError(400, "Names can change before the next hand");
    const seatIndex = Number(body.seat);
    if (!Number.isInteger(seatIndex) || seatIndex < 0 || seatIndex > 3) throw new HttpError(400, "Choose a seat");
    const name = cleanName(body.name);
    const { data, error } = await admin
      .from("seats")
      .update({ display_name: name })
      .eq("table_id", tableId)
      .eq("seat_index", seatIndex)
      .select("user_id");
    if (error) throw new HttpError(500, error.message);
    if (!data || data.length === 0) throw new HttpError(400, "That seat is empty");
    return json({ view: await buildView(admin, tableId, userId) });
  }

  if (action === "new_round") {
    const table = await loadTable(admin, tableId);
    const seats = await loadSeats(admin, tableId);
    requireSeat(seats, userId);
    if (table.status !== "round_end") throw new HttpError(400, "This round is still going");
    const nextRound = table.round_number + 1;
    const { data, error } = await admin
      .from("game_tables")
      .update({ status: "lobby", round_number: nextRound })
      .eq("id", tableId)
      .eq("status", "round_end")
      .select("id");
    if (error) throw new HttpError(500, error.message);
    if (!data || data.length === 0) throw new HttpError(409, "The table changed. Try that again.");
    await clearChat(admin, tableId);
    return json({ view: await buildView(admin, tableId, userId) });
  }

  throw new HttpError(400, "Unknown action");
}

export async function handleDeal(req: Request): Promise<Response> {
  const userId = await requireUser(req);
  const body = await readBody(req);
  const tableId = String(body.tableId ?? "");
  const admin = adminClient();
  const table = await loadTable(admin, tableId);
  const seats = await loadSeats(admin, tableId);
  await dealHand(admin, table, seats, userId);
  await runBots(admin, tableId);
  return json({ view: await buildView(admin, tableId, userId) });
}

export async function handlePlay(req: Request): Promise<Response> {
  const userId = await requireUser(req);
  const body = await readBody(req);
  const cards = Array.isArray(body.cards) ? body.cards.map((card) => String(card)) : [];
  const admin = adminClient();
  const tableId = String(body.tableId ?? "");
  await act(admin, tableId, userId, "play", cards);
  await runBots(admin, tableId);
  return json({ view: await buildView(admin, tableId, userId) });
}

export async function handlePass(req: Request): Promise<Response> {
  const userId = await requireUser(req);
  const body = await readBody(req);
  const admin = adminClient();
  const tableId = String(body.tableId ?? "");
  await act(admin, tableId, userId, "pass", []);
  await runBots(admin, tableId);
  return json({ view: await buildView(admin, tableId, userId) });
}

export async function handleTick(req: Request): Promise<Response> {
  const userId = await requireUser(req);
  const body = await readBody(req);
  const tableId = String(body.tableId ?? "");
  const admin = adminClient();
  const table = await loadTable(admin, tableId);
  await clearStaleHold(admin, table);
  await settleUndo(admin, table);
  const live = await loadTable(admin, tableId);
  let hand = await latestHand(admin, tableId);
  const settings = settingsOf(live);
  if (undoOf(live)) {
    if (hand && (hand.webhook_status === "pending" || hand.webhook_status === "failed" || hand.webhook_status === "sending")) {
      await sendWebhook(admin, hand.id);
    }
    return json({ view: await buildView(admin, tableId, userId) });
  }
  if (held(live)) {
    const at = Date.parse(String(live.settings?.hold?.at ?? ""));
    if (!Number.isFinite(at) || Date.now() - at < AUTO_PASS_WAIT_MS) {
      if (hand && (hand.webhook_status === "pending" || hand.webhook_status === "failed" || hand.webhook_status === "sending")) {
        await sendWebhook(admin, hand.id);
      }
      return json({ view: await buildView(admin, tableId, userId) });
    }
  }
  await resumeAutomaticLastCard(admin, tableId);
  await resumeAutoPass(admin, tableId);
  await resumeStuckBot(admin, tableId);
  hand = await latestHand(admin, tableId);
  if (hand?.status === "playing") {
    const played = await replayHand(admin, hand, settings);
    if (played.step.state.status === "complete") {
      const seats = await loadSeats(admin, tableId);
      await saveProjection(admin, table, hand, seats, played.step, played.deckText);
      hand = await latestHand(admin, tableId);
    }
  }
  if (hand?.status === "playing" && settings.turnTimerSeconds > 0) {
    const elapsed = Date.now() - new Date(hand.turn_started_at).getTime();
    if (elapsed >= settings.turnTimerSeconds * 1000) {
      const played = await replayHand(admin, hand, settings);
      const timedSeat = played.step.state.status === "playing" ? played.step.state.turn : null;
      if (timedSeat != null && timeoutBlock(played.step.state, timedSeat) === null) {
        await act(admin, tableId, userId, "timeout", [], undefined, false, false, 0, false, timedSeat);
      }
      hand = await latestHand(admin, tableId);
    }
  }
  if (hand?.status === "playing") await runBots(admin, tableId);
  hand = await latestHand(admin, tableId);
  if (hand && (hand.webhook_status === "pending" || hand.webhook_status === "failed" || hand.webhook_status === "sending")) {
    await sendWebhook(admin, hand.id);
  }
  return json({ view: await buildView(admin, tableId, userId) });
}

export async function handlePing(): Promise<Response> {
  const admin = adminClient();
  const { error } = await admin.from("keep_alive").upsert({ id: 1, pinged_at: new Date().toISOString() });
  if (error) throw new HttpError(500, error.message);
  return json({ ok: true, at: new Date().toISOString() });
}
