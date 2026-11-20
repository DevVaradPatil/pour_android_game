// Headless sim + pixel-fill benchmark on the worst case: the toy box with
// gravity swinging constantly, so nothing ever sleeps.
//   dart run tool/bench_sim.dart                       (JIT, quick)
//   dart compile exe tool/bench_sim.dart -o build/bench.exe; build/bench.exe   (AOT, like the app)
// Exits 1 if a step is over budget, as an early alarm (PLAN.md Phase 1).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pour_sand_game/game/palette.dart';
import 'package:pour_sand_game/sim/scenes.dart';

const double budgetMsPerStep = 6;

void main() {
  final sim = toyBox();
  final px = Uint32List(gridW * gridH);
  const warmup = 120, steps = 1800;
  final stepUs = <int>[];
  var renderUs = 0;
  final sw = Stopwatch();
  for (var t = 0; t < warmup + steps; t++) {
    sim.setGravityDegrees(60 * math.sin(t / 50));
    sw
      ..reset()
      ..start();
    sim.step();
    sw.stop();
    if (t >= warmup) stepUs.add(sw.elapsedMicroseconds);
    if (t % 3 == 0) {
      sw
        ..reset()
        ..start();
      renderPixels(sim, px);
      sw.stop();
      if (t >= warmup) renderUs += sw.elapsedMicroseconds;
    }
  }
  stepUs.sort();
  double ms(int us) => us / 1000;
  final avg = stepUs.reduce((a, b) => a + b) / stepUs.length / 1000;
  final p95 = ms(stepUs[(stepUs.length * 0.95).floor()]);
  final renderAvg = renderUs / (steps / 3) / 1000;
  stdout.writeln('grid ${gridW}x$gridH  grains ${sim.grains}');
  stdout.writeln('step   avg ${avg.toStringAsFixed(3)} ms  p95 ${p95.toStringAsFixed(3)} ms  max ${ms(stepUs.last).toStringAsFixed(3)} ms');
  stdout.writeln('render avg ${renderAvg.toStringAsFixed(3)} ms');
  stdout.writeln('per 60 Hz tick at 3 steps: ${(avg * 3 + renderAvg).toStringAsFixed(2)} ms (frame budget 16.7)');
  if (avg > budgetMsPerStep) {
    stderr.writeln('OVER BUDGET: $budgetMsPerStep ms/step');
    exit(1);
  }
}
