import "dart:math" as math;

import "package:big_two/rules/cards.dart";
import "package:big_two/theme.dart";
import "package:big_two/widgets/playing_card_view.dart";
import "package:flutter/material.dart";

/// A short celebration. Tap it to skip. It does not post scores or deal the next hand.
class WinFlourish extends StatefulWidget {
  final String name;
  final List<PlayingCard> cards;
  final VoidCallback onDone;
  const WinFlourish({super.key, required this.name, required this.cards, required this.onDone});

  @override
  State<WinFlourish> createState() => _WinFlourishState();
}

class _WinFlourishState extends State<WinFlourish> with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  var _closed = false;
  late final List<_Bit> _bits;

  @override
  void initState() {
    super.initState();
    final random = math.Random(7);
    _bits = [for (var i = 0; i < 36; i++) _Bit(random)];
    _motion = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..forward();
    _motion.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  void _finish() {
    if (_closed) return;
    _closed = true;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return GestureDetector(
      key: const Key("win-flourish"),
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: AnimatedBuilder(
        animation: _motion,
        builder: (context, _) {
          final t = reduce ? 1.0 : Curves.easeOut.transform(_motion.value);
          final fade = reduce ? _motion.value : 1.0;
          return SizedBox(
            height: 250,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xF0062616),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: gold.withValues(alpha: 0.8)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (!reduce) CustomPaint(key: const Key("confetti"), painter: _ConfettiPainter(_bits, _motion.value)),
                    Opacity(
                      opacity: fade.clamp(0, 1),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "${widget.name} wins!",
                            key: const Key("win-banner"),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: gold, fontFamily: "Roboto"),
                          ),
                          const SizedBox(height: 8),
                          _fan(t),
                          const SizedBox(height: 6),
                          const Text("Tap to skip", style: TextStyle(color: Colors.white70, fontFamily: "Roboto")),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _fan(double t) {
    final cards = widget.cards;
    if (cards.isEmpty) return const SizedBox(height: 90);
    final width = cards.length >= 5 ? 52.0 : 72.0;
    return FittedBox(
      child: SizedBox(
        height: width * 1.55,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < cards.length; i++)
              Transform.rotate(
                angle: (cards.length <= 1 ? 0 : (i - (cards.length - 1) / 2) * 0.14) * t,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    boxShadow: [BoxShadow(color: gold.withValues(alpha: 0.75 * t), blurRadius: 16, spreadRadius: 1)],
                  ),
                  child: PlayingCardView(card: cards[i], width: width),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Bit {
  final double x;
  final double drift;
  final double spin;
  final Color color;
  final double size;
  _Bit(math.Random random)
      : x = random.nextDouble(),
        drift = random.nextDouble() * 0.2 - 0.1,
        spin = random.nextDouble() * 6,
        size = 6 + random.nextDouble() * 8,
        color = [gold, cardRed, Colors.white, const Color(0xFF7DCEA0)][random.nextInt(4)];
}

class _ConfettiPainter extends CustomPainter {
  final List<_Bit> bits;
  final double t;
  _ConfettiPainter(this.bits, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    for (final bit in bits) {
      final paint = Paint()..color = bit.color;
      final dx = (bit.x + bit.drift * t) * size.width;
      final dy = -12 + t * (size.height + 24) * (0.55 + bit.x * 0.55);
      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(bit.spin * t);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: bit.size, height: bit.size * 0.55), const Radius.circular(2)),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => oldDelegate.t != t;
}

/// Face-up cards still held when the hand ended.
class LeftoverCards extends StatelessWidget {
  final List<PlayingCard> cards;
  const LeftoverCards({super.key, required this.cards});

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    final shown = sortCards(cards, "rank");
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [for (final card in shown) PlayingCardView(card: card, width: 42)],
      ),
    );
  }
}
