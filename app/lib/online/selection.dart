/// Play stays grey until it is your turn and the selected cards are a legal play.
bool canPressPlay({required bool yourTurn, required bool paused, required String? issue}) {
  return yourTurn && !paused && issue == null;
}

/// A private selection is dropped when the trick is won or the hand ends.
/// It is never included in what other players are sent.
bool dropSelection({
  required bool newHand,
  required bool cardsChanged,
  required bool trickWon,
  required bool handEnded,
}) {
  return newHand || cardsChanged || trickWon || handEnded;
}
