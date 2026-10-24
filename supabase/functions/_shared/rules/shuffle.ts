import { type Card, deckCanonical, fullDeck } from "./cards.ts";

export type NextUint32 = () => number;

const RANGE = 0x100000000;

/** Uniform integer in [0, maxExclusive), rejecting values that would bias `%`. */
export function indexBelow(maxExclusive: number, nextUint32: NextUint32): number {
  if (!Number.isInteger(maxExclusive) || maxExclusive <= 0 || maxExclusive > RANGE) {
    throw new Error("bad range");
  }
  const limit = RANGE - (RANGE % maxExclusive);
  while (true) {
    const value = nextUint32() >>> 0;
    if (value < limit) return value % maxExclusive;
  }
}

export function shuffleInPlace<T>(items: T[], nextUint32: NextUint32): void {
  for (let i = items.length - 1; i > 0; i--) {
    const j = indexBelow(i + 1, nextUint32);
    const swap = items[i];
    items[i] = items[j];
    items[j] = swap;
  }
}

export function cryptoUint32(): number {
  const buffer = new Uint32Array(1);
  crypto.getRandomValues(buffer);
  return buffer[0];
}

export function shuffleDeck(deck: readonly Card[] = fullDeck()): Card[] {
  const copy = deck.map((card) => ({ ...card }));
  shuffleInPlace(copy, cryptoUint32);
  return copy;
}

export async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function commitDeck(deck: readonly Card[]): Promise<{ canonical: string; commitment: string }> {
  const canonical = deckCanonical(deck);
  return { canonical, commitment: await sha256Hex(canonical) };
}
