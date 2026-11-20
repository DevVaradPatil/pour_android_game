// Grid → RGBA pixels. Pure Dart (no Flutter) so the benchmark can time it.
import 'dart:typed_data';

import '../sim/sand_sim.dart';

/// Sand colors for types 2..9, in this order. Chosen so every pair stays
/// ≥ 12.9 ΔE2000 apart under normal, protan, deutan and tritan vision
/// (locked by test/ui/palette_test.dart). Jars also show [SandColor.glyph]s,
/// so color is never the only cue.
enum SandColor {
  blue(0x2469F2, 'circle'),
  yellow(0xFFE066, 'triangle'),
  red(0xB3123A, 'square'),
  green(0x3ECF8E, 'diamond'),
  purple(0xD489FA, 'star'),
  orange(0xF7801E, 'plus'),
  white(0xF6F1E9, 'ring'),
  black(0x26222B, 'cross');

  const SandColor(this.rgb, this.glyph);
  final int rgb;
  final String glyph;

  int get cellType => Cell.firstSand + index;
  static SandColor ofCell(int type) => values[type - Cell.firstSand];
}

const int wallRgb = 0xE9DCC6, corkRgb = 0xC08A55, gateRgb = 0x8C7B6B;

/// Index = type * 4 + shade. Values are RGBA8888 read as a little-endian
/// uint32 (0xAABBGGRR). Empty = transparent so the background shows through.
final Uint32List colorLut = _buildLut();

int _abgr(int rgb, double k, [int alpha = 0xFF]) {
  // Premultiplied, as decodeImageFromPixels expects for translucent pixels.
  int ch(int shift) => (((rgb >> shift) & 0xFF) * k * alpha / 255).round().clamp(0, 255);
  return (alpha << 24) | (ch(0) << 16) | (ch(8) << 8) | ch(16);
}

Uint32List _buildLut() {
  final lut = Uint32List(256 * 4);
  const wallShade = [1.0, 0.97, 1.0, 0.95];
  const sandShade = [0.88, 0.95, 1.0, 1.07];
  for (var s = 0; s < 4; s++) {
    lut[Cell.wall * 4 + s] = _abgr(wallRgb, wallShade[s]);
    lut[Cell.cork * 4 + s] = _abgr(corkRgb, wallShade[s]);
    lut[Cell.gate * 4 + s] = _abgr(gateRgb, s.isEven ? 1.0 : 0.85); // striped
    for (final c in SandColor.values) {
      lut[c.cellType * 4 + s] = _abgr(c.rgb, sandShade[s]);
      // Filters: translucent mesh in their color.
      lut[Cell.filterFor(c.cellType) * 4 + s] = _abgr(c.rgb, 1.0, s.isEven ? 0xD0 : 0x70);
    }
  }
  return lut;
}

void renderPixels(SandSim sim, Uint32List out) {
  final cells = sim.cells, shade = sim.shade, lut = colorLut;
  for (var i = 0; i < cells.length; i++) {
    out[i] = lut[(cells[i] << 2) | shade[i]];
  }
}
