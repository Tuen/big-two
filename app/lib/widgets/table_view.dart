import "package:big_two/rules/cards.dart";
import "package:big_two/theme.dart";
import "package:big_two/widgets/playing_card_view.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";

class SeatSpot {
  final String name;
  final int cardsLeft;
  final int total;
  final bool turn;
  final bool connected;
  const SeatSpot({
    required this.name,
    required this.cardsLeft,
    required this.total,
    required this.turn,
    this.connected = true,
  });
}

class TableView extends StatelessWidget {
  final SeatSpot bottom;
  final SeatSpot left;
  final SeatSpot top;
  final SeatSpot right;
  final List<PlayingCard> hand;
  final Set<String> selected;
  final List<PlayingCard> trick;
  final String? trickLabel;
  final String? trickPlayer;
  final bool canPlay;
  final bool canPass;
  final String passLabel;
  final String? reason;
  final String banner;
  final VoidCallback onPlay;
  final VoidCallback onPass;
  final VoidCallback onSortRank;
  final VoidCallback onSortSuit;
  final VoidCallback onScores;
  final ValueChanged<String> onToggle;
  final void Function(int from, int to) onReorder;

  const TableView({
    super.key,
    required this.bottom,
    required this.left,
    required this.top,
    required this.right,
    required this.hand,
    required this.selected,
    required this.trick,
    required this.trickLabel,
    required this.trickPlayer,
    required this.canPlay,
    required this.canPass,
    required this.passLabel,
    required this.reason,
    required this.banner,
    required this.onPlay,
    required this.onPass,
    required this.onSortRank,
    required this.onSortSuit,
    required this.onScores,
    required this.onToggle,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): canPlay ? onPlay : () {},
        const SingleActivator(LogicalKeyboardKey.numpadEnter): canPlay ? onPlay : () {},
        const SingleActivator(LogicalKeyboardKey.keyP): canPass ? onPass : () {},
      },
      child: Focus(
        autofocus: true,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(colors: [felt, feltDeep], radius: 1.1),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                return Column(
                  children: [
                    _topBar(context),
                    Expanded(child: wide ? _wide() : _portrait()),
                    if (banner.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Text(banner, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      ),
                    _hand(constraints.maxWidth),
                    if (reason != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(reason!, style: const TextStyle(color: gold, fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Row(
                        children: [
                          Expanded(child: OutlinedButton(onPressed: canPass ? onPass : null, child: Text(passLabel))),
                          const SizedBox(width: 12),
                          Expanded(child: FilledButton(onPressed: canPlay ? onPlay : null, child: const Text("Play"))),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: "Back",
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const Spacer(),
          TextButton(onPressed: onSortRank, child: const Text("Sort rank", style: TextStyle(color: Colors.white, fontSize: 16))),
          TextButton(onPressed: onSortSuit, child: const Text("Sort suit", style: TextStyle(color: Colors.white, fontSize: 16))),
          TextButton(onPressed: onScores, child: const Text("Scores", style: TextStyle(color: gold, fontSize: 18, fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }

  Widget _portrait() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(child: _plaque(left)),
              Expanded(child: _plaque(top)),
              Expanded(child: _plaque(right)),
            ],
          ),
        ),
        Expanded(child: _trick()),
      ],
    );
  }

  Widget _wide() {
    return Row(
      children: [
        SizedBox(width: 220, child: _plaque(left)),
        Expanded(
          child: Column(
            children: [
              _plaque(top),
              Expanded(child: _trick()),
            ],
          ),
        ),
        SizedBox(width: 220, child: _plaque(right)),
      ],
    );
  }

  Widget _plaque(SeatSpot seat) {
    return Container(
      margin: const EdgeInsets.all(6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: seat.turn ? const Color(0xFF145C34) : const Color(0x66000000),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: seat.turn ? gold : Colors.white24, width: seat.turn ? 3 : 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(seat.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text("${seat.cardsLeft} cards", style: const TextStyle(fontSize: 16)),
          Text("${seat.total} pts", style: const TextStyle(color: Colors.white70)),
          if (!seat.connected) const Text("Away", style: TextStyle(color: gold, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _trick() {
    return Center(
      child: trick.isEmpty
          ? const Text("Lead any combination", style: TextStyle(fontSize: 20, color: Colors.white70))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("${trickPlayer ?? ""}  ·  ${trickLabel ?? ""}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  children: [for (final card in trick) PlayingCardView(card: card, width: 78)],
                ),
              ],
            ),
    );
  }

  Widget _hand(double width) {
    final cardWidth = width >= 900 ? 96.0 : 74.0;
    final gap = hand.length <= 1 ? cardWidth : ((width - 24 - cardWidth) / (hand.length - 1)).clamp(28.0, cardWidth * 0.62);
    final height = cardWidth * 1.42 + 28;
    return SizedBox(
      height: height,
      width: width,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var index = 0; index < hand.length; index++)
            Positioned(
              left: 12 + gap * index,
              bottom: 0,
              child: _FanCard(
                card: hand[index],
                selected: selected.contains(hand[index].id),
                width: cardWidth,
                onTap: () => onToggle(hand[index].id),
                onMove: (delta) {
                  if (gap <= 0) return;
                  final target = (index + (delta / gap).round()).clamp(0, hand.length - 1);
                  if (target != index) onReorder(index, target);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _FanCard extends StatefulWidget {
  final PlayingCard card;
  final bool selected;
  final double width;
  final VoidCallback onTap;
  final ValueChanged<double> onMove;
  const _FanCard({
    required this.card,
    required this.selected,
    required this.width,
    required this.onTap,
    required this.onMove,
  });

  @override
  State<_FanCard> createState() => _FanCardState();
}

class _FanCardState extends State<_FanCard> {
  double _moved = 0;

  @override
  Widget build(BuildContext context) {
    return PlayingCardView(
      card: widget.card,
      selected: widget.selected,
      width: widget.width,
      onTap: widget.onTap,
      onDragStart: (_) => _moved = 0,
      onDragUpdate: (details) => _moved += details.primaryDelta ?? 0,
      onDragEnd: (_) {
        widget.onMove(_moved);
        _moved = 0;
      },
    );
  }
}
