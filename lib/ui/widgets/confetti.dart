import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// A one-shot burst of confetti and tiny basketballs, for full houses.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, this.particles = 70});

  final int particles;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..forward();

  late final List<_Particle> _particles = () {
    final rng = math.Random();
    const colors = [
      Brand.orange,
      Color(0xFF4DFFA0),
      Color(0xFFFFC23D),
      Color(0xFF3D7BF7),
      Color(0xFFE5487F),
      Colors.white,
    ];
    return List.generate(widget.particles, (i) {
      final angle = -math.pi / 2 + (rng.nextDouble() - 0.5) * math.pi * 0.9;
      final speed = 0.9 + rng.nextDouble() * 0.9;
      return _Particle(
        vx: math.cos(angle) * speed * 0.55,
        vy: math.sin(angle) * speed,
        spin: (rng.nextDouble() - 0.5) * 14,
        size: 6 + rng.nextDouble() * 7,
        color: colors[rng.nextInt(colors.length)],
        ball: i % 9 == 0,
        delay: rng.nextDouble() * 0.12,
      );
    });
  }();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(_particles, _controller.value),
        ),
      ),
    );
  }
}

class _Particle {
  _Particle({
    required this.vx,
    required this.vy,
    required this.spin,
    required this.size,
    required this.color,
    required this.ball,
    required this.delay,
  });

  final double vx;
  final double vy;
  final double spin;
  final double size;
  final Color color;
  final bool ball;
  final double delay;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.particles, this.progress);

  final List<_Particle> particles;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.42);
    final scale = size.height * 0.75;
    for (final p in particles) {
      final t = ((progress - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;
      const gravity = 2.2;
      final dx = p.vx * t * scale;
      final dy = (p.vy * t + 0.5 * gravity * t * t) * scale * 0.55;
      final opacity = t < 0.75 ? 1.0 : (1 - (t - 0.75) / 0.25);
      final pos = origin + Offset(dx, dy);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.spin * t);
      if (p.ball) {
        final r = p.size * 0.75;
        canvas.drawCircle(
          Offset.zero,
          r,
          Paint()..color = Brand.orange.withValues(alpha: opacity),
        );
        final seam = Paint()
          ..color = const Color(0xFF2A1408).withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.16;
        canvas.drawLine(Offset(-r, 0), Offset(r, 0), seam);
        canvas.drawLine(Offset(0, -r), Offset(0, r), seam);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size,
              height: p.size * 0.45,
            ),
            const Radius.circular(1.5),
          ),
          Paint()..color = p.color.withValues(alpha: opacity),
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}
