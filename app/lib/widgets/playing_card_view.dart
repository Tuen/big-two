import "package:big_two/rules/cards.dart";
import "package:big_two/theme.dart";
import "package:flutter/material.dart";

class PlayingCardView extends StatelessWidget {
  final PlayingCard? card;
  final bool selected;
  final double width;
  final VoidCallback? onTap;
  final GestureDragStartCallback? onDragStart;
  final GestureDragUpdateCallback? onDragUpdate;
  final GestureDragEndCallback? onDragEnd;

  const PlayingCardView({
    super.key,
    required this.card,
    this.selected = false,
    this.width = 72,
    this.onTap,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final height = width * 1.42;
    final face = card;
    final label = face == null ? "Card back" : "${rankName(face.rank)} of ${suitName[face.suit]}";
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: selected ? "$label, selected" : label,
      child: GestureDetector(
        onTap: onTap,
        onHorizontalDragStart: onDragStart,
        onHorizontalDragUpdate: onDragUpdate,
        onHorizontalDragEnd: onDragEnd,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          transform: Matrix4.translationValues(0, selected ? -18 : 0, 0),
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: face == null ? const Color(0xFF1E4D8C) : cardFace,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? gold : const Color(0xFF2A2A2A), width: selected ? 4 : 1.5),
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 3))],
          ),
          child: face == null ? _back() : _face(context, face),
        ),
      ),
    );
  }

  Widget _face(BuildContext context, PlayingCard face) {
    final red = face.suit == Suit.hearts || face.suit == Suit.diamonds;
    final color = red ? cardRed : ink;
    final suit = switch (face.suit) {
      Suit.diamonds => "♦",
      Suit.clubs => "♣",
      Suit.hearts => "♥",
      Suit.spades => "♠",
    };
    final rank = rankName(face.rank);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 3, 5, 3),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final corner = constraints.maxHeight * 0.2;
            final small = constraints.maxHeight * 0.15;
            Widget mark(String text, double size, Alignment alignment) {
              return SizedBox(
                height: size,
                width: double.infinity,
                child: FittedBox(
                  alignment: alignment,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    text,
                    style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w800, height: 1),
                  ),
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                mark(rank, corner, Alignment.centerLeft),
                mark(suit, small, Alignment.centerLeft),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: FittedBox(
                      child: Text(suit, style: TextStyle(color: color, fontSize: 48, height: 1)),
                    ),
                  ),
                ),
                mark(rank, corner, Alignment.centerRight),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _back() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: gold, width: 2),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}
