enum Suit { diamonds, clubs, hearts, spades }

const suitValue = {
  Suit.diamonds: 1,
  Suit.clubs: 2,
  Suit.hearts: 3,
  Suit.spades: 4,
};

const suitName = {
  Suit.diamonds: "diamonds",
  Suit.clubs: "clubs",
  Suit.hearts: "hearts",
  Suit.spades: "spades",
};

const _rankChar = ["", "", "", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A", "2"];

String rankName(int rank) => rank == 10 ? "10" : _rankChar[rank];

class PlayingCard {
  final int rank;
  final Suit suit;
  const PlayingCard(this.rank, this.suit);

  String get id => formatCard(this);

  @override
  bool operator ==(Object other) => other is PlayingCard && other.rank == rank && other.suit == suit;

  @override
  int get hashCode => Object.hash(rank, suit);
}

Suit _suitFrom(String letter) {
  switch (letter) {
    case "D":
      return Suit.diamonds;
    case "C":
      return Suit.clubs;
    case "H":
      return Suit.hearts;
    case "S":
      return Suit.spades;
    default:
      throw FormatException("Bad suit: $letter");
  }
}

const _ranks = {
  "3": 3,
  "4": 4,
  "5": 5,
  "6": 6,
  "7": 7,
  "8": 8,
  "9": 9,
  "10": 10,
  "T": 10,
  "J": 11,
  "Q": 12,
  "K": 13,
  "A": 14,
  "2": 15,
};

PlayingCard parseCard(String text) {
  final raw = text.trim().toUpperCase();
  if (raw.length < 2) throw FormatException("Bad card: $text");
  final suit = _suitFrom(raw.substring(raw.length - 1));
  final rank = _ranks[raw.substring(0, raw.length - 1)];
  if (rank == null) throw FormatException("Bad rank: $text");
  return PlayingCard(rank, suit);
}

List<PlayingCard> parseCards(List<String> cards) => cards.map(parseCard).toList();

String formatCard(PlayingCard card) {
  final letter = switch (card.suit) {
    Suit.diamonds => "D",
    Suit.clubs => "C",
    Suit.hearts => "H",
    Suit.spades => "S",
  };
  return "${_rankChar[card.rank]}$letter";
}

List<PlayingCard> fullDeck() {
  final cards = <PlayingCard>[];
  for (final suit in Suit.values) {
    for (var rank = 3; rank <= 15; rank++) {
      cards.add(PlayingCard(rank, suit));
    }
  }
  return cards;
}

String deckCanonical(List<PlayingCard> deck) => deck.map(formatCard).join(",");

List<PlayingCard>? removeCards(List<PlayingCard> hand, List<PlayingCard> play) {
  final left = [...hand];
  for (final card in play) {
    final index = left.indexWhere((other) => other == card);
    if (index < 0) return null;
    left.removeAt(index);
  }
  return left;
}

List<PlayingCard> sortCards(List<PlayingCard> cards, String mode) {
  final copy = [...cards];
  copy.sort((a, b) {
    if (mode == "suit") {
      final suit = suitValue[a.suit]! - suitValue[b.suit]!;
      if (suit != 0) return suit;
      return a.rank.compareTo(b.rank);
    }
    if (a.rank != b.rank) return a.rank.compareTo(b.rank);
    return suitValue[a.suit]!.compareTo(suitValue[b.suit]!);
  });
  return copy;
}
