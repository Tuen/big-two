import "dart:convert";

import "package:crypto/crypto.dart";

import "cards.dart";

String sha256Hex(String text) => sha256.convert(utf8.encode(text)).toString();

class DeckCommitment {
  final String canonical;
  final String commitment;
  const DeckCommitment(this.canonical, this.commitment);
}

DeckCommitment commitDeck(List<PlayingCard> deck) {
  final canonical = deckCanonical(deck);
  return DeckCommitment(canonical, sha256Hex(canonical));
}
