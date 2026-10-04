import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Seven-segment LED digits, like an arena scoreboard. Unlit segments glow
/// faintly, the way real LED panels do.
class LedNumber extends StatelessWidget {
  const LedNumber({
    super.key,
    required this.value,
    this.digits = 2,
    this.height = 44,
    this.color = Brand.led,
  });

  final int value;
  final int digits;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = value.clamp(0, 999).toString().padLeft(digits, '0');
    final digitWidth = height * 0.56;
    final gap = height * 0.14;
    return Semantics(
      label: '$value',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        // Flash brighter for a moment whenever the number changes.
        key: ValueKey(value),
        tween: Tween(begin: 1, end: 0),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        builder: (context, flash, _) => CustomPaint(
          size: Size(
            digitWidth * text.length + gap * (text.length - 1),
            height,
          ),
          painter: _LedPainter(
            text: text,
            color: color,
            digitWidth: digitWidth,
            gap: gap,
            flash: flash,
          ),
        ),
      ),
    );
  }
}

class _LedPainter extends CustomPainter {
  _LedPainter({
    required this.text,
    required this.color,
    required this.digitWidth,
    required this.gap,
    required this.flash,
  });

  final String text;
  final Color color;
  final double digitWidth;
  final double gap;
  final double flash;

  // Segments: a b c d e f g
  static const _map = <String, int>{
    '0': 0x3F, // abcdef
    '1': 0x06, // bc
    '2': 0x5B, // abdeg
    '3': 0x4F, // abcdg
    '4': 0x66, // bcfg
    '5': 0x6D, // acdfg
    '6': 0x7D, // acdefg
    '7': 0x07, // abc
    '8': 0x7F,
    '9': 0x6F, // abcdfg
  };

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final t = h * 0.12; // segment thickness
    final w = digitWidth;
    final lit = Paint()..color = color;
    final glow = Paint()
      ..color = color.withValues(alpha: 0.55 + 0.35 * flash)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * (0.06 + 0.06 * flash));
    final ghost = Paint()..color = color.withValues(alpha: 0.09);

    canvas.save();
    // Slight forward lean, like a real scoreboard.
    canvas.translate(h * 0.06, 0);
    canvas.transform(
      Matrix4.skewX(-0.08).storage,
    );

    for (var i = 0; i < text.length; i++) {
      final mask = _map[text[i]] ?? 0;
      final ox = i * (w + gap);
      final segs = _segments(ox, w, h, t);
      for (var s = 0; s < 7; s++) {
        final on = mask & (1 << s) != 0;
        if (on) {
          canvas.drawPath(segs[s], glow);
          canvas.drawPath(segs[s], lit);
        } else {
          canvas.drawPath(segs[s], ghost);
        }
      }
    }
    canvas.restore();
  }

  List<Path> _segments(double x, double w, double h, double t) {
    final g = t * 0.18; // gap between segments
    final mid = h / 2;
    Path horizontal(double y) {
      final l = x + g + t / 2;
      final r = x + w - g - t / 2;
      return Path()
        ..moveTo(l, y)
        ..lineTo(l + t / 2, y - t / 2)
        ..lineTo(r - t / 2, y - t / 2)
        ..lineTo(r, y)
        ..lineTo(r - t / 2, y + t / 2)
        ..lineTo(l + t / 2, y + t / 2)
        ..close();
    }

    Path vertical(double cx, double top, double bottom) {
      final tp = top + g;
      final bt = bottom - g;
      return Path()
        ..moveTo(cx, tp)
        ..lineTo(cx + t / 2, tp + t / 2)
        ..lineTo(cx + t / 2, bt - t / 2)
        ..lineTo(cx, bt)
        ..lineTo(cx - t / 2, bt - t / 2)
        ..lineTo(cx - t / 2, tp + t / 2)
        ..close();
    }

    final top = t / 2;
    final bottom = h - t / 2;
    final left = x + t / 2;
    final right = x + w - t / 2;
    return [
      horizontal(top), // a
      vertical(right, top, mid), // b
      vertical(right, mid, bottom), // c
      horizontal(bottom), // d
      vertical(left, mid, bottom), // e
      vertical(left, top, mid), // f
      horizontal(mid), // g
    ];
  }

  @override
  bool shouldRepaint(_LedPainter old) =>
      old.text != text || old.color != color || old.flash != flash;
}

/// The roll-call scoreboard: HERE · LATE · AWAY.
class Scoreboard extends StatelessWidget {
  const Scoreboard({
    super.key,
    required this.here,
    required this.late,
    required this.away,
    required this.excused,
    required this.total,
  });

  final int here;
  final int late;
  final int away;
  final int excused;
  final int total;

  static const _green = Color(0xFF4DFFA0);
  static const _amber = Color(0xFFFFC23D);
  static const _red = Color(0xFFFF5A5F);

  @override
  Widget build(BuildContext context) {
    final digits = total >= 100 ? 3 : 2;
    final arrived = here + late;
    return Semantics(
      label: '$arrived of $total here. $late late. $away away.',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        decoration: BoxDecoration(
          color: Brand.board,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF262A36), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _Cell(
                  label: 'HERE',
                  value: arrived,
                  digits: digits,
                  color: _green,
                  big: true,
                  footer: 'OF $total',
                ),
                _Cell(label: 'LATE', value: late, digits: digits, color: _amber),
                _Cell(
                  label: 'AWAY',
                  value: away,
                  digits: digits,
                  color: _red,
                  footer: excused > 0 ? '+$excused EXCUSED' : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ProgressStrip(
              here: here,
              late: late,
              excused: excused,
              total: total,
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.label,
    required this.value,
    required this.digits,
    required this.color,
    this.big = false,
    this.footer,
  });

  final String label;
  final int value;
  final int digits;
  final Color color;
  final bool big;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(
      fontFamily: Brand.display,
      fontWeight: FontWeight.w700,
      fontSize: 13,
      letterSpacing: 2.2,
      color: Color(0xFF9AA0B2),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(height: 6),
        LedNumber(
          value: value,
          digits: digits,
          height: big ? 50 : 34,
          color: color,
        ),
        SizedBox(
          height: 18,
          child: footer == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    footer!,
                    style: labelStyle.copyWith(
                      fontSize: 10.5,
                      letterSpacing: 1.4,
                      color: const Color(0xFF6E7487),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({
    required this.here,
    required this.late,
    required this.excused,
    required this.total,
  });

  final int here;
  final int late;
  final int excused;
  final int total;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 6,
        child: LayoutBuilder(
          builder: (context, c) {
            double w(int n) => total == 0 ? 0 : c.maxWidth * n / total;
            return Stack(
              children: [
                Container(color: const Color(0xFF1C1F2A)),
                Row(
                  children: [
                    _bar(w(here), Scoreboard._green),
                    _bar(w(late), Scoreboard._amber),
                    _bar(w(excused), const Color(0xFF8197FF)),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _bar(double width, Color color) => AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    curve: Curves.easeOutCubic,
    width: width,
    color: color,
  );
}

/// Faint basketball-court lines, used as a texture behind hero cards.
class CourtLinesPainter extends CustomPainter {
  CourtLinesPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final w = size.width;
    final h = size.height;
    // Half court seen from the side: centre circle on the right edge, key and
    // three-point arc on the left.
    canvas.drawCircle(Offset(w, h / 2), h * 0.28, paint);
    canvas.drawLine(Offset(w, 0), Offset(w, h), paint);
    final keyWidth = h * 0.42;
    canvas.drawRect(
      Rect.fromLTWH(-2, h / 2 - keyWidth / 2, w * 0.24, keyWidth),
      paint,
    );
    canvas.drawCircle(Offset(w * 0.24, h / 2), keyWidth / 2, paint);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(-w * 0.02, h / 2), radius: h * 0.78),
      -1.25,
      2.5,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(CourtLinesPainter old) => old.color != color;
}

/// A basketball, drawn rather than loaded so it stays crisp at any size.
class Basketball extends StatelessWidget {
  const Basketball({super.key, this.size = 64, this.rotation = 0});

  final double size;
  final double rotation;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _BallPainter(rotation),
  );
}

class _BallPainter extends CustomPainter {
  _BallPainter(this.rotation);

  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(r * 0.7, r * 0.6),
          r * 1.4,
          [const Color(0xFFFF9248), Brand.orange, const Color(0xFFB8470A)],
          [0, 0.55, 1],
        ),
    );
    final seam = Paint()
      ..color = const Color(0xFF2A1408)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.075
      ..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    canvas.translate(r, r);
    canvas.rotate(rotation);
    canvas.translate(-r, -r);
    canvas.drawLine(Offset(r, 0), Offset(r, size.height), seam);
    canvas.drawLine(Offset(0, r), Offset(size.width, r), seam);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(-r * 0.35, r), radius: r * 0.95),
      -1.2,
      2.4,
      false,
      seam,
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset(r * 2.35, r), radius: r * 0.95),
      1.94,
      2.4,
      false,
      seam,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BallPainter old) => old.rotation != rotation;
}
