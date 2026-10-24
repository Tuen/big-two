import { type Card, formatCard, rankName, SUIT_NAME, SUIT_VALUE, type Suit } from "./cards.ts";

/**
 * Straight flushes compare by suit, then by the cards.
 * Any spade straight flush beats any heart one.
 * The same suit is compared by straight strength (the numbers).
 * Royal flushes stay a higher category and compare by suit.
 */
export const STRAIGHT_FLUSH_SUIT_ONLY = true;

export type ComboKind =
  | "single"
  | "pair"
  | "triple"
  | "straight"
  | "flush"
  | "full_house"
  | "four"
  | "straight_flush"
  | "royal_flush";

export interface Combo {
  kind: ComboKind;
  cards: Card[];
  /** Lexicographic key. A bigger key wins inside the same family. */
  key: number[];
  label: string;
  /** Points added to every other player when this combo is played. */
  bonusEach: number;
  /** Webhook name for bonus combos. */
  bonusName: string | null;
}

export function family(kind: ComboKind): "single" | "pair" | "triple" | "five" {
  if (kind === "single" || kind === "pair" || kind === "triple") return kind;
  return "five";
}

export function compareKey(a: readonly number[], b: readonly number[]): number {
  const length = Math.max(a.length, b.length);
  for (let i = 0; i < length; i++) {
    const diff = (a[i] ?? 0) - (b[i] ?? 0);
    if (diff !== 0) return diff;
  }
  return 0;
}

export function beats(attack: Combo, defense: Combo): boolean {
  if (family(attack.kind) !== family(defense.kind)) return false;
  return compareKey(attack.key, defense.key) > 0;
}

interface StraightInfo {
  strength: number;
  top: Card;
}

function countsByRank(cards: readonly Card[]): Map<number, Card[]> {
  const groups = new Map<number, Card[]>();
  for (const card of cards) {
    const list = groups.get(card.r) ?? [];
    list.push(card);
    groups.set(card.r, list);
  }
  return groups;
}

function highestSuit(cards: readonly Card[]): number {
  return Math.max(...cards.map((card) => SUIT_VALUE[card.s]));
}

function cardWithRank(cards: readonly Card[], rank: number): Card {
  const card = cards.find((item) => item.r === rank);
  if (!card) throw new Error("missing rank");
  return card;
}

/**
 * Straights are five consecutive ranks from 3-4-5-6-7 (lowest) through J-Q-K-A-2 (highest).
 * The 2 is always high. A straight never wraps past the 2, so A-2-3-4-5, 2-3-4-5-6,
 * Q-K-A-2-3, and K-A-2-3-4 are not straights. `wrap` is kept so callers still compile;
 * it cannot make those hands legal.
 */
export function straightInfo(cards: readonly Card[], wrap: boolean): StraightInfo | null {
  void wrap;
  if (cards.length !== 5) return null;
  const ranks = cards.map((card) => card.r);
  if (new Set(ranks).size !== 5) return null;

  const sorted = [...ranks].sort((a, b) => a - b);
  const consecutive = sorted.every((rank, index) => index === 0 || rank === sorted[index - 1] + 1);
  if (consecutive && sorted[4] - sorted[0] === 4) {
    const topRank = sorted[4];
    return { strength: topRank - 5, top: cardWithRank(cards, topRank) };
  }
  return null;
}

function isRoyal(cards: readonly Card[]): boolean {
  const ranks = new Set(cards.map((card) => card.r));
  return [10, 11, 12, 13, 14].every((rank) => ranks.has(rank));
}

function sameSuit(cards: readonly Card[]): Suit | null {
  const suit = cards[0]?.s;
  if (!suit) return null;
  return cards.every((card) => card.s === suit) ? suit : null;
}

function descendingRanks(cards: readonly Card[]): number[] {
  return cards.map((card) => card.r).sort((a, b) => b - a);
}

export function identify(cards: readonly Card[], wrap = false): Combo | null {
  if (cards.length === 0) return null;
  const ids = cards.map(formatCard);
  if (new Set(ids).size !== cards.length) return null;
  const owned = cards.map((card) => ({ ...card }));

  if (owned.length === 1) {
    const card = owned[0];
    return {
      kind: "single",
      cards: owned,
      key: [card.r, SUIT_VALUE[card.s]],
      label: rankName(card.r),
      bonusEach: 0,
      bonusName: null,
    };
  }

  if (owned.length === 2 || owned.length === 3) {
    if (new Set(owned.map((card) => card.r)).size !== 1) return null;
    const kind = owned.length === 2 ? "pair" : "triple";
    const rank = owned[0].r;
    const name = rankName(rank);
    return {
      kind,
      cards: owned,
      key: [rank, highestSuit(owned)],
      label: kind === "pair" ? `Pair of ${name}s` : `Triple ${name}s`,
      bonusEach: 0,
      bonusName: null,
    };
  }

  if (owned.length !== 5) return null;

  const groups = [...countsByRank(owned).values()].sort((a, b) => b.length - a.length);
  const straight = straightInfo(owned, wrap);
  const flushSuit = sameSuit(owned);

  if (straight && flushSuit) {
    if (isRoyal(owned)) {
      return {
        kind: "royal_flush",
        cards: owned,
        key: [6, SUIT_VALUE[flushSuit]],
        label: `Royal flush (${SUIT_NAME[flushSuit]})`,
        bonusEach: 10,
        bonusName: "royal flush",
      };
    }
    const key = STRAIGHT_FLUSH_SUIT_ONLY
      ? [5, SUIT_VALUE[flushSuit], straight.strength]
      : [5, straight.strength, SUIT_VALUE[straight.top.s]];
    return {
      kind: "straight_flush",
      cards: owned,
      key,
      label: `Straight flush (${SUIT_NAME[flushSuit]})`,
      bonusEach: 8,
      bonusName: "straight flush",
    };
  }

  if (groups.length === 2 && groups[0].length === 4) {
    return {
      kind: "four",
      cards: owned,
      key: [4, groups[0][0].r],
      label: `Four ${rankName(groups[0][0].r)}s`,
      bonusEach: 5,
      bonusName: "four of a kind",
    };
  }

  if (groups.length === 2 && groups[0].length === 3 && groups[1].length === 2) {
    return {
      kind: "full_house",
      cards: owned,
      key: [3, groups[0][0].r],
      label: `Full house, ${rankName(groups[0][0].r)}s`,
      bonusEach: 0,
      bonusName: null,
    };
  }

  if (flushSuit) {
    return {
      kind: "flush",
      cards: owned,
      key: [2, SUIT_VALUE[flushSuit], ...descendingRanks(owned)],
      label: `Flush (${SUIT_NAME[flushSuit]})`,
      bonusEach: 0,
      bonusName: null,
    };
  }

  if (straight) {
    return {
      kind: "straight",
      cards: owned,
      key: [1, straight.strength, SUIT_VALUE[straight.top.s]],
      label: "Straight",
      bonusEach: 0,
      bonusName: null,
    };
  }

  return null;
}

export function neededShape(kind: ComboKind): string {
  const group = family(kind);
  if (group === "single") return "a single";
  if (group === "pair") return "a pair";
  if (group === "triple") return "a triple";
  return "a five-card hand";
}
