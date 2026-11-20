// Logo mark, wordmark and sand glyphs, drawn in code so the in-app logo,
// app icon, splash and store art all come from one source
// (PNG exports: tool/brand_export_test.dart).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/palette.dart';
import 'tokens.dart';

/// A corked glass jar of layered pixel sand, tipped 10° — the "tilt & pour" in one shape.
/// The sand surface stays level with the world, so it reads as physical.
class LogoMarkPainter extends CustomPainter {
  const LogoMarkPainter({this.silhouette = false, this.silhouetteColor = Colors.white});

  /// Single-color version for Android 13+ themed (monochrome) icons.
  final bool silhouette;
  final Color silhouetteColor;

  static const double tiltDeg = -10;

  static Path jarPath(double s) {
    final body = Path()..addRRect(RRect.fromLTRBR(0.20 * s, 0.30 * s, 0.80 * s, 0.92 * s, Radius.circular(0.17 * s)));
    final neck = Path()..addRRect(RRect.fromLTRBR(0.34 * s, 0.20 * s, 0.66 * s, 0.36 * s, Radius.circular(0.05 * s)));
    return Path.combine(PathOperation.union, body, neck);
  }

  static RRect corkRect(double s) => RRect.fromLTRBR(0.37 * s, 0.07 * s, 0.63 * s, 0.22 * s, Radius.circular(0.04 * s));

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    canvas.translate(s / 2, s / 2);
    canvas.rotate(tiltDeg * math.pi / 180);
    canvas.translate(-s / 2, -s / 2);

    final jar = jarPath(s);
    if (silhouette) {
      final p = Paint()..color = silhouetteColor;
      canvas.drawPath(jar, p);
      canvas.drawRRect(corkRect(s), p);
      canvas.restore();
      return;
    }

    // Glass body tint.
    canvas.drawPath(jar, Paint()..color = PourColors.glass.withValues(alpha: 0.10));

    // Pixel sand, clipped to the jar. Layer tops are level in world space,
    // i.e. tilted +10° in the jar's frame.
    canvas.save();
    canvas.clipPath(jar);
    const bands = [(SandColor.blue, 0.71), (SandColor.yellow, 0.56), (SandColor.red, 0.44)];
    final slope = math.tan(-tiltDeg * math.pi / 180);
    const n = 34; // grains across
    final cell = s / n;
    for (var gy = 0; gy < n; gy++) {
      for (var gx = 0; gx < n; gx++) {
        final cx = (gx + 0.5) / n, cy = (gy + 0.5) / n;
        SandColor? color;
        for (final (c, top) in bands) {
          if (cy >= top + (cx - 0.5) * slope) {
            color = c; // bands are listed bottom-up: first match wins
            break;
          }
        }
        if (color == null) continue;
        final h = (gx * 73856093 ^ gy * 19349663) & 0xFF;
        final k = 0.91 + (h / 255) * 0.14;
        canvas.drawRect(
          Rect.fromLTWH(gx * cell, gy * cell, cell + 0.5, cell + 0.5),
          Paint()..color = _shade(Color(0xFF000000 | color.rgb), k),
        );
      }
    }
    canvas.restore();

    // Glass outline + highlight.
    canvas.drawPath(
      jar,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.045 * s
        ..strokeJoin = StrokeJoin.round
        ..color = PourColors.glass,
    );
    canvas.drawLine(
      Offset(0.30 * s, 0.46 * s),
      Offset(0.30 * s, 0.70 * s),
      Paint()
        ..strokeWidth = 0.035 * s
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.55),
    );

    // Cork with two grooves.
    final cork = corkRect(s);
    canvas.drawRRect(cork, Paint()..color = PourColors.cork);
    final groove = Paint()
      ..strokeWidth = 0.012 * s
      ..color = const Color(0xFF8E5F35);
    for (final y in [0.12, 0.17]) {
      canvas.drawLine(Offset(0.40 * s, y * s), Offset(0.60 * s, y * s), groove);
    }
    canvas.restore();
  }

  static Color _shade(Color c, double k) => Color.from(
        alpha: 1,
        red: (c.r * k).clamp(0, 1),
        green: (c.g * k).clamp(0, 1),
        blue: (c.b * k).clamp(0, 1),
      );

  @override
  bool shouldRepaint(LogoMarkPainter old) => old.silhouette != silhouette;
}

class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: const CustomPaint(painter: LogoMarkPainter()));
}

/// "P[jar]UR": the mark stands in for the O.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.height = 56});
  final double height;

  @override
  Widget build(BuildContext context) {
    final style = PourText.display.copyWith(fontSize: height, height: 1, letterSpacing: height * 0.06);
    return Semantics(
      label: 'Pour',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('P', style: style),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: height * 0.01),
            child: LogoMark(size: height * 0.95),
          ),
          Text('UR', style: style),
        ],
      ),
    );
  }
}

/// Shape that backs up each sand color (accessibility: color is never the only cue).
class SandGlyphPainter extends CustomPainter {
  const SandGlyphPainter(this.color);
  final SandColor color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final c = Offset(size.width / 2, size.height / 2);
    final fill = Paint()..color = Color(0xFF000000 | color.rgb);
    final light = Color(0xFF000000 | color.rgb).computeLuminance() > 0.4;
    final ink = Paint()
      ..color = light ? const Color(0xFF2A211B) : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawCircle(c, s / 2, fill);
    if (Color(0xFF000000 | color.rgb).computeLuminance() < 0.05) {
      // Dark sand would vanish on the dark UI: give it a glass rim.
      canvas.drawCircle(
        c,
        s / 2 - s * 0.03,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.06
          ..color = PourColors.glass.withValues(alpha: 0.6),
      );
    }
    final r = s * 0.24;
    switch (color.glyph) {
      case 'circle':
        canvas.drawCircle(c, r, ink..style = PaintingStyle.fill);
      case 'ring':
        canvas.drawCircle(c, r, ink);
      case 'square':
        canvas.drawRect(Rect.fromCenter(center: c, width: r * 1.7, height: r * 1.7), ink..style = PaintingStyle.fill);
      case 'triangle':
        canvas.drawPath(_poly(c, r * 1.15, 3, -math.pi / 2), ink..style = PaintingStyle.fill);
      case 'diamond':
        canvas.drawPath(_poly(c, r * 1.15, 4, -math.pi / 2), ink..style = PaintingStyle.fill);
      case 'star':
        canvas.drawPath(_star(c, r * 1.25, r * 0.55), ink..style = PaintingStyle.fill);
      case 'plus':
        canvas.drawLine(c.translate(-r, 0), c.translate(r, 0), ink);
        canvas.drawLine(c.translate(0, -r), c.translate(0, r), ink);
      case 'cross':
        canvas.drawLine(c.translate(-r * 0.8, -r * 0.8), c.translate(r * 0.8, r * 0.8), ink);
        canvas.drawLine(c.translate(r * 0.8, -r * 0.8), c.translate(-r * 0.8, r * 0.8), ink);
    }
  }

  static Path _poly(Offset c, double r, int n, double start) {
    final p = Path();
    for (var i = 0; i < n; i++) {
      final a = start + i * 2 * math.pi / n;
      final pt = c + Offset(math.cos(a), math.sin(a)) * r;
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  static Path _star(Offset c, double ro, double ri) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final pt = c + Offset(math.cos(a), math.sin(a)) * (i.isEven ? ro : ri);
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  @override
  bool shouldRepaint(SandGlyphPainter old) => old.color != color;
}

class SandGlyph extends StatelessWidget {
  const SandGlyph(this.color, {super.key, this.size = 28});
  final SandColor color;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '${color.name} sand',
        child: SizedBox.square(dimension: size, child: CustomPaint(painter: SandGlyphPainter(color))),
      );
}
