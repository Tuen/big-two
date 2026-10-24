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
  final bool wheel;
  const _StraightInfo(this.strength, this.top, this.wheel);
}

PlayingCard _cardWithRank(List<PlayingCard> cards, int rank) => cards.firstWhere((card) => card.rank == rank);

int _highestSuit(List<PlayingCard> cards) => cards.map((card) => suitValue[card.suit]!).reduce((a, b) => a > b ? a : b);

/// Wheel A-2-3-4-5 is the lowest straight. 2 is high otherwise, so J-Q-K-A-2 is the highest
/// natural straight. Wrap adds 2-3-4-5-6, then Q-K-A-2-3, then K-A-2-3-4 above that.
_StraightInfo? _straightInfo(List<PlayingCard> cards, bool wrap) {
  if (cards.length != 5) return null;
  final ranks = cards.map((card) => card.rank).toList();
  if (ranks.toSet().length != 5) return null;
  bool has(int rank) => ranks.contains(rank);
  if ([14, 15, 3, 4, 5].every(has)) {
    return _StraightInfo(0, _cardWithRank(cards, 5), true);
  }
  final sorted = [...ranks]..sort();
  final consecutive = List.generate(5, (index) => index == 0 || sorted[index] == sorted[index - 1] + 1).every((ok) => ok);
  if (consecutive && sorted[4] - sorted[0] == 4) {
    return _StraightInfo(sorted[4] - 5, _cardWithRank(cards, sorted[4]), false);
  }
  if (!wrap) return null;
  const wrapped = [
    [15, 3, 4, 5, 6, 1],
    [12, 13, 14, 15, 3, 11],
    [13, 14, 15, 3, 4, 12],
  ];
  for (final pattern in wrapped) {
    if (pattern.take(5).every(has)) {
      return _StraightInfo(pattern[5], _cardWithRank(cards, 15), false);
    }
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
      label: straight.wheel ? "Straight (A-2-3-4-5)" : "Straight",
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
