import { type Card, formatCard, fullDeck, SUITS } from "../rules/cards.ts";
import { beats, type Combo, compareKey, family, identify } from "../rules/combo.ts";
import { makeState, playIssue, type Settings } from "../rules/game.ts";

/**
 * Computer-player choice. Callers pass one seat's own cards, the cards already
 * played, and the other seats' counts. This module never sees another hand or
 * the unrevealed deck.
 */
export type Difficulty = "easy" | "normal" | "hard";

export type BotMove = { kind: "play"; cards: string[] } | { kind: "pass" };

export interface BotView {
  seat: number;
  hand: readonly Card[];
  played: readonly Card[];
  counts: readonly number[];
  trick: Combo | null;
  trickSeat: number | null;
  firstLead: boolean;
  running: readonly number[];
  settings: Settings;
  difficulty: Difficulty;
  /** Unit interval. Easy uses it to vary the lowest play. */
  rng: () => number;
  locked?: readonly number[];
}

interface Plan {
  fives: Card[][];
  triples: Card[][];
  pairs: Card[][];
  singles: Card[][];
}

export function chooseMove(view: BotView): BotMove {
  const wrap = view.settings.straightsWrap;
  const legal = legalPlays(view);
  if (legal.length === 0) return { kind: "pass" };
  const safe = safePlays(view.hand, legal);

  const dumped = dumpTwos(view.hand, safe, wrap);
  if (dumped) return played(dumped);

  if (view.difficulty === "easy") return played(chooseEasy(view, safe, wrap));

  const winning = safe.filter((cards) => without(view.hand, cards).length === 0);
  if (winning.length > 0) {
    winning.sort((a, b) => {
      const bonus = (identify(b, wrap)?.bonusEach ?? 0) - (identify(a, wrap)?.bonusEach ?? 0);
      return bonus !== 0 ? bonus : comparePlays(b, a, wrap);
    });
    return played(winning[0]);
  }

  if (view.trick === null) return played(chooseLead(view, safe, wrap));
  const answer = chooseFollow(view, safe, wrap);
  return answer === null ? { kind: "pass" } : played(answer);
}

function played(cards: readonly Card[]): BotMove {
  return { kind: "play", cards: cards.map(formatCard) };
}

function legalPlays(view: BotView): Card[][] {
  const hands: Card[][] = [0, 1, 2, 3].map((seat) => {
    if (seat === view.seat) return view.hand.map((card) => ({ ...card }));
    const count = view.counts[seat] ?? 0;
    // Other hands stay hidden. Only the count matters, for the one-card single rule.
    return Array.from({ length: count }, () => ({ r: 3, s: "D" as const }));
  });
  const state = makeState({
    hands,
    turn: view.seat,
    trick: view.trick,
    trickSeat: view.trickSeat,
    firstLead: view.firstLead,
    locked: [...(view.locked ?? [])],
    running: [...view.running],
  });
  const seen = new Set<string>();
  const found: Card[][] = [];
  for (const cards of candidates(view.hand)) {
    if (playIssue(state, view.seat, cards, view.settings) !== null) continue;
    const id = playId(cards);
    if (seen.has(id)) continue;
    seen.add(id);
    found.push(cards);
  }
  return found;
}

function candidates(hand: readonly Card[]): Card[][] {
  const found: Card[][] = [];
  for (const card of hand) found.push([card]);
  for (const group of groupsOf(hand)) {
    if (group.length >= 2) found.push(...combinations(group, 2));
    if (group.length >= 3) found.push(...combinations(group, 3));
  }
  found.push(...straightCandidates(hand));
  found.push(...flushCandidates(hand));
  found.push(...fullHouseCandidates(hand));
  found.push(...fourCandidates(hand));
  return found;
}

function straightCandidates(hand: readonly Card[]): Card[][] {
  const found: Card[][] = [];
  for (let start = 3; start <= 11; start++) {
    const buckets: Card[][] = [];
    let missing = false;
    for (let offset = 0; offset < 5; offset++) {
      const bucket = hand.filter((card) => card.r === start + offset);
      if (bucket.length === 0) {
        missing = true;
        break;
      }
      buckets.push(bucket);
    }
    if (!missing) found.push(...product(buckets));
  }
  return found;
}

function flushCandidates(hand: readonly Card[]): Card[][] {
  const found: Card[][] = [];
  for (const suit of SUITS) {
    const suited = hand.filter((card) => card.s === suit);
    if (suited.length >= 5) found.push(...combinations(suited, 5));
  }
  return found;
}

function fullHouseCandidates(hand: readonly Card[]): Card[][] {
  const found: Card[][] = [];
  const groups = groupsOf(hand);
  for (const triple of groups) {
    if (triple.length < 3) continue;
    for (const pair of groups) {
      if (pair[0].r === triple[0].r || pair.length < 2) continue;
      found.push([...triple.slice(0, 3), ...pair.slice(0, 2)]);
    }
  }
  return found;
}

function fourCandidates(hand: readonly Card[]): Card[][] {
  const found: Card[][] = [];
  for (const group of groupsOf(hand)) {
    if (group.length < 4) continue;
    for (const kicker of hand) {
      if (kicker.r !== group[0].r) found.push([...group.slice(0, 4), kicker]);
    }
  }
  return found;
}

function combinations(items: readonly Card[], size: number): Card[][] {
  const found: Card[][] = [];
  const pick: Card[] = [];
  const walk = (start: number) => {
    if (pick.length === size) {
      found.push([...pick]);
      return;
    }
    for (let index = start; index <= items.length - (size - pick.length); index++) {
      pick.push(items[index]);
      walk(index + 1);
      pick.pop();
    }
  };
  walk(0);
  return found;
}

function product(buckets: readonly (readonly Card[])[]): Card[][] {
  let rows: Card[][] = [[]];
  for (const bucket of buckets) {
    const next: Card[][] = [];
    for (const row of rows) {
      for (const card of bucket) next.push([...row, card]);
    }
    rows = next;
  }
  return rows;
}

function groupsOf(hand: readonly Card[]): Card[][] {
  const map = new Map<number, Card[]>();
  for (const card of hand) {
    const list = map.get(card.r) ?? [];
    list.push(card);
    map.set(card.r, list);
  }
  return [...map.values()].sort((a, b) => a[0].r - b[0].r);
}

function playId(cards: readonly Card[]): string {
  return cards.map(formatCard).sort().join(",");
}

function without(hand: readonly Card[], play: readonly Card[]): Card[] {
  const left = hand.map((card) => ({ ...card }));
  for (const card of play) {
    const index = left.findIndex((item) => item.r === card.r && item.s === card.s);
    if (index >= 0) left.splice(index, 1);
  }
  return left;
}

function onlyTwos(cards: readonly Card[]): boolean {
  return cards.length > 0 && cards.every((card) => card.r === 15);
}

/** Drop a play that would leave nothing but 2s when another legal play does not. */
function safePlays(hand: readonly Card[], plays: Card[][]): Card[][] {
  const kept = plays.filter((play) => !onlyTwos(without(hand, play)));
  return kept.length > 0 ? kept : plays;
}

/**
 * The remaining non-2 cards are one combination, so play the 2s now.
 * Otherwise the last play would be 2s and could not finish the hand.
 */
function dumpTwos(hand: readonly Card[], plays: readonly Card[][], wrap: boolean): Card[] | null {
  const twos = hand.filter((card) => card.r === 15);
  const rest = hand.filter((card) => card.r !== 15);
  if (twos.length < 1 || twos.length > 3) return null;
  if (!identify(rest, wrap)) return null;
  return plays.find((play) => play.length === twos.length && play.every((card) => card.r === 15)) ?? null;
}

function comparePlays(a: readonly Card[], b: readonly Card[], wrap: boolean): number {
  const left = identify(a, wrap);
  const right = identify(b, wrap);
  if (!left || !right) return 0;
  return compareKey(left.key, right.key);
}

function lowest(plays: readonly Card[][], wrap: boolean): Card[] {
  return [...plays].sort((a, b) => comparePlays(a, b, wrap))[0];
}

function highest(plays: readonly Card[][], wrap: boolean): Card[] {
  return [...plays].sort((a, b) => comparePlays(b, a, wrap))[0];
}

function chooseEasy(view: BotView, plays: Card[][], wrap: boolean): Card[] {
  let pool = plays;
  if (view.trick === null && plays.some((play) => play.length === 1)) {
    pool = plays.filter((play) => play.length === 1);
  }
  const sorted = [...pool].sort((a, b) => comparePlays(a, b, wrap));
  const index = sorted.length > 1 && view.rng() < 0.2 ? 1 : 0;
  return sorted[index];
}

function chooseLead(view: BotView, plays: Card[][], wrap: boolean): Card[] {
  const plan = arrange(view.hand, wrap);
  const threat = smallestOpponent(view);
  const desperate = view.hand.length >= 10 || behind(view);

  if (threat <= 1) {
    const shaped = firstMatch(plays, [...plan.fives, ...plan.triples, ...plan.pairs]);
    if (shaped) return shaped;
    return controlSingle(view, plays, wrap);
  }
  if (threat === 2) {
    const shaped = firstMatch(plays, [
      ...plan.fives,
      ...plan.triples,
      ...plan.singles.filter((play) => play[0].r < 15),
    ]);
    if (shaped) return shaped;
    const pairs = plays.filter((play) => play.length === 2);
    return pairs.length > 0 ? highest(pairs, wrap) : highest(plays, wrap);
  }
  if (desperate) {
    return firstMatch(plays, [
      ...plan.fives,
      ...plan.triples,
      ...plan.pairs.filter((play) => play[0].r < 15),
      ...plan.singles.filter((play) => play[0].r < 15),
      ...plan.pairs,
      ...plan.singles,
      ...plays,
    ]) ?? lowest(plays, wrap);
  }
  return firstMatch(plays, [
    ...plan.singles.filter((play) => play[0].r <= 10),
    ...plan.pairs.filter((play) => play[0].r < 14),
    ...plan.triples.filter((play) => play[0].r < 14),
    ...plan.fives.filter((play) => play.every((card) => card.r < 15)),
    ...plan.singles.filter((play) => play[0].r < 15),
    ...plan.fives,
    ...plan.pairs,
    ...plays,
  ]) ?? lowest(plays, wrap);
}

function chooseFollow(view: BotView, plays: Card[][], wrap: boolean): Card[] | null {
  const threat = smallestOpponent(view);
  const shape = family(identify(plays[0], wrap)!.kind);
  const blockSingle = threat <= 2 && shape === "single";
  const blockPair = threat === 2 && shape === "pair";
  if (blockSingle || blockPair) {
    if (view.difficulty === "hard") {
      const sure = sureStops(view, plays, wrap, shape);
      if (sure.length > 0) return lowest(sure, wrap);
    }
    return highest(plays, wrap);
  }

  const calm = plays.filter((play) => play.every((card) => card.r !== 15));
  if (calm.length > 0) return lowest(calm, wrap);
  if (view.hand.length >= 10 || behind(view) || threat <= 2) return lowest(plays, wrap);
  return null;
}

function controlSingle(view: BotView, plays: Card[][], wrap: boolean): Card[] {
  const singles = plays.filter((play) => play.length === 1);
  const pool = singles.length > 0 ? singles : plays;
  if (view.difficulty === "hard") {
    const sure = sureStops(view, pool.filter((play) => play.length === 1), wrap, "single");
    if (sure.length > 0) return lowest(sure, wrap);
  }
  return highest(pool, wrap);
}

function sureStops(view: BotView, plays: readonly Card[][], wrap: boolean, shape: "single" | "pair"): Card[][] {
  const unseen = unseenCards(view.hand, view.played);
  if (shape === "single") return plays.filter((play) => play.length === 1 && unbeatenSingle(play[0], unseen));
  return plays.filter((play) => play.length === 2 && unbeatenPair(play, unseen, wrap));
}

function unseenCards(hand: readonly Card[], played: readonly Card[]): Card[] {
  const known = new Set<string>();
  for (const card of hand) known.add(formatCard(card));
  for (const card of played) known.add(formatCard(card));
  return fullDeck().filter((card) => !known.has(formatCard(card)));
}

function unbeatenSingle(card: Card, unseen: readonly Card[]): boolean {
  const mine = identify([card], false);
  if (!mine) return false;
  return !unseen.some((other) => {
    const theirs = identify([other], false);
    return Boolean(theirs && beats(theirs, mine));
  });
}

function unbeatenPair(play: readonly Card[], unseen: readonly Card[], wrap: boolean): boolean {
  const mine = identify(play, wrap);
  if (!mine) return false;
  for (let i = 0; i < unseen.length; i++) {
    for (let j = i + 1; j < unseen.length; j++) {
      if (unseen[i].r !== unseen[j].r) continue;
      const theirs = identify([unseen[i], unseen[j]], wrap);
      if (theirs && beats(theirs, mine)) return false;
    }
  }
  return true;
}

function firstMatch(plays: readonly Card[][], wanted: readonly (readonly Card[])[]): Card[] | null {
  const legal = new Map(plays.map((play) => [playId(play), play]));
  for (const play of wanted) {
    const found = legal.get(playId(play));
    if (found) return found;
  }
  return null;
}

function arrange(hand: readonly Card[], wrap: boolean): Plan {
  let left = hand.map((card) => ({ ...card }));
  const fives: Card[][] = [];
  while (left.length >= 5) {
    const five = bestFive(left, wrap);
    if (!five) break;
    const next = without(left, five);
    if (next.length >= left.length) break;
    fives.push(five);
    left = next;
  }
  const triples: Card[][] = [];
  const pairs: Card[][] = [];
  const singles: Card[][] = [];
  for (const group of groupsOf(left)) {
    let rest = group;
    if (rest.length >= 3) {
      triples.push(rest.slice(0, 3));
      rest = rest.slice(3);
    }
    if (rest.length >= 2) {
      pairs.push(rest.slice(0, 2));
      rest = rest.slice(2);
    }
    for (const card of rest) singles.push([card]);
  }
  return { fives, triples, pairs, singles };
}

function bestFive(hand: readonly Card[], wrap: boolean): Card[] | null {
  let best: Card[] | null = null;
  let bestKey: number[] | null = null;
  for (const play of fiveOnly(hand)) {
    const combo = identify(play, wrap);
    if (!combo || family(combo.kind) !== "five") continue;
    const key = fiveKey(play, combo);
    if (!best || !bestKey || compareKey(key, bestKey) > 0) {
      best = play;
      bestKey = key;
    }
  }
  return best;
}

function fiveOnly(hand: readonly Card[]): Card[][] {
  return [...straightCandidates(hand), ...flushCandidates(hand), ...fullHouseCandidates(hand), ...fourCandidates(hand)];
}

function fiveKey(cards: readonly Card[], combo: Combo): number[] {
  const twos = cards.filter((card) => card.r === 15).length;
  const aces = cards.filter((card) => card.r === 14).length;
  const top = Math.max(...cards.map((card) => card.r));
  return [-twos, -aces, combo.key[0], combo.bonusEach, -top];
}

function smallestOpponent(view: BotView): number {
  let smallest = 13;
  for (let seat = 0; seat < 4; seat++) {
    if (seat === view.seat) continue;
    const count = view.counts[seat] ?? 13;
    if (count < smallest) smallest = count;
  }
  return smallest;
}

function behind(view: BotView): boolean {
  const mine = view.running[view.seat] ?? 0;
  for (let seat = 0; seat < 4; seat++) {
    if (seat !== view.seat && (view.running[seat] ?? 0) < mine) return true;
  }
  return false;
}
