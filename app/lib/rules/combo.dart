import "cards.dart";

/// Straight flushes compare by suit, then by the cards.
/// Any spade straight flush beats any heart one.
/// The same suit is compared by straight strength (the numbers).
const straightFlushSuitOnly = true;

enum ComboKind { single, pair, triple, straight, flush, fullHouse, four, straightFlush, royalFlush }

class Combo {
  final ComboKind kind;
  final List<PlayingCard> cards;
  final List<int> key;
  final String label;
  final int bonusEach;
  final String? bonusName;
  const Combo({
    required this.kind,
    required this.cards,
    required this.key,
    required this.label,
    required this.bonusEach,
    required this.bonusName,
  });
}

String family(ComboKind kind) {
  switch (kind) {
    case ComboKind.single:
      return "single";
    case ComboKind.pair:
      return "pair";
    case ComboKind.triple:
      return "triple";
    default:
      return "five";
  }
}

int compareKey(List<int> a, List<int> b) {
  final length = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final av = i < a.length ? a[i] : 0;
    final bv = i < b.length ? b[i] : 0;
    if (av != bv) return av - bv;
  }
  return 0;
}

bool beats(Combo attack, Combo defense) {
  if (family(attack.kind) != family(defense.kind)) return false;
  return compareKey(attack.key, defense.key) > 0;
}

class _StraightInfo {
  final int strength;
  final PlayingCard top;
  const _StraightInfo(this.strength, this.top);
}

PlayingCard _cardWithRank(List<PlayingCard> cards, int rank) => cards.firstWhere((card) => card.rank == rank);

int _highestSuit(List<PlayingCard> cards) => cards.map((card) => suitValue[card.suit]!).reduce((a, b) => a > b ? a : b);

/// Five consecutive ranks from 3-4-5-6-7 through J-Q-K-A-2. The 2 is high.
/// A straight never wraps past the 2. The ignored argument cannot make
/// A-2-3-4-5, 2-3-4-5-6, Q-K-A-2-3, or K-A-2-3-4 legal.
_StraightInfo? _straightInfo(List<PlayingCard> cards, bool _) {
  if (cards.length != 5) return null;
  final ranks = cards.map((card) => card.rank).toList();
  if (ranks.toSet().length != 5) return null;
  final sorted = [...ranks]..sort();
  final consecutive = List.generate(5, (index) => index == 0 || sorted[index] == sorted[index - 1] + 1).every((ok) => ok);
  if (consecutive && sorted[4] - sorted[0] == 4) {
    return _StraightInfo(sorted[4] - 5, _cardWithRank(cards, sorted[4]));
  }
  return null;
}

bool _isRoyal(List<PlayingCard> cards) {
  final ranks = cards.map((card) => card.rank).toSet();
  return [10, 11, 12, 13, 14].every(ranks.contains);
}

Suit? _sameSuit(List<PlayingCard> cards) {
  final suit = cards.first.suit;
  return cards.every((card) => card.suit == suit) ? suit : null;
}

List<int> _descending(List<PlayingCard> cards) {
  final ranks = cards.map((card) => card.rank).toList()..sort((a, b) => b.compareTo(a));
  return ranks;
}

Combo? identify(List<PlayingCard> cards, {bool wrap = false}) {
  if (cards.isEmpty) return null;
  final ids = cards.map(formatCard).toList();
  if (ids.toSet().length != cards.length) return null;
  final owned = [...cards];

  if (owned.length == 1) {
    final card = owned.first;
    return Combo(
      kind: ComboKind.single,
      cards: owned,
      key: [card.rank, suitValue[card.suit]!],
      label: rankName(card.rank),
      bonusEach: 0,
      bonusName: null,
    );
  }

  if (owned.length == 2 || owned.length == 3) {
    if (owned.map((card) => card.rank).toSet().length != 1) return null;
    final kind = owned.length == 2 ? ComboKind.pair : ComboKind.triple;
    final rank = owned.first.rank;
    final name = rankName(rank);
    return Combo(
      kind: kind,
      cards: owned,
      key: [rank, _highestSuit(owned)],
      label: kind == ComboKind.pair ? "Pair of ${name}s" : "Triple ${name}s",
      bonusEach: 0,
      bonusName: null,
    );
  }

  if (owned.length != 5) return null;
  final groups = <int, List<PlayingCard>>{};
  for (final card in owned) {
    groups.putIfAbsent(card.rank, () => []).add(card);
  }
  final ordered = groups.values.toList()..sort((a, b) => b.length.compareTo(a.length));
  final straight = _straightInfo(owned, wrap);
  final flushSuit = _sameSuit(owned);

  if (straight != null && flushSuit != null) {
    if (_isRoyal(owned)) {
      return Combo(
        kind: ComboKind.royalFlush,
        cards: owned,
        key: [6, suitValue[flushSuit]!],
        label: "Royal flush (${suitName[flushSuit]})",
        bonusEach: 10,
        bonusName: "royal flush",
      );
    }
    final key = straightFlushSuitOnly
        ? [5, suitValue[flushSuit]!, straight.strength]
        : [5, straight.strength, suitValue[straight.top.suit]!];
    return Combo(
      kind: ComboKind.straightFlush,
      cards: owned,
      key: key,
      label: "Straight flush (${suitName[flushSuit]})",
      bonusEach: 8,
      bonusName: "straight flush",
    );
  }

  if (ordered.length == 2 && ordered[0].length == 4) {
    return Combo(
      kind: ComboKind.four,
      cards: owned,
      key: [4, ordered[0].first.rank],
      label: "Four ${rankName(ordered[0].first.rank)}s",
      bonusEach: 5,
      bonusName: "four of a kind",
    );
  }

  if (ordered.length == 2 && ordered[0].length == 3 && ordered[1].length == 2) {
    return Combo(
      kind: ComboKind.fullHouse,
      cards: owned,
      key: [3, ordered[0].first.rank],
      label: "Full house, ${rankName(ordered[0].first.rank)}s",
      bonusEach: 0,
      bonusName: null,
    );
  }

  if (flushSuit != null) {
    return Combo(
      kind: ComboKind.flush,
      cards: owned,
      key: [2, suitValue[flushSuit]!, ..._descending(owned)],
      label: "Flush (${suitName[flushSuit]})",
      bonusEach: 0,
      bonusName: null,
    );
  }

  if (straight != null) {
    return Combo(
      kind: ComboKind.straight,
      cards: owned,
      key: [1, straight.strength, suitValue[straight.top.suit]!],
      label: "Straight",
      bonusEach: 0,
      bonusName: null,
    );
  }
  return null;
}

String neededShape(ComboKind kind) {
  switch (family(kind)) {
    case "single":
      return "a single";
    case "pair":
      return "a pair";
    case "triple":
      return "a triple";
    default:
      return "a five-card hand";
  }
}

/// How many cards a play of this shape needs.
int cardsRequired(ComboKind kind) {
  switch (family(kind)) {
    case "single":
      return 1;
    case "pair":
      return 2;
    case "triple":
      return 3;
    default:
      return 5;
  }
}

bool _beatsIf(Combo defense, List<PlayingCard> cards, bool wrap) {
  final combo = identify(cards, wrap: wrap);
  return combo != null && beats(combo, defense);
}

bool _anyPick(List<List<PlayingCard>> groups, bool Function(List<PlayingCard> cards) visit) {
  final pick = <PlayingCard>[];
  bool walk(int index) {
    if (index == groups.length) return visit(pick);
    for (final card in groups[index]) {
      pick.add(card);
      if (walk(index + 1)) return true;
      pick.removeLast();
    }
    return false;
  }

  return groups.isNotEmpty && walk(0);
}

bool _anyCount(List<PlayingCard> cards, int count, bool Function(List<PlayingCard> cards) visit) {
  final pick = <PlayingCard>[];
  bool walk(int start) {
    if (pick.length == count) return visit(pick);
    for (var index = start; index <= cards.length - (count - pick.length); index++) {
      pick.add(cards[index]);
      if (walk(index + 1)) return true;
      pick.removeLast();
    }
    return false;
  }

  return cards.length >= count && walk(0);
}

/// True when some cards in [pool] form a combination that beats [defense].
/// What counts, and which play wins, comes from [identify] and [beats].
bool anyBeats(Combo defense, List<PlayingCard> pool, bool wrap) {
  final need = cardsRequired(defense.kind);
  if (pool.length < need) return false;
  final group = family(defense.kind);
  if (group == "single") {
    return pool.any((card) => _beatsIf(defense, [card], wrap));
  }
  final byRank = <int, List<PlayingCard>>{};
  for (final card in pool) {
    byRank.putIfAbsent(card.rank, () => []).add(card);
  }
  if (group == "pair" || group == "triple") {
    for (final cards in byRank.values) {
      if (cards.length < need) continue;
      if (_anyCount(cards, need, (choice) => _beatsIf(defense, choice, wrap))) return true;
    }
    return false;
  }

  final bySuit = <Suit, List<PlayingCard>>{};
  for (final card in pool) {
    bySuit.putIfAbsent(card.suit, () => []).add(card);
  }
  for (final suited in bySuit.values) {
    if (suited.length < 5) continue;
    if (_anyCount(suited, 5, (cards) => _beatsIf(defense, cards, wrap))) return true;
  }

  for (final cards in byRank.values) {
    if (cards.length < 4) continue;
    final four = cards.sublist(0, 4);
    for (final kicker in pool) {
      if (kicker.rank == four.first.rank) continue;
      if (_beatsIf(defense, [...four, kicker], wrap)) return true;
    }
  }

  final rankKeys = byRank.keys.toList();
  for (final tripleRank in rankKeys) {
    final tripleCards = byRank[tripleRank] ?? [];
    if (tripleCards.length < 3) continue;
    for (final pairRank in rankKeys) {
      if (pairRank == tripleRank) continue;
      final pairCards = byRank[pairRank] ?? [];
      if (pairCards.length < 2) continue;
      final found = _anyCount(
        tripleCards,
        3,
        (triple) => _anyCount(pairCards, 2, (pair) => _beatsIf(defense, [...triple, ...pair], wrap)),
      );
      if (found) return true;
    }
  }

  final chosen = <int>[];
  bool walkRanks(int start) {
    if (chosen.length == 5) {
      final groups = [for (final rank in chosen) byRank[rank] ?? []];
      final probe = identify([for (final cards in groups) cards.first], wrap: wrap);
      if (probe == null ||
          (probe.kind != ComboKind.straight &&
              probe.kind != ComboKind.straightFlush &&
              probe.kind != ComboKind.royalFlush)) {
        return false;
      }
      return _anyPick(groups, (cards) => _beatsIf(defense, cards, wrap));
    }
    for (var index = start; index <= rankKeys.length - (5 - chosen.length); index++) {
      chosen.add(rankKeys[index]);
      if (walkRanks(index + 1)) return true;
      chosen.removeLast();
    }
    return false;
  }

  return rankKeys.length >= 5 && walkRanks(0);
}
