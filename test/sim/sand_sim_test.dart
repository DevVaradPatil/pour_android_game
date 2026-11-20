import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pour_sand_game/sim/sand_sim.dart';
import 'package:pour_sand_game/sim/scenes.dart';

/// Swings gravity left and right so sand keeps flowing.
double script(int t) => 60 * math.sin(t / 40);

void run(SandSim sim, int steps) {
  for (var t = 0; t < steps; t++) {
    sim.setGravityDegrees(script(t));
    sim.step();
  }
}

SandSim openFloorBox() {
  final sim = SandSim(100, 60);
  sim.fillRect(0, 57, 100, 3, Cell.wall);
  sim.fillRect(0, 0, 3, 60, Cell.wall);
  sim.fillRect(97, 0, 3, 60, Cell.wall);
  return sim;
}

void main() {
  test('determinism: same seed and inputs give the same grid', () {
    final a = toyBox(seed: 7), b = toyBox(seed: 7), c = toyBox(seed: 8);
    run(a, 300);
    run(b, 300);
    run(c, 300);
    expect(a.stateHash(), b.stateHash());
    expect(a.stateHash(), isNot(c.stateHash()));
  });

  test('conservation: a closed box never gains or loses sand', () {
    final sim = toyBox();
    final start = sim.grains;
    run(sim, 400);
    expect(sim.grains, start);
    expect(sim.lost.reduce((a, b) => a + b), 0);
  });

  test('void: sand leaving the field is counted as lost', () {
    final sim = SandSim(60, 60);
    sim.fillRect(20, 10, 20, 20, Cell.firstSand);
    final start = sim.grains;
    run(sim, 200);
    final lost = sim.lost.reduce((a, b) => a + b);
    expect(lost, greaterThan(0));
    expect(sim.grains + lost, start);
  });

  test('sleeping chunks give exactly the same result as processing everything', () {
    final sleepy = toyBox(seed: 3), awake = toyBox(seed: 3)..alwaysAwake = true;
    for (var t = 0; t < 600; t++) {
      // Hold still for a while in the middle so chunks actually fall asleep.
      final g = t > 200 && t < 400 ? 0.0 : script(t);
      sleepy.setGravityDegrees(g);
      awake.setGravityDegrees(g);
      sleepy.step();
      awake.step();
      if (t % 50 == 0) expect(sleepy.stateHash(), awake.stateHash(), reason: 'step $t');
    }
    expect(sleepy.stateHash(), awake.stateHash());
  });

  test('settled sand goes to sleep', () {
    final sim = toyBox();
    for (var t = 0; t < 1500; t++) {
      sim.step();
    }
    expect(sim.moved, 0);
    expect(sim.activeChunks, lessThan(sim.chunkCount ~/ 10));
  });

  test('angle of repose: a flat layer holds at 30° tilt and slides at 40°', () {
    final sim = openFloorBox();
    sim.fillRect(20, 56, 40, 1, Cell.firstSand); // one-grain-thick layer on the floor
    sim.setGravityDegrees(30);
    final before = sim.stateHash();
    for (var t = 0; t < 100; t++) {
      sim.step();
    }
    expect(sim.stateHash(), before);

    sim.setGravityDegrees(40);
    for (var t = 0; t < 100; t++) {
      sim.step();
    }
    expect(sim.stateHash(), isNot(before));
  });

  test('a cliff steeper than repose (relative to tilted gravity) collapses', () {
    // Column leaning on the right wall with a vertical left face. At 37° tilt that
    // face is a 53° slope relative to gravity, so it must avalanche to the left.
    final sim = SandSim(100, 100);
    sim.fillRect(0, 97, 100, 3, Cell.wall);
    sim.fillRect(97, 0, 3, 100, Cell.wall);
    sim.fillRect(72, 20, 25, 77, Cell.firstSand);
    sim.setGravityDegrees(37);
    for (var t = 0; t < 1500; t++) {
      sim.step();
    }
    var leftmost = 100;
    for (var y = 0; y < 97; y++) {
      for (var x = 0; x < 97; x++) {
        if (sim.get(x, y) == Cell.firstSand && x < leftmost) leftmost = x;
      }
    }
    expect(leftmost, lessThan(60));
  });

  test('a falling stream follows the gravity angle', () {
    final sim = SandSim(200, 200);
    sim.set(100, 0, Cell.firstSand);
    sim.setGravityDegrees(30);
    var x = 100, y = 0;
    for (var t = 0; t < 150; t++) {
      sim.step();
      final i = sim.cells.indexWhere((c) => c != Cell.empty);
      if (i < 0) break;
      x = i % 200;
      y = i ~/ 200;
    }
    final angle = math.atan2(x - 100, y) * 180 / math.pi;
    expect(angle, closeTo(30, 6));
  });

  test('gravity is clamped to ±70° and quantized', () {
    final sim = SandSim(10, 10);
    sim.setGravityDegrees(120);
    expect(sim.gravityDeg, 70);
    sim.setGravityDegrees(-12.3);
    expect(sim.gravityDeg, -12.5);
  });
}
