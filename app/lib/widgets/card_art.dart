import "package:big_two/rules/cards.dart";
import "package:big_two/theme.dart";
import "package:flutter/material.dart";

bool isCourt(int rank) => rank == 11 || rank == 12 || rank == 13;

Color suitColor(Suit suit) => suit == Suit.hearts || suit == Suit.diamonds ? cardRed : ink;

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
