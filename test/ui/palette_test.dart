import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pour_sand_game/game/palette.dart';
import 'package:pour_sand_game/ui/tokens.dart';

// Machado et al. 2009 CVD simulation (severity 1.0), applied in linear RGB.
const _cvd = {
  'protan': [0.152286, 1.052583, -0.204868, 0.114503, 0.786281, 0.099216, -0.003882, -0.048116, 1.051998],
  'deutan': [0.367322, 0.860646, -0.227968, 0.280085, 0.672501, 0.047413, -0.011820, 0.042940, 0.968881],
  'tritan': [1.255528, -0.076749, -0.178779, -0.078411, 0.930809, 0.147602, 0.004733, 0.691367, 0.303900],
};

double _lin(int c) {
  final v = c / 255;
  return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

List<double> _lab(int rgb, [String? cvd]) {
  var c = [_lin((rgb >> 16) & 255), _lin((rgb >> 8) & 255), _lin(rgb & 255)];
  if (cvd != null) {
    final m = _cvd[cvd]!;
    c = [for (var i = 0; i < 3; i++) (m[i * 3] * c[0] + m[i * 3 + 1] * c[1] + m[i * 3 + 2] * c[2]).clamp(0.0, 1.0)];
  }
  final x = (0.4124 * c[0] + 0.3576 * c[1] + 0.1805 * c[2]) / 0.95047;
  final y = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
  final z = (0.0193 * c[0] + 0.1192 * c[1] + 0.9505 * c[2]) / 1.08883;
  double f(double t) => t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  return [116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))];
}

double _rad(double d) => d * math.pi / 180;

/// CIEDE2000 colour difference.
double deltaE2000(List<double> p, List<double> q) {
  final c1 = math.sqrt(p[1] * p[1] + p[2] * p[2]), c2 = math.sqrt(q[1] * q[1] + q[2] * q[2]);
  final cb7 = math.pow((c1 + c2) / 2, 7);
  final g = 0.5 * (1 - math.sqrt(cb7 / (cb7 + math.pow(25, 7))));
  final a1 = (1 + g) * p[1], a2 = (1 + g) * q[1];
  final c1p = math.sqrt(a1 * a1 + p[2] * p[2]), c2p = math.sqrt(a2 * a2 + q[2] * q[2]);
  double hue(double b, double a) => (math.atan2(b, a) * 180 / math.pi) % 360;
  final h1 = hue(p[2], a1), h2 = hue(q[2], a2);
  var dh = h2 - h1;
  if (c1p * c2p == 0) {
    dh = 0;
  } else if (dh > 180) {
    dh -= 360;
  } else if (dh < -180) {
    dh += 360;
  }
  final dL = q[0] - p[0], dC = c2p - c1p;
  final dH = 2 * math.sqrt(c1p * c2p) * math.sin(_rad(dh / 2));
  final lb = (p[0] + q[0]) / 2, cbp = (c1p + c2p) / 2;
  var hb = (h1 - h2).abs() <= 180 ? (h1 + h2) / 2 : (h1 + h2 + 360) / 2;
  if (c1p * c2p == 0) hb = h1 + h2;
  final t = 1 -
      0.17 * math.cos(_rad(hb - 30)) +
      0.24 * math.cos(_rad(2 * hb)) +
      0.32 * math.cos(_rad(3 * hb + 6)) -
      0.2 * math.cos(_rad(4 * hb - 63));
  final dth = 30 * math.exp(-math.pow((hb - 275) / 25, 2));
  final cbp7 = math.pow(cbp, 7);
  final rc = 2 * math.sqrt(cbp7 / (cbp7 + math.pow(25, 7)));
  final sl = 1 + 0.015 * math.pow(lb - 50, 2) / math.sqrt(20 + math.pow(lb - 50, 2));
  final sc = 1 + 0.045 * cbp, sh = 1 + 0.015 * cbp * t;
  final rt = -math.sin(_rad(2 * dth)) * rc;
  return math.sqrt(math.pow(dL / sl, 2) + math.pow(dC / sc, 2) + math.pow(dH / sh, 2) + rt * (dC / sc) * (dH / sh));
}

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  test('sand colors stay distinguishable under normal and colorblind vision', () {
    final cs = SandColor.values;
    for (final vision in [null, 'protan', 'deutan', 'tritan']) {
      for (var i = 0; i < cs.length; i++) {
        for (var j = i + 1; j < cs.length; j++) {
          final d = deltaE2000(_lab(cs[i].rgb, vision), _lab(cs[j].rgb, vision));
          expect(d, greaterThanOrEqualTo(12.5), reason: '${cs[i].name}/${cs[j].name} under ${vision ?? 'normal'}');
        }
      }
    }
  });

  test('every sand color has a unique glyph', () {
    expect(SandColor.values.map((c) => c.glyph).toSet().length, SandColor.values.length);
  });

  test('text tokens meet WCAG AA contrast (4.5:1)', () {
    final pairs = {
      'text/bg': (PourColors.text, PourColors.bg),
      'text/surface': (PourColors.text, PourColors.surface),
      'text/surfaceHigh': (PourColors.text, PourColors.surfaceHigh),
      'textMuted/bg': (PourColors.textMuted, PourColors.bg),
      'textMuted/surface': (PourColors.textMuted, PourColors.surface),
      'onAccent/accent': (PourColors.onAccent, PourColors.accent),
    };
    pairs.forEach((name, p) => expect(contrast(p.$1, p.$2), greaterThanOrEqualTo(4.5), reason: name));
  });
}
