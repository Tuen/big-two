import { type Card } from "./rules/cards.ts";
import {
  applyPass,
  applyPlay,
  applyTimeout,
  NO_PLAY_MESSAGE,
  shouldAutoPass,
  startHand,
  type Settings,
  type Step,
} from "./rules/game.ts";
import { isLoneTwoOfSpades } from "./undo.ts";

/** One public action from the current hand. Played cards are already public. */
export interface RecentAction {
  seq: number;
  seat: number;
  kind: "play" | "pass";
  cards: string[];
  label: string;
}

export interface RecentEvent {
  seq: number;
  seat: number;
  kind: string;
  cards?: string[];
}

const RECENT_LIMIT = 8;

/**
 * Rebuild the last few plays and passes from the event log.
 * A timeout is shown as a play when it put cards down, otherwise as a pass.
 * Hidden cards are never included: only cards that were played.
 */
export function recentActions(
  deck: readonly Card[],
  running: readonly number[],
  firstHand: boolean,
  previousWinner: number | null,
  events: readonly RecentEvent[],
  settings: Settings,
  markNoPlay = true,
): RecentAction[] {
  let step: Step = {
    ok: true,
    state: startHand(deck, running, firstHand, previousWinner),
    result: null,
    message: "Deal",
  };
  const rows: RecentAction[] = [];
  for (const event of events) {
    if (!step.ok || step.state.status !== "playing") break;
    const seat = event.seat;
    const before = step.state.hands[seat]?.length ?? 0;
    const noPlay = markNoPlay
      && event.kind === "pass"
      && shouldAutoPass(step.state, seat, settings)
      && !isLoneTwoOfSpades(step.state.trickCards);
    if (event.kind === "play") step = applyPlay(step.state, seat, event.cards ?? [], settings);
    else if (event.kind === "timeout") step = applyTimeout(step.state, settings);
    else step = applyPass(step.state, seat, settings);
    if (!step.ok) break;
    const after = step.state;
    const played = (after.hands[seat]?.length ?? before) < before;
    rows.push({
      seq: event.seq,
      seat,
      kind: played ? "play" : "pass",
      cards: played ? [...after.trickCards] : [],
      label: played ? after.trick?.label ?? "Play" : noPlay ? NO_PLAY_MESSAGE : "Pass",
    });
  }
  return rows.slice(-RECENT_LIMIT);
}
