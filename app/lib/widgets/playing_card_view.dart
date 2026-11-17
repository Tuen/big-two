import "dart:math" as math;

import "package:big_two/rules/cards.dart";
import "package:big_two/theme.dart";
import "package:big_two/widgets/card_art.dart";
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
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cornerW = constraints.maxWidth * 0.30;
          final cornerH = constraints.maxHeight * 0.28;
          return Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(constraints.maxWidth * 0.08, cornerH * 0.85, constraints.maxWidth * 0.08, cornerH * 0.85),
                child: isCourt(face.rank) ? CourtFace(card: face) : _pips(face),
              ),
              Positioned(left: 3, top: 2, width: cornerW, height: cornerH, child: CornerIndex(card: face)),
              Positioned(
                right: 3,
                bottom: 2,
                width: cornerW,
                height: cornerH,
                child: Transform.rotate(angle: math.pi, child: CornerIndex(card: face)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _pips(PlayingCard face) {
    final spots = pipSpots(face.rank);
    return LayoutBuilder(
      builder: (context, constraints) {
        final pip = constraints.maxHeight / (spots.length <= 3 ? 3.2 : 5.4);
        return Stack(
          children: [
            for (final spot in spots)
              Align(
                alignment: Alignment((spot.x - 0.5) * 2, (spot.y - 0.5) * 2),
                child: SizedBox(
                  width: pip,
                  height: pip,
                  child: PipMark(suit: face.suit, invert: spot.invert),
                ),
              ),
          ],
        );
      },
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
