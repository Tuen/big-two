import "dart:math";

import "cards.dart";
import "combo.dart";
import "score.dart";

class Settings {
  final bool passLocks;
  final bool straightsWrap;
  final int turnTimerSeconds;
  final int season;
  final String timezone;
  final int firstRoundNumber;
  const Settings({
    required this.passLocks,
    required this.straightsWrap,
    required this.turnTimerSeconds,
    required this.season,
    required this.timezone,
    required this.firstRoundNumber,
  });

  Settings copyWith({
    bool? passLocks,
    bool? straightsWrap,
    int? turnTimerSeconds,
    int? season,
    String? timezone,
    int? firstRoundNumber,
  }) {
    return Settings(
      passLocks: passLocks ?? this.passLocks,
      straightsWrap: straightsWrap ?? this.straightsWrap,
      turnTimerSeconds: turnTimerSeconds ?? this.turnTimerSeconds,
      season: season ?? this.season,
      timezone: timezone ?? this.timezone,
      firstRoundNumber: firstRoundNumber ?? this.firstRoundNumber,
    );
  }
}

const defaultSettings = Settings(
  passLocks: false,
  straightsWrap: false,
  turnTimerSeconds: 0,
  season: 24,
  timezone: "Australia/Melbourne",
  firstRoundNumber: 1,
);

class HandState {
  final List<List<PlayingCard>> hands;
  final int turn;
  final Combo? trick;
  final int? trickSeat;
  final List<String> trickCards;
  final int consecutivePasses;
  final List<int> locked;
  final bool firstLead;
  final List<int> running;
  final List<int> runningAtStart;
  final List<Bonus> bonuses;
  final String status;
  final int? winner;
  final int leadSkips;
  final String? closedReason;

  const HandState({
    required this.hands,
    required this.turn,
    required this.trick,
    required this.trickSeat,
    required this.trickCards,
    required this.consecutivePasses,
    required this.locked,
    required this.firstLead,
    required this.running,
    required this.runningAtStart,
    required this.bonuses,
    required this.status,
    required this.winner,
    required this.leadSkips,
    required this.closedReason,
  });
}

class HandResult extends HandScore {
  final int? winner;
  final String? closedReason;
  final List<Bonus> bonuses;
  const HandResult({
    required super.cardsLeft,
    required super.cardPointList,
    required super.bonusReceived,
    required super.handPoints,
    required super.runningTotals,
    required super.roundOver,
    required this.winner,
    required this.closedReason,
    required this.bonuses,
  });
}

sealed class Step {}

class StepOk extends Step {
  final HandState state;
  final HandResult? result;
  final String message;
  StepOk(this.state, this.result, this.message);
}

class StepBad extends Step {
  final String reason;
  final String message;
  StepBad(this.reason, this.message);
}

List<List<PlayingCard>> dealHands(List<PlayingCard> deck) {
  if (deck.length != 52) throw StateError("A deck has 52 cards");
  if (deck.map(formatCard).toSet().length != 52) throw StateError("The deck has a duplicate card");
  return [for (var seat = 0; seat < 4; seat++) deck.sublist(seat * 13, seat * 13 + 13)];
}

int seatHolding(List<List<PlayingCard>> hands, String cardId) {
  for (var seat = 0; seat < hands.length; seat++) {
    if (hands[seat].any((card) => formatCard(card) == cardId)) return seat;
  }
  return -1;
}

HandState startHand(List<PlayingCard> deck, List<int> running, bool firstHand, int? previousWinner) {
  final hands = dealHands(deck);
  final leader = firstHand || previousWinner == null ? seatHolding(hands, "3D") : previousWinner;
  if (leader < 0) throw StateError("The 3 of diamonds is missing");
  return HandState(
    hands: hands,
    turn: leader,
    trick: null,
    trickSeat: null,
    trickCards: const [],
    consecutivePasses: 0,
    locked: const [],
    firstLead: firstHand,
    running: [...running],
    runningAtStart: [...running],
    bonuses: const [],
    status: "playing",
    winner: null,
    leadSkips: 0,
    closedReason: null,
  );
}

HandState makeState({
  required List<List<PlayingCard>> hands,
  required int turn,
  List<int>? running,
  bool firstLead = false,
  Combo? trick,
  int? trickSeat,
  List<String>? trickCards,
  int consecutivePasses = 0,
  List<int>? locked,
}) {
  final totals = running ?? [0, 0, 0, 0];
  return HandState(
    hands: hands,
    turn: turn,
    trick: trick,
    trickSeat: trickSeat,
    trickCards: trickCards ?? const [],
    consecutivePasses: consecutivePasses,
    locked: locked ?? const [],
    firstLead: firstLead,
    running: [...totals],
    runningAtStart: [...totals],
    bonuses: const [],
    status: "playing",
    winner: null,
    leadSkips: 0,
    closedReason: null,
  );
}

int _nextSeat(int seat) => (seat + 1) % 4;

/// A lower single is refused while the next player is on their last card.
const highestSingleMessage = "Next player has one card left: you must play your highest single.";

const highestSingleNote = "Next player is on one card: singles must be your highest card";

const mustPlayHighestMessage = "Next player has one card left: you must play your highest card.";

const mustPlayHighestNote = "Next player is on one card: you must play your highest card";

const twoOnTableNote = "A 2 is on the table: you may pass, or play your highest card";

const cannotBeatNote = "Your highest card can't beat this single. You may pass.";

bool nextPlayerHasOneCard(HandState state, int seat) => state.hands[_nextSeat(seat)].length == 1;

HandResult? resultOf(HandState state) {
  if (state.status != "complete") return null;
  final score = scoreCounts(state.hands.map((hand) => hand.length).toList(), state.running, state.bonuses);
  return HandResult(
    cardsLeft: score.cardsLeft,
    cardPointList: score.cardPointList,
    bonusReceived: score.bonusReceived,
    handPoints: score.handPoints,
    runningTotals: score.runningTotals,
    roundOver: score.roundOver,
    winner: state.winner,
    closedReason: state.closedReason,
    bonuses: state.bonuses,
  );
}

int _bitCount(int mask) {
  var count = 0;
  var value = mask;
  while (value != 0) {
    count += value & 1;
    value >>= 1;
  }
  return count;
}

List<List<PlayingCard>> _subsets(List<PlayingCard> hand) {
  final found = <List<PlayingCard>>[];
  for (var mask = 1; mask < (1 << hand.length); mask++) {
    final size = _bitCount(mask);
    if (size != 1 && size != 2 && size != 3 && size != 5) continue;
    found.add([for (var index = 0; index < hand.length; index++) if (mask & (1 << index) != 0) hand[index]]);
  }
  return found;
}

String? playIssue(HandState state, int seat, List<PlayingCard> cards, Settings settings) {
  if (state.status != "playing") return "This hand is over";
  if (seat != state.turn) return "Not your turn";
  if (state.locked.contains(seat)) return "You passed this trick";
  if (cards.isEmpty) return "Select cards to play";
  final combo = identify(cards, wrap: settings.straightsWrap);
  if (combo == null) return "Not a valid combination";
  if (removeCards(state.hands[seat], cards) == null) return "Those cards are not in your hand";
  if (state.firstLead && state.trick == null && !cards.any((card) => formatCard(card) == "3D")) {
    return "First play must include the 3♦";
  }
  if (state.trick != null && family(combo.kind) != family(state.trick!.kind)) {
    return "You need ${neededShape(state.trick!.kind)}";
  }
  if (state.trick != null && !beats(combo, state.trick!)) return "Doesn't beat the current play";
  if (cards.length == state.hands[seat].length && cards.every((card) => card.rank == 15)) {
    return "You can't go out if you only have 2s";
  }
  if (cards.length == 1 && nextPlayerHasOneCard(state, seat)) {
    final highest = highestCard(state.hands[seat]);
    final played = cards.first;
    if (highest != null && played != highest) return highestSingleMessage;
  }
  return null;
}

bool mustPlayHighestSingle(HandState state, int seat, Settings settings) {
  if (!nextPlayerHasOneCard(state, seat)) return false;
  final trick = state.trick;
  if (trick == null || family(trick.kind) != "single" || trick.cards.isEmpty || trick.cards.first.rank == 15) {
    return false;
  }
  final highest = highestCard(state.hands[seat]);
  if (highest == null) return false;
  return playIssue(state, seat, [highest], settings) == null;
}

String? oneCardNote(HandState state, int seat, Settings settings) {
  if (!nextPlayerHasOneCard(state, seat)) return null;
  if (mustPlayHighestSingle(state, seat, settings)) return mustPlayHighestNote;
  final trick = state.trick;
  if (trick != null && family(trick.kind) == "single" && trick.cards.isNotEmpty && trick.cards.first.rank == 15) {
    return twoOnTableNote;
  }
  if (trick != null && family(trick.kind) == "single") {
    final highest = highestCard(state.hands[seat]);
    if (highest == null || playIssue(state, seat, [highest], settings) != null) return cannotBeatNote;
  }
  return highestSingleNote;
}

String lastCardMessage(String name) {
  final who = name.trim().isEmpty ? "Someone" : name.trim();
  return "$who plays their last card";
}

/// The one card to play on its own, when this seat has a single legal card left.
String? automaticLastCard(HandState state, int seat, Settings settings) {
  if (state.status != "playing" || state.turn != seat) return null;
  final hand = state.hands[seat];
  if (hand.length != 1) return null;
  if (playIssue(state, seat, hand, settings) != null) return null;
  return formatCard(hand.first);
}

const noPlayMessage = "No play – auto pass";

/// True when this seat is following and nothing they hold is a legal play.
/// A new lead is never an auto-pass, even when the only cards are 2s.
bool shouldAutoPass(HandState state, int seat, Settings settings) {
  if (state.status != "playing" || state.turn != seat) return false;
  if (state.trick == null) return false;
  if (passIssue(state, seat, settings) != null) return false;
  return legalSelections(state, seat, settings).isEmpty;
}

String? passIssue(HandState state, int seat, Settings settings) {
  if (state.status != "playing") return "This hand is over";
  if (seat != state.turn) return "Not your turn";
  if (mustPlayHighestSingle(state, seat, settings)) return mustPlayHighestMessage;
  if (state.trick == null && legalSelections(state, seat, settings).isNotEmpty) {
    return "You must lead — passing isn't allowed";
  }
  return null;
}

List<List<PlayingCard>> legalSelections(HandState state, int seat, Settings settings) {
  if (state.status != "playing" || seat != state.turn || state.locked.contains(seat)) return [];
  return _subsets(state.hands[seat]).where((cards) => playIssue(state, seat, cards, settings) == null).toList();
}

HandState _withBonus(HandState state, int seat, Combo combo) {
  if (combo.bonusName == null || combo.bonusEach == 0) return state;
  final bonus = Bonus(
    seat: seat,
    kind: switch (combo.kind) {
      ComboKind.four => "four",
      ComboKind.straightFlush => "straight_flush",
      ComboKind.royalFlush => "royal_flush",
      _ => combo.kind.name,
    },
    combo: combo.bonusName!,
    pointsEach: combo.bonusEach,
  );
  return HandState(
    hands: state.hands,
    turn: state.turn,
    trick: state.trick,
    trickSeat: state.trickSeat,
    trickCards: state.trickCards,
    consecutivePasses: state.consecutivePasses,
    locked: state.locked,
    firstLead: state.firstLead,
    running: [for (var index = 0; index < 4; index++) index == seat ? state.running[index] : state.running[index] + combo.bonusEach],
    runningAtStart: state.runningAtStart,
    bonuses: [...state.bonuses, bonus],
    status: state.status,
    winner: state.winner,
    leadSkips: state.leadSkips,
    closedReason: state.closedReason,
  );
}

HandState _copy(HandState state, {
  List<List<PlayingCard>>? hands,
  int? turn,
  Combo? trick,
  bool clearTrick = false,
  int? trickSeat,
  bool clearTrickSeat = false,
  List<String>? trickCards,
  int? consecutivePasses,
  List<int>? locked,
  bool? firstLead,
  List<int>? running,
  List<Bonus>? bonuses,
  String? status,
  int? winner,
  bool clearWinner = false,
  int? leadSkips,
  String? closedReason,
  bool clearClosed = false,
}) {
  return HandState(
    hands: hands ?? state.hands,
    turn: turn ?? state.turn,
    trick: clearTrick ? null : (trick ?? state.trick),
    trickSeat: clearTrickSeat ? null : (trickSeat ?? state.trickSeat),
    trickCards: trickCards ?? state.trickCards,
    consecutivePasses: consecutivePasses ?? state.consecutivePasses,
    locked: locked ?? state.locked,
    firstLead: firstLead ?? state.firstLead,
    running: running ?? state.running,
    runningAtStart: state.runningAtStart,
    bonuses: bonuses ?? state.bonuses,
    status: status ?? state.status,
    winner: clearWinner ? null : (winner ?? state.winner),
    leadSkips: leadSkips ?? state.leadSkips,
    closedReason: clearClosed ? null : (closedReason ?? state.closedReason),
  );
}

Step applyPlay(HandState state, int seat, List<String> cardIds, Settings settings) {
  late List<PlayingCard> cards;
  try {
    cards = parseCards(cardIds);
  } on FormatException {
    return StepBad("bad_card", "Those cards are not in the deck");
  }
  final issue = playIssue(state, seat, cards, settings);
  if (issue != null) return StepBad("illegal", issue);
  final combo = identify(cards, wrap: settings.straightsWrap)!;
  final left = removeCards(state.hands[seat], cards)!;
  final hands = [
    for (var index = 0; index < 4; index++) index == seat ? left : [...state.hands[index]],
  ];
  var next = _withBonus(
    _copy(
      state,
      hands: hands,
      trick: combo,
      trickSeat: seat,
      trickCards: cards.map(formatCard).toList(),
      consecutivePasses: 0,
      firstLead: false,
      leadSkips: 0,
    ),
    seat,
    combo,
  );
  if (left.isEmpty) {
    next = _copy(next, status: "complete", winner: seat, closedReason: "winner");
    return StepOk(next, resultOf(next), "${combo.label} wins the hand");
  }
  return StepOk(_copy(next, turn: _nextSeat(seat)), null, combo.label);
}

Step applyPass(HandState state, int seat, Settings settings) {
  final issue = passIssue(state, seat, settings);
  if (issue != null) {
    if (issue == mustPlayHighestMessage) return StepBad("must_play", issue);
    if (state.status != "playing") return StepBad("over", issue);
    if (seat != state.turn) return StepBad("turn", issue);
    return StepBad("must_lead", issue);
  }
  if (state.trick == null) {
    final skips = state.leadSkips + 1;
    if (skips >= 4) {
      final done = _copy(state, leadSkips: skips, status: "complete", clearWinner: true, closedReason: "stuck");
      return StepOk(done, resultOf(done), "Nobody can lead. The hand is scored as it stands.");
    }
    return StepOk(_copy(state, turn: _nextSeat(seat), leadSkips: skips), null, "You can't go out if you only have 2s. The lead passes on.");
  }
  final locked = settings.passLocks && !state.locked.contains(seat) ? [...state.locked, seat] : [...state.locked];
  final passes = state.consecutivePasses + 1;
  if (passes >= 3 && state.trickSeat != null) {
    return StepOk(
      _copy(
        state,
        turn: state.trickSeat,
        clearTrick: true,
        clearTrickSeat: true,
        trickCards: const [],
        consecutivePasses: 0,
        locked: const [],
        leadSkips: 0,
      ),
      null,
      "The trick is won. Lead anything.",
    );
  }
  return StepOk(
    _copy(state, turn: _nextSeat(seat), consecutivePasses: passes, locked: locked),
    null,
    "Pass",
  );
}

List<String>? lowestLegalPlay(HandState state, int seat, Settings settings) {
  final options = legalSelections(state, seat, settings);
  if (options.isEmpty) return null;
  final singles = options.where((cards) => cards.length == 1).toList();
  final pool = state.trick == null && singles.isNotEmpty ? singles : options;
  var best = pool.first;
  var bestCombo = identify(best, wrap: settings.straightsWrap);
  for (final cards in pool.skip(1)) {
    final combo = identify(cards, wrap: settings.straightsWrap);
    if (combo != null && bestCombo != null && beats(bestCombo, combo)) {
      best = cards;
      bestCombo = combo;
    }
  }
  return best.map(formatCard).toList();
}

Step applyTimeout(HandState state, Settings settings) {
  if (mustPlayHighestSingle(state, state.turn, settings)) {
    final highest = highestCard(state.hands[state.turn]);
    if (highest != null) return applyPlay(state, state.turn, [formatCard(highest)], settings);
  }
  if (state.trick == null) {
    final cards = lowestLegalPlay(state, state.turn, settings);
    if (cards == null) return applyPass(state, state.turn, settings);
    return applyPlay(state, state.turn, cards, settings);
  }
  return applyPass(state, state.turn, settings);
}

List<int> roundWinners(List<int> totals) {
  final best = totals.reduce((a, b) => a < b ? a : b);
  return [for (var seat = 0; seat < totals.length; seat++) if (totals[seat] == best) seat];
}

int indexBelow(int maxExclusive, int Function() nextUint32) {
  const range = 0x100000000;
  final limit = range - (range % maxExclusive);
  while (true) {
    final value = nextUint32() & 0xffffffff;
    if (value < limit) return value % maxExclusive;
  }
}

void shuffleInPlace<T>(List<T> items, int Function() nextUint32) {
  for (var i = items.length - 1; i > 0; i--) {
    final j = indexBelow(i + 1, nextUint32);
    final swap = items[i];
    items[i] = items[j];
    items[j] = swap;
  }
}

List<PlayingCard> shuffleDeck([List<PlayingCard>? deck]) {
  final copy = [...(deck ?? fullDeck())];
  final random = Random.secure();
  shuffleInPlace(copy, () => random.nextInt(0x100000000));
  return copy;
}
