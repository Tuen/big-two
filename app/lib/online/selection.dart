/// Play stays grey until it is your turn and the selected cards are a legal play.
bool canPressPlay({required bool yourTurn, required bool paused, required String? issue}) {
  return yourTurn && !paused && issue == null;
}

/// Cards a player taps stay selected across polls, ticks, and turn changes.
///
/// The selection is a set of card ids held by the seat, not by the current
/// turn. A new snapshot drops only ids that are no longer in [hand]. Card ids
/// are reused every deal, so a new hand drops the whole set. A play the server
/// accepted drops it too. Tapping a card off is the caller's job. The set is
/// never sent to the other seats.
Set<String> retainSelection({
  required Set<String> selected,
  required Iterable<String> hand,
  required bool newHand,
  required bool played,
}) {
  if (newHand || played) return <String>{};
  final still = Set<String>.of(hand);
  return {for (final id in selected) if (still.contains(id)) id};
}
