import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pour_sand_game/game/palette.dart';
import 'package:pour_sand_game/level/level.dart';
import 'package:pour_sand_game/level/level_run.dart';
import 'package:pour_sand_game/sim/sand_sim.dart';

/// Jar inside x100..140, y300..360 (2400 cells), fill 0.5 ⇒ target 1200.
Level level({
  List<Map<String, Object>> sand = const [],
  List<Map<String, Object>> valves = const [],
  List<Map<String, Object>> walls = const [],
  double purity = 0.9,
}) =>
    Level.fromJson(jsonEncode({
      'id': 'test',
      'name': 'Test',
      'seed': 3,
      'sand': sand,
      'jars': [
        {'color': 'blue', 'rect': [100, 300, 40, 60], 'fill': 0.5, 'purity': purity},
      ],
      'valves': valves,
      'walls': walls,
    }));

/// Hopper sides around x95..145 down to the valve at y210.
const hopper = [
  {'rect': [93, 130, 2, 83]},
  {'rect': [145, 130, 2, 83]},
];

Map<String, Object> block(String color, int x, int y, int w, int h) => {'color': color, 'rect': [x, y, w, h]};

LevelRun runFor(Level l, int ticks, [void Function(LevelRun r)? each]) {
  final r = LevelRun(l);
  for (var t = 0; t < ticks; t++) {
    each?.call(r);
    r.step();
  }
  return r;
}

void main() {
  test('jar corks when filled with its color; clean run = 3 stars', () {
    final r = runFor(level(sand: [block('blue', 105, 200, 30, 50)]), 600);
    expect(r.status, RunStatus.won);
    expect(r.jars.single.corked, isTrue);
    expect(r.stars, 3);
    // Cork row is in place.
    for (var x = 100; x < 140; x++) {
      expect(r.sim.get(x, 300), Cell.cork);
    }
  });

  test('result is frozen at the win even if sand keeps spilling', () {
    // Extra sand off to the side keeps falling into the void after the jar corks.
    final r = runFor(level(sand: [block('blue', 105, 200, 30, 50), block('blue', 10, 100, 30, 30)]), 60);
    for (var t = 0; t < 600 && r.status == RunStatus.playing; t++) {
      r.step();
    }
    expect(r.status, RunStatus.won);
    final spill = r.spill, stars = r.stars;
    for (var t = 0; t < 600; t++) {
      r.step();
    }
    expect(r.lostGrains / r.initialGrains, greaterThan(spill));
    expect(r.spill, spill);
    expect(r.stars, stars);
  });

  test('impure jar does not cork', () {
    final r = runFor(level(sand: [block('blue', 105, 200, 15, 80), block('yellow', 120, 200, 15, 80)]), 600);
    expect(r.jars.single.corked, isFalse);
    expect(r.jars.single.purity, lessThan(0.9));
  });

  test('a corked jar keeps its sand when tilted hard', () {
    final r = runFor(level(sand: [block('blue', 105, 200, 30, 50)]), 600);
    expect(r.jars.single.corked, isTrue);
    final counts = Int32List(Cell.typeCount);
    r.sim.countRect(100, 301, 40, 59, counts);
    final inside = counts[SandColor.blue.cellType];
    r.sim.setGravityDegrees(70);
    for (var t = 0; t < 900; t++) {
      r.sim.step();
    }
    r.sim.countRect(100, 301, 40, 59, counts);
    expect(counts[SandColor.blue.cellType], inside);
  });

  test('out of sand when the needed color falls into the void', () {
    final r = runFor(level(sand: [block('blue', 10, 200, 30, 50)]), 600);
    expect(r.status, RunStatus.outOfSand);
    expect(r.shortColors, {SandColor.blue});
  });

  test('closed valve holds sand until toggled', () {
    final l = level(
      sand: [block('blue', 105, 150, 30, 50)],
      valves: [
        {'rect': [95, 210, 50, 3]},
      ],
      walls: hopper,
    );
    final r = runFor(l, 300);
    expect(r.status, RunStatus.playing);
    expect(r.jars.single.total, 0);
    r.toggleValve(0);
    for (var t = 0; t < 600 && r.status == RunStatus.playing; t++) {
      r.step();
    }
    expect(r.status, RunStatus.won);
  });

  test('stars: spill costs the third star, impurity the second', () {
    // 1800 extra grains fall into the void ⇒ spill > 10%.
    final spilled = runFor(level(sand: [block('blue', 105, 200, 30, 50), block('blue', 10, 360, 30, 60)]), 600);
    expect(spilled.status, RunStatus.won);
    expect(spilled.spill, greaterThan(0.1));
    expect(spilled.stars, 2);

    // Yellow lands first: purity ~0.875 ⇒ corks at 0.8, but below the 95% star line.
    final impure = runFor(
      level(purity: 0.8, sand: [block('blue', 105, 200, 30, 45), block('yellow', 105, 245, 30, 5)]),
      600,
    );
    expect(impure.status, RunStatus.won);
    expect(impure.avgPurity, lessThan(0.95));
    expect(impure.stars, 1);
  });

  test('out of sand when too few grains are left to reach the fill line', () {
    // 1100 blue grains: enough for 90% purity (1080) but not the 1200 fill line.
    final r = runFor(level(sand: [block('blue', 105, 200, 22, 50)]), 600);
    expect(r.status, RunStatus.outOfSand);
  });

  test('replay reproduces a run exactly', () {
    final l = level(
      sand: [block('blue', 105, 140, 30, 70), block('yellow', 160, 150, 20, 30)],
      valves: [
        {'rect': [95, 210, 50, 3]},
      ],
      walls: hopper,
    );
    final live = LevelRun(l);
    for (var t = 0; t < 700 && live.status == RunStatus.playing; t++) {
      if (t == 30) live.setGravityDegrees(-3.3);
      if (t == 60) live.toggleValve(0);
      if (t == 90) live.setSlowMo(true);
      if (t == 150) live.setSlowMo(false);
      if (t == 200) live.setGravityDegrees(2);
      live.step();
    }
    final replay = Replay.fromJson(live.toReplay().toJson());
    final again = LevelRun.play(l, replay, extraTicks: 0);
    expect(live.status, RunStatus.won);
    expect(again.tick, live.tick);
    expect(again.sim.stateHash(), live.sim.stateHash());
    expect(again.status, live.status);
  });

  test('validation catches broken levels', () {
    final bad = Level.fromJson(jsonEncode({
      'id': 'bad',
      'name': 'Bad',
      'sand': [block('blue', 10, 10, 5, 5)],
      'jars': [
        {'color': 'blue', 'rect': [230, 410, 40, 60], 'fill': 0.95},
      ],
      'filters': [
        {'color': 'blue', 'rect': [0, 100, 50, 4]},
      ],
    }));
    final p = bad.problems().join('\n');
    expect(p, contains('outside the field'));
    expect(p, contains('fill'));
    expect(p, contains('filter 0'));
    expect(p, contains('blue: jars need'));
    expect(level(sand: [block('blue', 105, 200, 30, 50)]).problems(), isEmpty);
  });
}
