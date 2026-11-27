import "dart:math" as math;

import "package:big_two/rules/cards.dart";
import "package:big_two/theme.dart";
import "package:flutter/material.dart";

bool isCourtRank(int rank) => rank >= 11 && rank <= 13;

class CardFacePainter extends CustomPainter {
  final PlayingCard card;
  const CardFacePainter(this.card);

  @override
  void paint(Canvas canvas, Size size) {
    final color = suitInk(card.suit);
    if (!isCourtRank(card.rank)) return;
    _court(canvas, size, color);
  }

  void _court(Canvas canvas, Size size, Color color) {
    final panel = Rect.fromLTRB(size.width * 0.2, size.height * 0.05,
        size.width * 0.8, size.height * 0.95);
    final radius = Radius.circular(size.width * 0.06);
    final plate = RRect.fromRectAndRadius(panel, radius);
    canvas.drawRRect(plate, Paint()..color = color.withValues(alpha: 0.07));
    canvas.drawRRect(
      plate,
      Paint()
        ..color = goldDeep
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, size.width * 0.018),
    );
    canvas.save();
    canvas.clipRRect(plate);
    _half(canvas, panel, color);
    canvas.save();
    canvas.translate(panel.center.dx, panel.center.dy);
    canvas.rotate(math.pi);
    canvas.translate(-panel.center.dx, -panel.center.dy);
    _half(canvas, panel, color);
    canvas.restore();
    canvas.restore();
  }

  void _half(Canvas canvas, Rect panel, Color color) {
    canvas.save();
    canvas.clipRect(
        Rect.fromLTRB(panel.left, panel.top, panel.right, panel.center.dy));
    final top = panel.top;
    final h = panel.height / 2;
    final w = panel.width;
    final cx = panel.center.dx;
    final robe = Path()
      ..moveTo(cx - w * 0.36, top + h)
      ..lineTo(cx - w * 0.22, top + h * 0.46)
      ..quadraticBezierTo(cx, top + h * 0.36, cx + w * 0.22, top + h * 0.46)
      ..lineTo(cx + w * 0.36, top + h)
      ..close();
    canvas.drawPath(robe, Paint()..color = color);
    canvas.drawLine(
      Offset(cx, top + h * 0.5),
      Offset(cx, top + h),
      Paint()
        ..color = gold
        ..strokeWidth = math.max(1, w * 0.035)
        ..strokeCap = StrokeCap.round,
    );
    final collar = Path()
      ..moveTo(cx - w * 0.18, top + h * 0.5)
      ..lineTo(cx, top + h * 0.68)
      ..lineTo(cx + w * 0.18, top + h * 0.5)
      ..close();
    canvas.drawPath(collar, Paint()..color = cardFace);
    final face = Rect.fromCenter(
        center: Offset(cx, top + h * 0.36), width: w * 0.36, height: h * 0.32);
    canvas.drawOval(face, Paint()..color = const Color(0xFFFFD7B0));
    final eye = math.max(0.7, w * 0.02);
    final eyeY = face.center.dy - face.height * 0.02;
    canvas.drawCircle(Offset(face.center.dx - face.width * 0.18, eyeY), eye,
        Paint()..color = ink);
    canvas.drawCircle(Offset(face.center.dx + face.width * 0.18, eyeY), eye,
        Paint()..color = ink);
    canvas.drawLine(
      Offset(face.center.dx, face.center.dy + face.height * 0.08),
      Offset(face.center.dx, face.center.dy + face.height * 0.22),
      Paint()
        ..color = const Color(0xFF8A5A3A)
        ..strokeWidth = math.max(0.6, w * 0.015)
        ..strokeCap = StrokeCap.round,
    );
    _hat(
        canvas,
        Rect.fromCenter(
            center: Offset(cx, top + h * 0.16),
            width: w * 0.55,
            height: h * 0.24),
        color);
    paintSuit(
      canvas,
      Rect.fromCenter(
          center: Offset(cx + w * 0.16, top + h * 0.78),
          width: w * 0.2,
          height: w * 0.2),
      card.suit,
      cardFace,
    );
    canvas.restore();
  }

  void _hat(Canvas canvas, Rect box, Color color) {
    if (card.rank == 13) {
      final crown = Path()
        ..moveTo(box.left, box.bottom)
        ..lineTo(box.left + box.width * 0.08, box.top + box.height * 0.45)
        ..lineTo(box.left + box.width * 0.28, box.bottom - box.height * 0.08)
        ..lineTo(box.center.dx, box.top)
        ..lineTo(box.right - box.width * 0.28, box.bottom - box.height * 0.08)
        ..lineTo(box.right - box.width * 0.08, box.top + box.height * 0.45)
        ..lineTo(box.right, box.bottom)
        ..close();
      canvas.drawPath(crown, Paint()..color = gold);
      canvas.drawCircle(Offset(box.center.dx, box.top + box.height * 0.42),
          box.width * 0.055, Paint()..color = color);
      return;
    }
    if (card.rank == 12) {
      final tiara = Path()
        ..moveTo(box.left + box.width * 0.08, box.bottom)
        ..quadraticBezierTo(
            box.center.dx, box.top, box.right - box.width * 0.08, box.bottom);
      canvas.drawPath(
        tiara,
        Paint()
          ..color = gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.4, box.width * 0.07)
          ..strokeCap = StrokeCap.round,
      );
      for (final dx in [-0.22, 0.0, 0.22]) {
        canvas.drawCircle(Offset(box.center.dx + box.width * dx, box.center.dy),
            box.width * 0.055, Paint()..color = color);
      }
      return;
    }
    canvas.save();
    canvas.translate(box.center.dx, box.center.dy);
    canvas.rotate(-0.35);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset.zero,
          width: box.width * 0.9,
          height: box.height * 0.72),
      Paint()..color = const Color(0xFF1B3A6B),
    );
    canvas.restore();
    final feather = Path()
      ..moveTo(box.right - box.width * 0.12, box.center.dy)
      ..quadraticBezierTo(box.right + box.width * 0.05, box.top,
          box.right - box.width * 0.02, box.top - box.height * 0.25);
    canvas.drawPath(
      feather,
      Paint()
        ..color = gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.1, box.width * 0.045)
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(CardFacePainter oldDelegate) => oldDelegate.card != card;
}

/// Traditional faces: spades and clubs black, hearts and diamonds red.
Color suitInk(Suit suit) {
  final red = suit == Suit.hearts || suit == Suit.diamonds;
  return red ? cardRed : ink;
}

void paintSuit(Canvas canvas, Rect rect, Suit suit, Color color) {
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.fill;
  if (suit == Suit.clubs) {
    _club(canvas, rect, paint);
    return;
  }
  if (suit == Suit.hearts) {
    _heartPaint(canvas, rect, paint);
    return;
  }
  canvas.save();
  canvas.translate(rect.left, rect.top);
  canvas.scale(rect.width, rect.height);
  canvas.drawPath(suit == Suit.diamonds ? _diamond : _spade, paint);
  if (suit == Suit.spades) canvas.drawPath(_spadeStem, paint);
  canvas.restore();
}

void _heartPaint(Canvas canvas, Rect rect, Paint paint) {
  final r = rect.width * 0.34;
  canvas.drawCircle(Offset(rect.left + rect.width * 0.3, rect.top + rect.height * 0.32), r, paint);
  canvas.drawCircle(Offset(rect.left + rect.width * 0.7, rect.top + rect.height * 0.32), r, paint);
  final body = Path()
    ..moveTo(rect.left + rect.width * 0.02, rect.top + rect.height * 0.4)
    ..lineTo(rect.center.dx, rect.bottom)
    ..lineTo(rect.right - rect.width * 0.02, rect.top + rect.height * 0.4)
    ..close();
  canvas.drawPath(body, paint);
}

void _club(Canvas canvas, Rect rect, Paint paint) {
  final r = rect.width * 0.32;
  canvas.drawCircle(Offset(rect.center.dx, rect.top + rect.height * 0.26), r, paint);
  canvas.drawCircle(Offset(rect.left + rect.width * 0.28, rect.top + rect.height * 0.5), r, paint);
  canvas.drawCircle(Offset(rect.right - rect.width * 0.28, rect.top + rect.height * 0.5), r, paint);
  final stem = Path()
    ..moveTo(rect.center.dx - rect.width * 0.1, rect.top + rect.height * 0.55)
    ..lineTo(rect.center.dx + rect.width * 0.1, rect.top + rect.height * 0.55)
    ..lineTo(rect.center.dx + rect.width * 0.22, rect.bottom)
    ..lineTo(rect.center.dx - rect.width * 0.22, rect.bottom)
    ..close();
  canvas.drawPath(stem, paint);
}

final Path _diamond = Path()
  ..moveTo(0.5, 0.0)
  ..lineTo(1.0, 0.5)
  ..lineTo(0.5, 1.0)
  ..lineTo(0.0, 0.5)
  ..close();

final Path _spade = Path()
  ..moveTo(0.5, 0.0)
  ..cubicTo(0.98, 0.34, 0.96, 0.62, 0.72, 0.7)
  ..cubicTo(0.6, 0.76, 0.54, 0.64, 0.5, 0.52)
  ..cubicTo(0.46, 0.64, 0.4, 0.76, 0.28, 0.7)
  ..cubicTo(0.04, 0.62, 0.02, 0.34, 0.5, 0.0)
  ..close();

final Path _spadeStem = Path()
  ..moveTo(0.42, 0.7)
  ..lineTo(0.58, 0.7)
  ..lineTo(0.68, 0.98)
  ..lineTo(0.32, 0.98)
  ..close();
