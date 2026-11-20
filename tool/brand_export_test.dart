// Exports brand PNGs from the in-code painters (lib/ui/brand.dart) into branding/.
// Not part of the normal suite (lives outside test/). Run after changing the logo:
//   flutter test tool/brand_export_test.dart; dart run flutter_launcher_icons; dart run flutter_native_splash:create
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pour_sand_game/ui/brand.dart';
import 'package:pour_sand_game/ui/tokens.dart';

Future<void> _png(String name, int w, int h, void Function(Canvas c, Size s) draw) async {
  final rec = ui.PictureRecorder();
  draw(Canvas(rec), Size(w.toDouble(), h.toDouble()));
  final img = await rec.endRecording().toImage(w, h);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  File('branding/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
}

void _bg(Canvas c, Size s) {
  c.drawRect(
    Offset.zero & s,
    Paint()
      ..shader = ui.Gradient.radial(
        s.center(Offset.zero).translate(0, -s.height * 0.08),
        s.width * 0.72,
        [PourColors.surfaceHigh, PourColors.bg],
      ),
  );
}

/// Draws the mark centered at [scale] of the canvas.
void _mark(Canvas c, Size s, double scale, {bool silhouette = false}) {
  final d = s.shortestSide * scale;
  c.save();
  c.translate((s.width - d) / 2, (s.height - d) / 2);
  LogoMarkPainter(silhouette: silhouette).paint(c, Size.square(d));
  c.restore();
}

void main() {
  testWidgets('export brand PNGs', (tester) async {
    await tester.runAsync(() async {
      final fredoka = FontLoader('Fredoka')..addFont(rootBundle.load('assets/fonts/Fredoka.ttf'));
      await fredoka.load();
      Directory('branding').createSync();

      await _png('logo_mark.png', 1024, 1024, (c, s) => _mark(c, s, 1));
      // iOS / Play hi-res icon: full-bleed background, no transparency.
      await _png('icon_ios.png', 1024, 1024, (c, s) {
        _bg(c, s);
        _mark(c, s, 0.80);
      });
      await _png('store_icon_512.png', 512, 512, (c, s) {
        _bg(c, s);
        _mark(c, s, 0.80);
      });
      // Android adaptive icon: 108dp canvas, launcher masks to ~72dp, safe circle 66dp.
      // 0.86 x (1 - 2 x 16% inset) = mark ~58% of 108dp, inside the safe circle.
      await _png('icon_bg.png', 1024, 1024, _bg);
      await _png('icon_fg.png', 1024, 1024, (c, s) => _mark(c, s, 0.86)); // launcher_icons adds a 16% inset
      await _png('icon_mono.png', 1024, 1024, (c, s) => _mark(c, s, 0.86, silhouette: true));
      // Splash: pre-Android-12 image, and the Android 12+ icon (1152, visible circle 768).
      await _png('splash.png', 512, 512, (c, s) => _mark(c, s, 1));
      await _png('splash_android12.png', 1152, 1152, (c, s) => _mark(c, s, 0.58));

      // Wordmark (store art, social).
      const h = 640.0;
      final style = PourText.display.copyWith(fontSize: h * 0.62, height: 1, letterSpacing: h * 0.03);
      TextPainter tp(String t) => TextPainter(text: TextSpan(text: t, style: style), textDirection: TextDirection.ltr)..layout();
      final p = tp('P'), ur = tp('UR');
      final markSize = h * 0.6;
      final w = (p.width + markSize + ur.width + h * 0.16).ceil();
      await _png('wordmark.png', w, h.toInt(), (c, s) {
        var x = h * 0.08;
        final baseY = (s.height - p.height) / 2;
        p.paint(c, Offset(x, baseY));
        x += p.width;
        c.save();
        c.translate(x, (s.height - markSize) / 2);
        const LogoMarkPainter().paint(c, Size.square(markSize));
        c.restore();
        x += markSize;
        ur.paint(c, Offset(x, baseY));
      });
    });
  });
}
