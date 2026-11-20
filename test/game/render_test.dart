import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pour_sand_game/game/palette.dart';
import 'package:pour_sand_game/sim/sand_sim.dart';

void main() {
  test('grains under sand render darker than the top layer; empty stays transparent', () {
    final sim = SandSim(4, 4);
    final t = SandColor.yellow.cellType;
    sim.set(1, 1, t);
    sim.set(1, 2, t);
    final out = Uint32List(16);
    renderPixels(sim, out);
    expect(out[1 * 4 + 1], colorLut[(t << 3) | sim.shade[5]]); // top grain: lit
    expect(out[2 * 4 + 1], colorLut[(t << 3) | 4 | sim.shade[9]]); // covered: shadowed
    expect(out[0], 0);
    for (final c in SandColor.values) {
      for (var s = 0; s < 4; s++) {
        final lit = colorLut[(c.cellType << 3) | s], shadow = colorLut[(c.cellType << 3) | 4 | s];
        expect((shadow >> 8) & 0xFF, lessThanOrEqualTo((lit >> 8) & 0xFF), reason: '${c.name} green channel');
      }
    }
  });
}
