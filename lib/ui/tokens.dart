// Design tokens: the "Desert Glass" look. Change values here, not in widgets.
import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

abstract final class PourColors {
  static const bg = Color(0xFF1A1410); // deep sand-brown night
  static const surface = Color(0xFF2A211B); // cards, sheets, playfield
  static const surfaceHigh = Color(0xFF3A2E25); // raised / pressed
  static const outline = Color(0xFF5A4838);
  static const glass = Color(0xFFE9DCC6); // walls, jar glass
  static const text = Color(0xFFF4EBDD);
  static const textMuted = Color(0xFFBBAB94);
  static const accent = Color(0xFFF2A93B); // amber: primary actions, stars
  static const onAccent = Color(0xFF2A1A08);
  static const cork = Color(0xFFC08A55);
  static const coin = Color(0xFFFFD45C);
  static const danger = Color(0xFFFF6B5E);
}

abstract final class Space {
  static const double xs = 4, s = 8, m = 12, l = 16, xl = 24, xxl = 32, xxxl = 48;
}

abstract final class Radii {
  static const double s = 8, m = 14, l = 22, xl = 32;
}

abstract final class Motion {
  static const fast = Duration(milliseconds: 120);
  static const medium = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 420);
  static const Curve standard = Curves.easeOutCubic;
  static const Curve pop = Curves.easeOutBack;
}

/// Fredoka (rounded display) for titles, buttons and numbers; Nunito for body.
/// Both are variable fonts, so weight is set through the `wght` axis too.
abstract final class PourText {
  static TextStyle _f(String family, double size, double weight, {double? spacing, double? height}) => TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
        fontVariations: [FontVariation.weight(weight)],
        letterSpacing: spacing,
        height: height,
        color: PourColors.text,
      );

  static final display = _f('Fredoka', 44, 600, spacing: 2, height: 1.05);
  static final title = _f('Fredoka', 26, 600, height: 1.15);
  static final heading = _f('Fredoka', 20, 500, height: 1.2);
  static final button = _f('Fredoka', 18, 600, spacing: 0.5);
  static final number = _f('Fredoka', 18, 600);
  static final body = _f('Nunito', 16, 500, height: 1.4);
  static final label = _f('Nunito', 13, 700, spacing: 0.3);
  static final caption = _f('Nunito', 12, 500, height: 1.3);
}
