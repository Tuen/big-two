import "package:big_two/rules/cards.dart";
import "package:big_two/theme.dart";
import "package:flutter/material.dart";

/// How many suit pips a number card shows. Ace is one, a two is two.
/// Jack, queen, and king are illustrated faces and have no pips.
int pipCount(int rank) {
  if (rank >= 3 && rank <= 10) return rank;
  if (rank == 14) return 1;
  if (rank == 15) return 2;
  return 0;
}

bool isCourt(int rank) => rank == 11 || rank == 12 || rank == 13;

class PipSpot {
  final double x;
  final double y;
  final bool invert;
  const PipSpot(this.x, this.y, {this.invert = false});
}

/// Standard pip places, from the top of the card. Lower pips are turned over.
List<PipSpot> pipSpots(int rank) {
  const left = 0.30;
  const right = 0.70;
  const top = 0.16;
  const upper = 0.34;
  const mid = 0.50;
  const lower = 0.66;
  const bottom = 0.84;
  PipSpot up(double x, double y) => PipSpot(x, y);
  PipSpot down(double x, double y) => PipSpot(x, y, invert: true);
  switch (pipCount(rank)) {
    case 1:
      return const [PipSpot(0.5, 0.5)];
    case 2:
      return [up(0.5, 0.22), down(0.5, 0.78)];
    case 3:
      return [up(0.5, 0.20), up(0.5, 0.50), down(0.5, 0.80)];
    case 4:
      return [up(left, top), up(right, top), down(left, bottom), down(right, bottom)];
    case 5:
      return [up(left, top), up(right, top), up(0.5, mid), down(left, bottom), down(right, bottom)];
    case 6:
      return [up(left, top), up(right, top), up(left, mid), up(right, mid), down(left, bottom), down(right, bottom)];
    case 7:
      return [
        up(left, top),
        up(right, top),
        up(0.5, 0.33),
        up(left, mid),
        up(right, mid),
        down(left, bottom),
        down(right, bottom),
      ];
    case 8:
      return [
        up(left, top),
        up(right, top),
        up(0.5, upper),
        up(left, mid),
        up(right, mid),
        down(0.5, lower),
        down(left, bottom),
        down(right, bottom),
      ];
    case 9:
      return [
        up(left, 0.14),
        up(right, 0.14),
        up(left, 0.36),
        up(right, 0.36),
        up(0.5, mid),
        down(left, 0.64),
        down(right, 0.64),
        down(left, 0.86),
        down(right, 0.86),
      ];
    case 10:
      return [
        up(left, 0.13),
        up(right, 0.13),
        up(0.5, 0.27),
        up(left, 0.38),
        up(right, 0.38),
        down(left, 0.62),
        down(right, 0.62),
        down(0.5, 0.73),
        down(left, 0.87),
        down(right, 0.87),
      ];
    default:
      return const [];
  }
}

Color suitColor(Suit suit) => suit == Suit.hearts || suit == Suit.diamonds ? cardRed : ink;

/// One suit pip, drawn as a path. Count these to check a layout.
class PipMark extends StatelessWidget {
  final Suit suit;
  final bool invert;
  const PipMark({super.key, required this.suit, this.invert = false});

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(painter: SuitPipPainter(suit));
    if (!invert) return mark;
    return Transform.rotate(angle: 3.1416, child: mark);
  }
}

class SuitPipPainter extends CustomPainter {
  final Suit suit;
  SuitPipPainter(this.suit);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = suitColor(suit);
    canvas.drawPath(suitPath(suit, size), paint);
  }

  @override
  bool shouldRepaint(covariant SuitPipPainter oldDelegate) => oldDelegate.suit != suit;
}

Path suitPath(Suit suit, Size size) {
  switch (suit) {
    case Suit.hearts:
      return _heart(size);
    case Suit.diamonds:
      return _diamond(size);
    case Suit.clubs:
      return _club(size);
    case Suit.spades:
      return _spade(size);
  }
}

Path _heart(Size size) {
  final w = size.width;
  final h = size.height;
  return Path()
    ..moveTo(w * 0.50, h * 0.90)
    ..cubicTo(w * -0.05, h * 0.48, w * 0.18, h * 0.02, w * 0.50, h * 0.30)
    ..cubicTo(w * 0.82, h * 0.02, w * 1.05, h * 0.48, w * 0.50, h * 0.90)
    ..close();
}

Path _diamond(Size size) {
  final w = size.width;
  final h = size.height;
  return Path()
    ..moveTo(w * 0.50, h * 0.02)
    ..lineTo(w * 0.94, h * 0.50)
    ..lineTo(w * 0.50, h * 0.98)
    ..lineTo(w * 0.06, h * 0.50)
    ..close();
}

Path _club(Size size) {
  final w = size.width;
  final h = size.height;
  final path = Path()
    ..addOval(Rect.fromCircle(center: Offset(w * 0.50, h * 0.30), radius: w * 0.20))
    ..addOval(Rect.fromCircle(center: Offset(w * 0.30, h * 0.50), radius: w * 0.20))
    ..addOval(Rect.fromCircle(center: Offset(w * 0.70, h * 0.50), radius: w * 0.20));
  path
    ..moveTo(w * 0.44, h * 0.52)
    ..lineTo(w * 0.36, h * 0.92)
    ..lineTo(w * 0.64, h * 0.92)
    ..lineTo(w * 0.56, h * 0.52)
    ..close();
  return path;
}

Path _spade(Size size) {
  final w = size.width;
  final h = size.height;
  final path = Path()
    ..moveTo(w * 0.50, h * 0.04)
    ..cubicTo(w * 1.08, h * 0.46, w * 0.82, h * 0.70, w * 0.50, h * 0.58)
    ..cubicTo(w * 0.18, h * 0.70, w * -0.08, h * 0.46, w * 0.50, h * 0.04)
    ..close();
  path
    ..moveTo(w * 0.44, h * 0.56)
    ..lineTo(w * 0.36, h * 0.94)
    ..lineTo(w * 0.64, h * 0.94)
    ..lineTo(w * 0.56, h * 0.56)
    ..close();
  return path;
}

class CornerIndex extends StatelessWidget {
  final PlayingCard card;
  const CornerIndex({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    final color = suitColor(card.suit);
    return FittedBox(
      alignment: Alignment.topLeft,
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            rankName(card.rank),
            style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800, height: 0.9, fontFamily: "Roboto"),
          ),
          SizedBox(
            width: 16,
            height: 16,
            child: CustomPaint(painter: SuitPipPainter(card.suit)),
          ),
        ],
      ),
    );
  }
}

/// Original court drawing: jack, queen, or king. No external image.
class CourtFace extends StatelessWidget {
  final PlayingCard card;
  const CourtFace({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CourtPainter(card),
      child: const SizedBox.expand(),
    );
  }
}

class _CourtPainter extends CustomPainter {
  final PlayingCard card;
  _CourtPainter(this.card);

  @override
  void paint(Canvas canvas, Size size) {
    final color = suitColor(card.suit);
    final inkPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.035
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = color.withValues(alpha: 0.14);
    final goldPaint = Paint()..color = goldDeep;
    final frame = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.shortestSide * 0.12));
    canvas.drawRRect(frame, fill);
    canvas.drawRRect(frame, inkPaint);

    final face = Rect.fromCenter(
      center: Offset(size.width * 0.5, size.height * 0.48),
      width: size.width * 0.46,
      height: size.height * 0.34,
    );
    canvas.drawOval(face, Paint()..color = const Color(0xFFFFE8C7));
    canvas.drawOval(face, inkPaint);

    final eye = size.shortestSide * 0.035;
    canvas.drawCircle(Offset(face.center.dx - face.width * 0.16, face.center.dy - face.height * 0.05), eye, Paint()..color = ink);
    canvas.drawCircle(Offset(face.center.dx + face.width * 0.16, face.center.dy - face.height * 0.05), eye, Paint()..color = ink);

    if (card.rank == 13) {
      _crown(canvas, size, goldPaint, points: 3);
      final beard = Path()
        ..moveTo(face.left + face.width * 0.22, face.bottom - face.height * 0.18)
        ..quadraticBezierTo(face.center.dx, face.bottom + face.height * 0.35, face.right - face.width * 0.22, face.bottom - face.height * 0.18);
      canvas.drawPath(beard, Paint()..color = color);
    } else if (card.rank == 12) {
      _crown(canvas, size, goldPaint, points: 1);
      final hair = Path()
        ..moveTo(face.left, face.center.dy)
        ..quadraticBezierTo(face.left - size.width * 0.04, face.bottom, face.center.dx, face.bottom + size.height * 0.02)
        ..quadraticBezierTo(face.right + size.width * 0.04, face.bottom, face.right, face.center.dy);
      canvas.drawPath(hair, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = inkPaint.strokeWidth);
    } else {
      final cap = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(size.width * 0.5, size.height * 0.22), width: size.width * 0.62, height: size.height * 0.12),
        Radius.circular(size.shortestSide * 0.08),
      );
      canvas.drawRRect(cap, goldPaint);
      final feather = Path()
        ..moveTo(size.width * 0.72, size.height * 0.22)
        ..quadraticBezierTo(size.width * 0.95, size.height * 0.05, size.width * 0.78, size.height * 0.34);
      canvas.drawPath(feather, inkPaint);
    }

    final letter = card.rank == 11 ? "J" : card.rank == 12 ? "Q" : "K";
    final painter = TextPainter(
      text: TextSpan(
        text: letter,
        style: TextStyle(color: color.withValues(alpha: 0.35), fontSize: size.height * 0.28, fontWeight: FontWeight.w800, fontFamily: "Roboto"),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset((size.width - painter.width) / 2, size.height * 0.62));
  }

  void _crown(Canvas canvas, Size size, Paint paint, {required int points}) {
    final path = Path()..moveTo(size.width * 0.22, size.height * 0.28);
    if (points == 1) {
      path
        ..quadraticBezierTo(size.width * 0.5, size.height * 0.02, size.width * 0.78, size.height * 0.28)
        ..close();
    } else {
      path
        ..lineTo(size.width * 0.32, size.height * 0.12)
        ..lineTo(size.width * 0.5, size.height * 0.28)
        ..lineTo(size.width * 0.68, size.height * 0.10)
        ..lineTo(size.width * 0.78, size.height * 0.28)
        ..close();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CourtPainter oldDelegate) => oldDelegate.card != card;
}
