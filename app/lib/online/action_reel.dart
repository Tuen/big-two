import "package:big_two/online/snapshot.dart";

class ShownPlay {
  final int seat;
  final List<String> cards;
  final String label;
  final bool lastTrick;
  const ShownPlay({
    required this.seat,
    required this.cards,
    required this.label,
    required this.lastTrick,
  });

  ShownPlay asLastTrick() => ShownPlay(seat: seat, cards: cards, label: label, lastTrick: true);
}

/// Plays missed actions one at a time. The latest snapshot stays authoritative.
class ActionReel {
  String? handKey;
  int cursor = -1;
  final List<RecentAction> queue = [];
  ShownPlay? trick;
  ShownPlay? previous;

  void reset() {
    handKey = null;
    cursor = -1;
    queue.clear();
    trick = null;
    previous = null;
  }

  /// A new hand is shown as it is now. Later calls queue only unseen seqs.
  bool ingest(String handKey, List<RecentAction> recent) {
    final ordered = [...recent]..sort((a, b) => a.seq.compareTo(b.seq));
    if (this.handKey != handKey) {
      this.handKey = handKey;
      queue.clear();
      cursor = ordered.isEmpty ? -1 : ordered.last.seq;
      trick = null;
      previous = null;
      _applyAll(ordered);
      return true;
    }
    final unseen = ordered.where((event) => event.seq > cursor).toList();
    if (unseen.isEmpty) return false;
    cursor = unseen.last.seq;
    queue.addAll(unseen);
    return false;
  }

  RecentAction? pop() {
    if (queue.isEmpty) return null;
    final next = queue.removeAt(0);
    _apply(next);
    return next;
  }

  void flush() {
    while (queue.isNotEmpty) {
      _apply(queue.removeAt(0));
    }
  }

  /// When the server pile is empty, the last play becomes "Last trick".
  void align({int? seat, List<String> cards = const [], String label = ""}) {
    if (cards.isEmpty) {
      if (trick != null && trick!.cards.isNotEmpty) previous = trick!.asLastTrick();
      trick = null;
      return;
    }
    final same = trick != null && trick!.seat == seat && _same(trick!.cards, cards);
    if (!same && trick != null && trick!.cards.isNotEmpty) {
      previous = ShownPlay(seat: trick!.seat, cards: [...trick!.cards], label: trick!.label, lastTrick: false);
    }
    trick = ShownPlay(seat: seat ?? 0, cards: [...cards], label: label, lastTrick: false);
  }

  void _applyAll(List<RecentAction> actions) {
    for (final action in actions) {
      _apply(action);
    }
  }

  void _apply(RecentAction action) {
    if (action.kind != "play") return;
    if (trick != null && trick!.cards.isNotEmpty) {
      previous = ShownPlay(seat: trick!.seat, cards: [...trick!.cards], label: trick!.label, lastTrick: false);
    }
    trick = ShownPlay(seat: action.seat, cards: [...action.cards], label: action.label, lastTrick: false);
  }
}

List<int> countsHolding(List<int> finalCounts, List<RecentAction> notShown) {
  final counts = [...finalCounts];
  for (final action in notShown) {
    if (action.kind == "play" && action.seat >= 0 && action.seat < counts.length) {
      counts[action.seat] += action.cards.length;
    }
  }
  return counts;
}

bool _same(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String seatOrigin(int actor, int you) {
  switch ((actor - you + 4) % 4) {
    case 0:
      return "bottom";
    case 1:
      return "left";
    case 2:
      return "top";
    default:
      return "right";
  }
}
