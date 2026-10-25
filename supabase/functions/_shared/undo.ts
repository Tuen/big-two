/** How long the other players have to answer an undo. Silence counts as no. */
export const UNDO_WAIT_MS = 30_000;

export const UNDO_REJECTED = "Undo rejected";
export const MOVE_UNDONE = "Move undone";
export const TWO_SPADES_MESSAGE = "2♠ – everyone passes";

export interface UndoOpen {
  handId: string;
  seq: number;
  seat: number;
  name: string;
  openedAt: string;
  votes: Record<string, boolean>;
}

/** Two yes votes undo the move. Two no votes, or silence after 30 seconds, reject it. */
export function undoOutcome(
  votes: Record<string, boolean>,
  openedAt: string,
  now: number,
): "wait" | "approved" | "rejected" {
  let approves = 0;
  let answers = 0;
  for (const vote of Object.values(votes)) {
    answers += 1;
    if (vote) approves += 1;
  }
  if (approves >= 2) return "approved";
  if (answers - approves >= 2) return "rejected";
  const opened = Date.parse(openedAt);
  if (Number.isFinite(opened) && now - opened >= UNDO_WAIT_MS) return "rejected";
  if (answers >= 3) return "rejected";
  return "wait";
}

/** Only a lone 2 of spades cannot be beaten. A pair or a five-card hand can. */
export function isLoneTwoOfSpades(cards: readonly string[]): boolean {
  return cards.length === 1 && cards[0] === "2S";
}
