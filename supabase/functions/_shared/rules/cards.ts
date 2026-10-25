export type Suit = "D" | "C" | "H" | "S";

export const SUITS: readonly Suit[] = ["D", "C", "H", "S"];

/** Diamonds < clubs < hearts < spades. */
export const SUIT_VALUE: Record<Suit, number> = { D: 1, C: 2, H: 3, S: 4 };

export const SUIT_NAME: Record<Suit, string> = {
  D: "diamonds",
  C: "clubs",
  H: "hearts",
  S: "spades",
};

const RANK_CHAR = ["", "", "", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A", "2"];

export function rankName(rank: number): string {
  if (rank === 10) return "10";
  return RANK_CHAR[rank] ?? String(rank);
}

export interface Card {
  r: number;
  s: Suit;
}

const RANK_BY_TEXT: Record<string, number> = {
  "3": 3,
  "4": 4,
  "5": 5,
  "6": 6,
  "7": 7,
  "8": 8,
  "9": 9,
  "10": 10,
  T: 10,
  J: 11,
  Q: 12,
  K: 13,
  A: 14,
  "2": 15,
};

export function formatCard(card: Card): string {
  return `${RANK_CHAR[card.r]}${card.s}`;
}

export function parseCard(text: string): Card {
  const raw = text.trim().toUpperCase();
  if (raw.length < 2) throw new Error(`Bad card: ${text}`);
  const suit = raw.slice(-1) as Suit;
  if (!SUITS.includes(suit)) throw new Error(`Bad suit: ${text}`);
  const rank = RANK_BY_TEXT[raw.slice(0, -1)];
  if (rank === undefined) throw new Error(`Bad rank: ${text}`);
  return { r: rank, s: suit };
}

export function parseCards(list: readonly string[]): Card[] {
  return list.map(parseCard);
}

export function sameCard(a: Card, b: Card): boolean {
  return a.r === b.r && a.s === b.s;
}

/** Higher rank wins. The same rank is broken by suit: spades > hearts > clubs > diamonds. */
export function beatsCard(a: Card, b: Card): boolean {
  if (a.r !== b.r) return a.r > b.r;
  return SUIT_VALUE[a.s] > SUIT_VALUE[b.s];
}

export function highestCard(cards: readonly Card[]): Card | null {
  let best: Card | null = null;
  for (const card of cards) {
    if (!best || beatsCard(card, best)) best = card;
  }
  return best;
}

export function fullDeck(): Card[] {
  const cards: Card[] = [];
  for (const suit of SUITS) {
    for (let rank = 3; rank <= 15; rank++) cards.push({ r: rank, s: suit });
  }
  return cards;
}

export function deckCanonical(deck: readonly Card[]): string {
  return deck.map(formatCard).join(",");
}

export function removeCards(hand: readonly Card[], play: readonly Card[]): Card[] | null {
  const left = hand.map((card) => ({ ...card }));
  for (const card of play) {
    const index = left.findIndex((other) => sameCard(other, card));
    if (index < 0) return null;
    left.splice(index, 1);
  }
  return left;
}

export function sortCards(cards: readonly Card[], mode: "rank" | "suit"): Card[] {
  const copy = cards.map((card) => ({ ...card }));
  copy.sort((a, b) => {
    if (mode === "suit") {
      const suit = SUIT_VALUE[a.s] - SUIT_VALUE[b.s];
      if (suit !== 0) return suit;
      return a.r - b.r;
    }
    if (a.r !== b.r) return a.r - b.r;
    return SUIT_VALUE[a.s] - SUIT_VALUE[b.s];
  });
  return copy;
}
