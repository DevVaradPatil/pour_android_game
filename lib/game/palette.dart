// Grid → RGBA pixels. Pure Dart (no Flutter) so the benchmark can time it.
import 'dart:typed_data';

import '../sim/sand_sim.dart';

/// Sand colors for types 2..9: blue, yellow, red, green, purple, orange, white, black.
/// Placeholder until the Phase 2 palette pass (colorblind-checked).
const List<int> sandRgb = [
  0x3D7DD8, 0xF2C230, 0xE0533D, 0x4CAF50, 0x8E5BD0, 0xF08A2C, 0xF3EEE6, 0x2E2A2A, //
];
const int wallRgb = 0xE9DCC6;

/// Index = type * 4 + shade. Values are RGBA8888 read as a little-endian
/// uint32 (0xAABBGGRR). Empty = transparent so the background shows through.
final Uint32List colorLut = _buildLut();

int _abgr(int rgb, double k) {
  int ch(int shift) => (((rgb >> shift) & 0xFF) * k).round().clamp(0, 255);
  return 0xFF000000 | (ch(0) << 16) | (ch(8) << 8) | ch(16);
}

Uint32List _buildLut() {
  final lut = Uint32List(256 * 4);
  const wallShade = [1.0, 0.97, 1.0, 0.95];
  const sandShade = [0.88, 0.95, 1.0, 1.07];
  for (var s = 0; s < 4; s++) {
    lut[Cell.wall * 4 + s] = _abgr(wallRgb, wallShade[s]);
    for (var c = 0; c < Cell.sandColors; c++) {
      lut[(Cell.firstSand + c) * 4 + s] = _abgr(sandRgb[c], sandShade[s]);
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
