import { type Card, formatCard, parseCards, removeCards } from "./cards.ts";
import { beats, type Combo, family, identify, neededShape } from "./combo.ts";
import { type Bonus, type HandScore, scoreCounts } from "./score.ts";

export interface Settings {
  passLocks: boolean;
  straightsWrap: boolean;
  /** 0 means the turn timer is off. */
  turnTimerSeconds: number;
  season: number;
  timezone: string;
  /** Number used for the first round at this table. Later rounds add 1. */
  firstRoundNumber: number;
}

export const DEFAULT_SETTINGS: Settings = {
  passLocks: false,
  straightsWrap: false,
  turnTimerSeconds: 0,
  season: 24,
  timezone: "Australia/Melbourne",
  firstRoundNumber: 1,
};

export interface HandState {
  hands: Card[][];
  turn: number;
  trick: Combo | null;
  trickSeat: number | null;
  trickCards: string[];
  consecutivePasses: number;
  locked: number[];
  /** Opening lead of the first hand of the round must include the 3 of diamonds. */
  firstLead: boolean;
  /** Round totals so far, including bonuses played during this hand. */
  running: number[];
  runningAtStart: number[];
  bonuses: Bonus[];
  status: "playing" | "complete";
  winner: number | null;
  leadSkips: number;
  closedReason: "winner" | "stuck" | null;
}

export interface HandResult extends HandScore {
  winner: number | null;
  closedReason: "winner" | "stuck" | null;
  bonuses: Bonus[];
}

export interface StepOk {
  ok: true;
  state: HandState;
  result: HandResult | null;
  message: string;
}

export interface StepBad {
  ok: false;
  reason: string;
  message: string;
}

export type Step = StepOk | StepBad;

export function cloneState(state: HandState): HandState {
  return {
    hands: state.hands.map((hand) => hand.map((card) => ({ ...card }))),
    turn: state.turn,
    trick: state.trick,
    trickSeat: state.trickSeat,
    trickCards: [...state.trickCards],
    consecutivePasses: state.consecutivePasses,
    locked: [...state.locked],
    firstLead: state.firstLead,
    running: [...state.running],
    runningAtStart: [...state.runningAtStart],
    bonuses: state.bonuses.map((bonus) => ({ ...bonus })),
    status: state.status,
    winner: state.winner,
    leadSkips: state.leadSkips,
    closedReason: state.closedReason,
  };
}

export function dealHands(deck: readonly Card[]): Card[][] {
  if (deck.length !== 52) throw new Error("A deck has 52 cards");
  const seen = new Set(deck.map(formatCard));
  if (seen.size !== 52) throw new Error("The deck has a duplicate card");
  return [0, 1, 2, 3].map((seat) => deck.slice(seat * 13, seat * 13 + 13).map((card) => ({ ...card })));
}

export function seatHolding(hands: readonly (readonly Card[])[], cardId: string): number {
  for (let seat = 0; seat < hands.length; seat++) {
    if (hands[seat].some((card) => formatCard(card) === cardId)) return seat;
  }
  return -1;
}

export function startHand(
  deck: readonly Card[],
  running: readonly number[],
  firstHand: boolean,
  previousWinner: number | null,
): HandState {
  const hands = dealHands(deck);
  const leader = firstHand || previousWinner === null ? seatHolding(hands, "3D") : previousWinner;
  if (leader < 0) throw new Error("The 3 of diamonds is missing");
  return {
    hands,
    turn: leader,
    trick: null,
    trickSeat: null,
    trickCards: [],
    consecutivePasses: 0,
    locked: [],
    firstLead: firstHand,
    running: [...running],
    runningAtStart: [...running],
    bonuses: [],
    status: "playing",
    winner: null,
    leadSkips: 0,
    closedReason: null,
  };
}

/** Build a hand already in progress. Used by tests and by replay. */
export function makeState(args: {
  hands: Card[][];
  turn: number;
  running?: number[];
  firstLead?: boolean;
  trick?: Combo | null;
  trickSeat?: number | null;
  trickCards?: string[];
  consecutivePasses?: number;
  locked?: number[];
}): HandState {
  const running = args.running ?? [0, 0, 0, 0];
  return {
    hands: args.hands,
    turn: args.turn,
    trick: args.trick ?? null,
    trickSeat: args.trickSeat ?? null,
    trickCards: args.trickCards ?? [],
    consecutivePasses: args.consecutivePasses ?? 0,
    locked: args.locked ?? [],
    firstLead: args.firstLead ?? false,
    running: [...running],
    runningAtStart: [...running],
    bonuses: [],
    status: "playing",
    winner: null,
    leadSkips: 0,
    closedReason: null,
  };
}

function nextSeat(seat: number): number {
  return (seat + 1) % 4;
}

function fail(reason: string, message: string): StepBad {
  return { ok: false, reason, message };
}

export function resultOf(state: HandState): HandResult | null {
  if (state.status !== "complete") return null;
  const score = scoreCounts(
    state.hands.map((hand) => hand.length),
    state.running,
    state.bonuses,
  );
  return { ...score, winner: state.winner, closedReason: state.closedReason, bonuses: state.bonuses };
}

function subsets(hand: readonly Card[]): Card[][] {
  const found: Card[][] = [];
  const count = hand.length;
  for (let mask = 1; mask < (1 << count); mask++) {
    const size = bitCount(mask);
    if (size !== 1 && size !== 2 && size !== 3 && size !== 5) continue;
    const pick: Card[] = [];
    for (let index = 0; index < count; index++) {
      if (mask & (1 << index)) pick.push(hand[index]);
    }
    found.push(pick);
  }
  return found;
}

function bitCount(mask: number): number {
  let count = 0;
  let value = mask;
  while (value) {
    count += value & 1;
    value >>= 1;
  }
  return count;
}

export function playIssue(
  state: HandState,
  seat: number,
  cards: readonly Card[],
  settings: Settings,
): string | null {
  if (state.status !== "playing") return "This hand is over";
  if (seat !== state.turn) return "Not your turn";
  if (state.locked.includes(seat)) return "You passed this trick";
  if (cards.length === 0) return "Select cards to play";
  const combo = identify(cards, settings.straightsWrap);
  if (!combo) return "Not a valid combination";
  if (removeCards(state.hands[seat], cards) === null) return "Those cards are not in your hand";
  if (state.firstLead && state.trick === null && !cards.some((card) => formatCard(card) === "3D")) {
    return "First play must include the 3♦";
  }
  if (state.trick && family(combo.kind) !== family(state.trick.kind)) {
    return `You need ${neededShape(state.trick.kind)}`;
  }
  if (state.trick && !beats(combo, state.trick)) return "Doesn't beat the current play";
  const empties = cards.length === state.hands[seat].length;
  if (empties && cards.every((card) => card.r === 15)) return "You can't go out if you only have 2s";
  return null;
}

export function legalSelections(state: HandState, seat: number, settings: Settings): Card[][] {
  if (state.status !== "playing" || seat !== state.turn || state.locked.includes(seat)) return [];
  return subsets(state.hands[seat]).filter((cards) => playIssue(state, seat, cards, settings) === null);
}

function withBonus(state: HandState, seat: number, combo: Combo): HandState {
  if (!combo.bonusName || combo.bonusEach === 0) return state;
  const bonus: Bonus = {
    seat,
    kind: combo.kind as Bonus["kind"],
    combo: combo.bonusName,
    pointsEach: combo.bonusEach,
  };
  const running = state.running.map((total, index) => (index === seat ? total : total + combo.bonusEach));
  return { ...state, running, bonuses: [...state.bonuses, bonus] };
}

function complete(state: HandState, winner: number | null, reason: "winner" | "stuck"): HandState {
  return { ...state, status: "complete", winner, closedReason: reason };
}

export function applyPlay(state: HandState, seat: number, cardIds: readonly string[], settings: Settings): Step {
  let cards: Card[];
  try {
    cards = parseCards(cardIds);
  } catch {
    return fail("bad_card", "Those cards are not in the deck");
  }
  const issue = playIssue(state, seat, cards, settings);
  if (issue) return fail("illegal", issue);
  const combo = identify(cards, settings.straightsWrap);
  if (!combo) return fail("illegal", "Not a valid combination");
  const left = removeCards(state.hands[seat], cards);
  if (!left) return fail("illegal", "Those cards are not in your hand");

  const hands = state.hands.map((hand, index) => (index === seat ? left : hand.map((card) => ({ ...card }))));
  let next: HandState = withBonus(
    {
      ...cloneState(state),
      hands,
      trick: combo,
      trickSeat: seat,
      trickCards: cards.map(formatCard),
      consecutivePasses: 0,
      firstLead: false,
      leadSkips: 0,
    },
    seat,
    combo,
  );

  if (left.length === 0) {
    next = complete(next, seat, "winner");
    return { ok: true, state: next, result: resultOf(next), message: `${combo.label} wins the hand` };
  }

  next = { ...next, turn: nextSeat(seat) };
  return { ok: true, state: next, result: null, message: combo.label };
}

export function applyPass(state: HandState, seat: number, settings: Settings): Step {
  if (state.status !== "playing") return fail("over", "This hand is over");
  if (seat !== state.turn) return fail("turn", "Not your turn");

  if (state.trick === null) {
    if (legalSelections(state, seat, settings).length > 0) {
      return fail("must_lead", "You must lead — passing isn't allowed");
    }
    const skips = state.leadSkips + 1;
    if (skips >= 4) {
      const done = complete({ ...cloneState(state), leadSkips: skips }, null, "stuck");
      return {
        ok: true,
        state: done,
        result: resultOf(done),
        message: "Nobody can lead. The hand is scored as it stands.",
      };
    }
    const skipped: HandState = { ...cloneState(state), turn: nextSeat(seat), leadSkips: skips };
    return { ok: true, state: skipped, result: null, message: "You can't go out if you only have 2s. The lead passes on." };
  }

  const locked = settings.passLocks && !state.locked.includes(seat) ? [...state.locked, seat] : [...state.locked];
  const passes = state.consecutivePasses + 1;
  if (passes >= 3 && state.trickSeat !== null) {
    const leader = state.trickSeat;
    const cleared: HandState = {
      ...cloneState(state),
      turn: leader,
      trick: null,
      trickSeat: null,
      trickCards: [],
      consecutivePasses: 0,
      locked: [],
      leadSkips: 0,
    };
    return { ok: true, state: cleared, result: null, message: "The trick is won. Lead anything." };
  }

  const passed: HandState = {
    ...cloneState(state),
    turn: nextSeat(seat),
    consecutivePasses: passes,
    locked,
  };
  return { ok: true, state: passed, result: null, message: "Pass" };
}

export function lowestLegalPlay(state: HandState, seat: number, settings: Settings): string[] | null {
  const options = legalSelections(state, seat, settings);
  if (options.length === 0) return null;
  const singles = options.filter((cards) => cards.length === 1);
  const pool = state.trick === null && singles.length > 0 ? singles : options;
  let best = pool[0];
  let bestCombo = identify(best, settings.straightsWrap);
  for (const cards of pool.slice(1)) {
    const combo = identify(cards, settings.straightsWrap);
    if (combo && bestCombo && beats(bestCombo, combo)) {
      best = cards;
      bestCombo = combo;
    }
  }
  return best.map(formatCard);
}

/** Disconnected-player timer. Followers pass. A leader plays their lowest single. */
export function applyTimeout(state: HandState, settings: Settings): Step {
  const seat = state.turn;
  if (state.trick === null) {
    const cards = lowestLegalPlay(state, seat, settings);
    if (!cards) return applyPass(state, seat, settings);
    return applyPlay(state, seat, cards, settings);
  }
  return applyPass(state, seat, settings);
}

export function roundWinners(totals: readonly number[]): number[] {
  const best = Math.min(...totals);
  return totals.map((total, seat) => (total === best ? seat : -1)).filter((seat) => seat >= 0);
}

export interface ReplayEvent {
  kind: "play" | "pass" | "timeout";
  seat: number;
  cards?: string[];
}

export function replay(
  deck: readonly Card[],
  running: readonly number[],
  firstHand: boolean,
  previousWinner: number | null,
  events: readonly ReplayEvent[],
  settings: Settings,
): Step {
  let step: Step = {
    ok: true,
    state: startHand(deck, running, firstHand, previousWinner),
    result: null,
    message: "Deal",
  };
  for (const event of events) {
    if (!step.ok) return step;
    if (step.state.status === "complete") return fail("over", "This hand is over");
    if (event.seat !== step.state.turn) return fail("turn", "Not your turn");
    if (event.kind === "play") step = applyPlay(step.state, event.seat, event.cards ?? [], settings);
    else if (event.kind === "timeout") step = applyTimeout(step.state, settings);
    else step = applyPass(step.state, event.seat, settings);
  }
  return step;
}
