export interface Bonus {
  seat: number;
  kind: "four" | "straight_flush" | "royal_flush";
  combo: string;
  pointsEach: number;
}

/** Points for a count of cards left. 9 stays 9. 10, 11 and 12 double. 13 is 36. */
export function cardPoints(cardsLeft: number): number {
  if (cardsLeft <= 0) return 0;
  if (cardsLeft === 13) return 36;
  if (cardsLeft >= 10 && cardsLeft <= 12) return cardsLeft * 2;
  return cardsLeft;
}

export interface HandScore {
  cardsLeft: number[];
  cardPoints: number[];
  bonusReceived: number[];
  handPoints: number[];
  runningTotals: number[];
  roundOver: boolean;
}

/**
 * `running` already includes bonuses paid during the hand.
 * `runningAtStart` is the total before this hand, bonuses included from earlier hands only.
 */
export function scoreCounts(
  cardsLeft: readonly number[],
  running: readonly number[],
  bonuses: readonly Bonus[],
): HandScore {
  const points = cardsLeft.map(cardPoints);
  const bonusReceived = [0, 0, 0, 0];
  for (const bonus of bonuses) {
    for (let seat = 0; seat < 4; seat++) {
      if (seat !== bonus.seat) bonusReceived[seat] += bonus.pointsEach;
    }
  }
  const handPoints = points.map((value, seat) => value + bonusReceived[seat]);
  const runningTotals = running.map((value, seat) => value + points[seat]);
  return {
    cardsLeft: [...cardsLeft],
    cardPoints: points,
    bonusReceived,
    handPoints,
    runningTotals,
    roundOver: runningTotals.some((total) => total >= 50),
  };
}

export function formatDate(now: Date, timeZone: string): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(now);
  const pick = (type: string) => parts.find((part) => part.type === type)?.value ?? "";
  return `${pick("year")}-${pick("month")}-${pick("day")}`;
}

export interface WebhookBonus {
  player: string;
  combo: string;
  pointsEach: number;
}

export interface WebhookPayload {
  handId: string;
  tableCode: string;
  season: number;
  round: number;
  hand: number;
  date: string;
  players: string[];
  cardsLeft: number[];
  handPoints: number[];
  bonuses: WebhookBonus[];
  runningTotals: number[];
  roundOver: boolean;
  roundWinner: string | null;
  /** True when this hand was played with at least one computer player. */
  hasBots: boolean;
  /** Display names of the computer players, without an emoji. */
  bots: string[];
  /**
   * One entry per seat, in seat order. A stand-in played that hand when
   * `played` is true. `who` is a watcher name, "computer", or both.
   * The player names above stay the original names.
   */
  standIns: { played: boolean; who: string | null }[];
}

/** Lowest total, in seat order. A tie lists every name. Null until the round is over. */
export function roundWinnerName(players: readonly string[], totals: readonly number[], roundOver: boolean): string | null {
  if (!roundOver || totals.length === 0) return null;
  const best = Math.min(...totals);
  return totals
    .flatMap((total, seat) => (total === best ? [players[seat] ?? `Seat ${seat + 1}`] : []))
    .join(", ");
}

export function webhookPayload(args: {
  handId: string;
  tableCode: string;
  season: number;
  round: number;
  hand: number;
  date: string;
  players: string[];
  cardsLeft: number[];
  handPoints: number[];
  runningTotals: number[];
  roundOver: boolean;
  bonuses: readonly Bonus[];
  hasBots?: boolean;
  bots?: readonly string[];
  standIns?: readonly { played: boolean; who: string | null }[];
}): WebhookPayload {
  const standIns = args.standIns ?? [
    { played: false, who: null },
    { played: false, who: null },
    { played: false, who: null },
    { played: false, who: null },
  ];
  return {
    handId: args.handId,
    tableCode: args.tableCode,
    season: args.season,
    round: args.round,
    hand: args.hand,
    date: args.date,
    players: [...args.players],
    cardsLeft: [...args.cardsLeft],
    handPoints: [...args.handPoints],
    bonuses: args.bonuses.map((bonus) => ({
      player: args.players[bonus.seat] ?? `Seat ${bonus.seat + 1}`,
      combo: bonus.combo,
      pointsEach: bonus.pointsEach,
    })),
    runningTotals: [...args.runningTotals],
    roundOver: args.roundOver,
    roundWinner: roundWinnerName(args.players, args.runningTotals, args.roundOver),
    hasBots: args.hasBots ?? false,
    bots: [...(args.bots ?? [])],
    standIns: standIns.map((item) => ({ played: item.played === true, who: item.who ?? null })),
  };
}

/** A game (one round) is posted only after some running total reaches 50. */
export function shouldPostGameScores(roundOver: boolean): boolean {
  return roundOver === true;
}

/**
 * A body already saved on a hand. A game batch is sent. An older per-hand body
 * is sent only when that hand ended the round. Anything else is dropped, so an
 * unfinished game does not go out.
 */
export function storedScoreDelivery(body: unknown, roundOver: boolean): "send" | "drop" {
  if (body == null || typeof body !== "object" || Array.isArray(body)) return "drop";
  if ((body as { type?: unknown }).type === "game") return "send";
  return roundOver ? "send" : "drop";
}

/**
 * Stable id for one game at a table. The same table, season, and round always
 * produce the same id, so a retry is a duplicate the receiver can skip.
 */
export function gameIdFor(tableId: string, season: number, round: number): string {
  return `${tableId}:${season}:${round}`;
}

export const GAME_PAYLOAD_VERSION = 1;

export interface GameWebhookPayload {
  type: "game";
  version: number;
  gameId: string;
  tableCode: string;
  season: number;
  round: number;
  date: string;
  players: string[];
  finalTotals: number[];
  winner: string | null;
  hands: WebhookPayload[];
}

/**
 * One POST for a finished game. Each entry in `hands` uses the same field
 * names as the old per-hand body. `winner` is the lowest final total.
 */
export function gameWebhookPayload(args: {
  gameId: string;
  tableCode: string;
  season: number;
  round: number;
  date: string;
  players: readonly string[];
  finalTotals: readonly number[];
  hands: readonly WebhookPayload[];
}): GameWebhookPayload {
  const hands = [...args.hands].sort((a, b) => a.hand - b.hand || a.handId.localeCompare(b.handId));
  const last = hands[hands.length - 1];
  const players = last ? [...last.players] : [...args.players];
  const finalTotals = last ? [...last.runningTotals] : [...args.finalTotals];
  const finished = hands.some((hand) => hand.roundOver);
  return {
    type: "game",
    version: GAME_PAYLOAD_VERSION,
    gameId: args.gameId,
    tableCode: args.tableCode,
    season: args.season,
    round: args.round,
    date: last?.date ?? args.date,
    players,
    finalTotals,
    winner: roundWinnerName(players, finalTotals, finished),
    hands,
  };
}

/** Rebuild one hand of a game from the row already saved for the score sheet. */
export function storedHandPayload(args: {
  handId: string;
  tableCode: string;
  season: number;
  round: number;
  hand: number;
  date: string;
  players: readonly string[];
  cardsLeft: readonly number[];
  handPoints: readonly number[];
  runningTotals: readonly number[];
  roundOver: boolean;
  bonuses?: readonly { player?: unknown; combo?: unknown; pointsEach?: unknown }[];
  hasBots?: boolean;
  bots?: readonly string[];
  standIns?: readonly { played?: unknown; who?: unknown }[] | null;
}): WebhookPayload {
  const players = args.players.map((name) => String(name));
  const standIns = args.standIns?.map((item) => ({
    played: item.played === true,
    who: item.who == null || item.who === "" ? null : String(item.who),
  }));
  const body = webhookPayload({
    handId: args.handId,
    tableCode: args.tableCode,
    season: args.season,
    round: args.round,
    hand: args.hand,
    date: args.date,
    players,
    cardsLeft: [...args.cardsLeft],
    handPoints: [...args.handPoints],
    runningTotals: [...args.runningTotals],
    roundOver: args.roundOver,
    bonuses: [],
    hasBots: args.hasBots ?? false,
    bots: args.bots ?? [],
    standIns,
  });
  return {
    ...body,
    bonuses: (args.bonuses ?? []).map((bonus) => ({
      player: String(bonus.player ?? ""),
      combo: String(bonus.combo ?? ""),
      pointsEach: Number(bonus.pointsEach ?? 0),
    })),
  };
}
