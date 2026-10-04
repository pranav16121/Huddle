// Generates Huddle's launcher icons: a basketball, nothing else.
//
// Run with:  flutter test tool/generate_icons_test.dart
//
// Writes into android/app/src/main/res:
//   mipmap-*/ic_launcher.png             legacy icon (ball on transparent)
//   mipmap-*/ic_launcher_background.png  adaptive layer: the ball's leather
//   mipmap-*/ic_launcher_foreground.png  adaptive layer: the seams
//   mipmap-*/ic_launcher_monochrome.png  themed-icon silhouette (Android 13+)
//
// The adaptive layers are drawn so the launcher's mask *is* the ball: with a
// round mask you get exactly a basketball.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _res = 'android/app/src/main/res';
const _densities = {
  'mdpi': 1.0,
  'hdpi': 1.5,
  'xhdpi': 2.0,
  'xxhdpi': 3.0,
  'xxxhdpi': 4.0,
};

const _orangeLight = Color(0xFFFF9A52);
const _orange = Color(0xFFF26A1B);
const _orangeDark = Color(0xFFB4450A);
const _seam = Color(0xFF2A1408);

/// Leather with a soft highlight up and to the left.
Paint _leather(Offset center, double r) => Paint()
  ..shader = ui.Gradient.radial(
    center + Offset(-r * 0.32, -r * 0.38),
    r * 1.45,
    [_orangeLight, _orange, _orangeDark],
    [0, 0.5, 1],
  );

/// The four seams of a basketball, for a ball of radius [r] at [c].
void _seams(Canvas canvas, Offset c, double r, Paint paint) {
  canvas.drawLine(Offset(c.dx, c.dy - r * 1.5), Offset(c.dx, c.dy + r * 1.5), paint);
  canvas.drawLine(Offset(c.dx - r * 1.5, c.dy), Offset(c.dx + r * 1.5, c.dy), paint);
  const sweep = 2.4;
  canvas.drawArc(
    Rect.fromCircle(center: Offset(c.dx - r * 1.35, c.dy), radius: r * 0.95),
    -sweep / 2,
    sweep,
    false,
    paint,
  );
  canvas.drawArc(
    Rect.fromCircle(center: Offset(c.dx + r * 1.35, c.dy), radius: r * 0.95),
    math.pi - sweep / 2,
    sweep,
    false,
    paint,
  );
}

Paint _seamPaint(double r, Color color) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = r * 0.085
  ..strokeCap = StrokeCap.round;

/// Legacy icon: the ball on transparent, with a little breathing room.
void _paintLegacy(Canvas canvas, double size) {
  final c = Offset(size / 2, size / 2);
  final r = size * 0.44;
  canvas.drawCircle(
    c + Offset(0, size * 0.015),
    r,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.22)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.018),
  );
  canvas.drawCircle(c, r, _leather(c, r));
  canvas.save();
  canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
  _seams(canvas, c, r, _seamPaint(r, _seam));
  canvas.restore();
}

// Adaptive icons are 108dp; the visible area is the central 72dp.
double _ballRadius(double size) => size * 36 / 108;

void _paintBackground(Canvas canvas, double size) {
  final c = Offset(size / 2, size / 2);
  canvas.drawRect(Offset.zero & Size.square(size), _leather(c, _ballRadius(size)));
}

void _paintForeground(Canvas canvas, double size) {
  final c = Offset(size / 2, size / 2);
  final r = _ballRadius(size);
  _seams(canvas, c, r, _seamPaint(r, _seam));
}

void _paintMonochrome(Canvas canvas, double size) {
  final c = Offset(size / 2, size / 2);
  final r = size * 30 / 108; // inside the 66dp safe zone
  canvas.saveLayer(Offset.zero & Size.square(size), Paint());
  canvas.drawCircle(c, r, Paint()..color = Colors.white);
  canvas.save();
  canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
  _seams(
    canvas,
    c,
    r,
    _seamPaint(r, Colors.black)..blendMode = BlendMode.clear,
  );
  canvas.restore();
  canvas.restore();
}

Future<void> _write(
  String path,
  int px,
  void Function(Canvas canvas, double size) paint,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paint(canvas, px.toDouble());
  final image = await recorder.endRecording().toImage(px, px);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('generate launcher icons', (tester) async {
    await tester.runAsync(() async {
      for (final MapEntry(key: name, value: scale) in _densities.entries) {
        final dir = '$_res/mipmap-$name';
        await _write('$dir/ic_launcher.png', (48 * scale).round(), _paintLegacy);
        final adaptive = (108 * scale).round();
        await _write('$dir/ic_launcher_background.png', adaptive, _paintBackground);
        await _write('$dir/ic_launcher_foreground.png', adaptive, _paintForeground);
        await _write('$dir/ic_launcher_monochrome.png', adaptive, _paintMonochrome);
      }
      // A large preview, handy for the README or a store listing.
      await _write('tool/icon_preview.png', 512, _paintLegacy);
    });
  });
}
