# House rules

These are the rules the app plays. The ones marked **confirm** were not fully spelled out in the brief. Say if any of them should change before a close round is treated as official.

Two switches are already in the code, one in each engine. They must stay the same.

- TypeScript: `STRAIGHT_FLUSH_SUIT_ONLY` in `supabase/functions/_shared/rules/combo.ts`
- Dart: `straightFlushSuitOnly` in `app/lib/rules/combo.dart`

`STRAIGHT_FLUSH_SUIT_ONLY` and `straightFlushSuitOnly` are `true`.

## Deck and combinations

A standard 52-card deck. Four players, 13 cards each.

Ranks, low to high: 3 4 5 6 7 8 9 10 J Q K A 2.

Suits, low to high: diamonds, clubs, hearts, spades.

Legal plays are a single, a pair, a triple, or a five-card hand. Nothing else.

A single is beaten only by a higher single: higher rank, then higher suit. A pair or a triple is beaten only by the same shape: higher rank, then the highest suit in the set. A five-card hand is beaten only by a higher five-card hand. You may pass whenever you are not leading.

Five-card hands, low to high:

1. Straight
2. Flush
3. Full house
4. Four of a kind plus one
5. Straight flush
6. Royal flush

Equal does not win. The new play has to be strictly higher.

A full house is ranked by the triple only. The pair is ignored. Four of a kind is ranked by the four only. The spare card is ignored.

## Flushes

A flush is ranked by suit, and only by suit, until the suits match. A low spade flush beats a high heart flush.

**Confirm.** If both flushes are the same suit, the cards are compared from the highest rank downward. Two players can each hold a five-card heart flush in one deal, so that order matters.

## Straights

A straight is five consecutive ranks. The 2 is high. The lowest straight is `3-4-5-6-7`. The highest is `J-Q-K-A-2`. Straights compare by the highest card, then by that card's suit, so two `J-Q-K-A-2` straights are ranked by the suit of the 2. `J-Q-K-A-2` beats `10-J-Q-K-A`.

A straight never wraps past the 2. These are not straights, whether or not the table's wrap switch is on:

- `A-2-3-4-5`
- `2-3-4-5-6`
- `Q-K-A-2-3`
- `K-A-2-3-4`

The wrap switch is still stored with the table. It cannot make any of those four hands legal. An ace is high in `10-J-Q-K-A`. A 2 is high in `J-Q-K-A-2`.

## Straight flushes and royals

A royal flush is `10-J-Q-K-A` of one suit. It is its own category, above every straight flush. Royals are compared by suit only. The bonus is +10, not also +8. A diamond royal still beats a spade straight flush, because a royal is the higher category.

`A-2-3-4-5` of one suit is a flush, not a straight flush. The bonus is 0. `2-3-4-5-6` of one suit is also a flush. `J-Q-K-A-2` of one suit is a straight flush (+8), not a royal. Two straight flushes of `J-Q-K-A-2` compare by the suit of the 2. A `J-Q-K-A-2` straight flush does not beat a royal.

Straight flushes rank by suit. Any spade straight flush beats any heart one, any heart one beats any club one, and any club one beats any diamond one. When both straight flushes are the same suit, the higher cards win. A spade `3-4-5-6-7` beats a heart `9-10-J-Q-K`. A spade `9-10-J-Q-K` beats a spade `3-4-5-6-7`.

## The last card

The hand ends as soon as one player plays their last card.

You cannot go out on 2s alone. One, two, or three 2s are refused when that play would empty your hand. Four 2s are not a legal combination, so they cannot empty the hand either. Playing a 2, a pair of 2s, or a triple of 2s is legal while other cards remain. A five-card hand may contain a 2 and may be the last play, including four 2s plus one other card.

If the person who must lead has no legal play, the lead passes clockwise. That happens when their only cards are one 2 or a pair of 2s. The button says **Pass lead**. Three 2s can still lead a single or a pair and keep the rest. If all four players are skipped on an empty trick, the hand ends with no winner (`stuck`). Everyone is scored on the cards they still hold. The next hand is led by whoever holds the 3 of diamonds, the same as a first hand.

## One card on the next player

When it is your turn and the next player has exactly one card left, a single must be the highest card in your hand. Rank comes first: 2, then ace, king, down to 3. The same rank is broken by suit: spades, then hearts, clubs, diamonds.

A pair, a triple, or a five-card hand may be any legal value. Leading a new trick follows the same rule: a single lead must be your highest card. On a pair, triple, or five-card trick, passing stays as it was.

If you are following a single that is not a 2, and your highest card can legally beat it, you must play that card. Passing is refused: "Next player has one card left: you must play your highest card." If your highest card cannot legally beat it, including when playing it would be going out on 2s alone, you may pass.

If the single on the table is a 2 of any suit, you may pass, even when you hold a higher 2. A single you do choose to play must still be your highest card.

Only the player sitting immediately before the one-card player is bound by this. Everyone else plays normally.

A lower single is refused with: "Next player has one card left: you must play your highest single."

## Undo

Undo puts back only your own last play or pass, and only before the next player plays or passes. It never works if that play ended the hand. The other three are asked: approve, or don't approve. Two approvals put the cards back and it is your turn again. Fewer than two, or no answer within 30 seconds, rejects it. Everyone then sees "Undo rejected". Computer players always approve. Nobody can play while the question is open.

## The 2 of spades

A single 2 of spades cannot be beaten. About a second later the other three pass on their own, the lead comes back to the player who played it, and the table says "2♠ – everyone passes". A pair or a five-card hand that merely contains the 2 of spades is not passed automatically.

## Leading

The first hand of a round is led by the holder of the 3 of diamonds, and that first play must include it. It can sit inside a pair, a triple, or a five-card hand.

Later hands are led by the winner of the previous hand, who may lead any legal combination. If the previous hand ended stuck, the next hand falls back to the 3 of diamonds.

The trick ends when the other three players have passed. The person who played last leads anything.

**Confirm, and this one matches the brief.** Passing locks you out of the rest of the trick only when that setting is on. The default is **off**, so a pass does not stop you playing if the turn comes back before three passes. With the lock on, everyone who passed stays out until the trick is won.

## Scoring

Lower is better. The winner scores 0 for the cards they played off.

Each card left is 1 point, with three exceptions:

- 9 cards left score 9. They are not doubled.
- 10, 11, or 12 cards left are doubled: 20, 22, 24.
- 13 cards left, never having played a card, score 36.

These bonuses are added to **every other** player's running total at the moment the combination is played, not at the end of the hand. The player who played it does not take the penalty.

| Combination | Added to each of the other three |
| --- | --- |
| Four of a kind + 1 | 5 |
| Straight flush | 8 |
| Royal flush | 10 |

A royal does not also add the straight-flush bonus. The bonus on the winning play is applied before card points.

The round ends at the end of the hand in which any running total is 50 or more. A bonus that pushes someone past 50 in the middle of the hand does **not** stop that hand. Finish the hand, add the card points, then end the round. The lowest total wins. The app shows a round summary and offers **New round**.

**Confirm.** If two or more players share the lowest total, they are joint winners.

During a hand the scoreboard includes bonuses already played and does not yet include card points. Card points land when the hand ends. The gap next to a name is how far they are behind the next-better player. Totals of 50 or more are highlighted.

## Timer

Default off.

**Confirm.** When a timer is on, any phone that still has the table open applies it, because the server does not sit and wait. Followers are passed. The leader plays their lowest legal single. If they cannot lead, the lead skips as above. Practice mode does not start the clock until **Show my cards**.

## Round bookkeeping

**Confirm these defaults.** Season starts at 24. The first round number starts at 1, so a table can begin at round 11 instead. Webhook dates use Australia/Melbourne unless the host picks another zone from the list in the lobby (Sydney, Brisbane, Adelaide, Perth, Auckland, UTC).

The worked example, which the tests check: start the hand at 20, 30, 38, 45. Damien (last seat) plays a straight flush. The other three immediately go to 28, 38, 46. Damien stays on 45. Cards left are 0, 11, 9, 4, so card points are 0, 22, 9, 4. Hand points, card points plus bonuses received, are 8, 30, 17, 4. Totals become 28, 60, 55, 49, and the round ends.
