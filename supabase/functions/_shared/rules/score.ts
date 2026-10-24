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
}): WebhookPayload {
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
  };
}
