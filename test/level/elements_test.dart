import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pour_sand_game/game/palette.dart';
import 'package:pour_sand_game/level/level.dart';
import 'package:pour_sand_game/level/level_run.dart';
import 'package:pour_sand_game/sim/sand_sim.dart';

Level lvl(Map<String, Object> m) => Level.fromJson(jsonEncode({'id': 't', 'name': 't', 'seed': 7, ...m}));

Map<String, Object> block(String color, int x, int y, int w, int h) => {'color': color, 'rect': [x, y, w, h]};

LevelRun runFor(Level l, int ticks) {
  final r = LevelRun(l);
  for (var t = 0; t < ticks && r.status == RunStatus.playing; t++) {
    r.step();
  }
  return r;
}

void main() {
  test('mixOf covers the three secondaries and nothing else', () {
    expect(mixOf(SandColor.blue, SandColor.yellow), SandColor.green);
    expect(mixOf(SandColor.yellow, SandColor.red), SandColor.orange);
    expect(mixOf(SandColor.red, SandColor.blue), SandColor.purple);
    expect(mixOf(SandColor.blue, SandColor.blue), isNull);
    expect(mixOf(SandColor.green, SandColor.blue), isNull);
  });

  test('blue and yellow falling through a mixer fill a green jar', () {
    final r = runFor(
      lvl({
        'sand': [block('blue', 100, 60, 20, 40), block('yellow', 120, 60, 20, 40)],
        'mixers': [
          {'rect': [90, 110, 60, 80]},
        ],
        'jars': [
          {'color': 'green', 'rect': [95, 300, 50, 40], 'fill': 0.5, 'purity': 0.8},
        ],
      }),
      900,
    );
    expect(r.status, RunStatus.won);
    expect(r.jars.single.purity, greaterThanOrEqualTo(0.8));
  });

  test('a green jar with no mixer and no green sand is not winnable (validation)', () {
    final l = lvl({
      'sand': [block('blue', 100, 60, 20, 40), block('yellow', 120, 60, 20, 40)],
      'jars': [
        {'color': 'green', 'rect': [95, 300, 50, 40], 'fill': 0.5},
      ],
    });
    expect(l.problems().join(), contains('green: jars need'));
  });

  test('out-of-sand counts primaries as potential secondaries only with a mixer', () {
    Map<String, Object> m({bool mixer = true}) => {
          'sand': [block('blue', 10, 380, 20, 20), block('yellow', 30, 380, 20, 20)], // never reach the jar
          if (mixer)
            'mixers': [
              {'rect': [0, 0, 10, 10]},
            ],
          'jars': [
            {'color': 'green', 'rect': [150, 300, 30, 30], 'fill': 0.3},
          ],
        };
    // The sand drops into the void within a few ticks; then both runs are short.
    expect(runFor(lvl(m()), 200).status, RunStatus.outOfSand);
    expect(LevelRun(lvl(m())).status, RunStatus.playing); // at start, primaries count
  });

  test('a fan pushes a falling stream sideways; toggling it is replayable', () {
    final l = lvl({
      'sand': [block('blue', 110, 20, 20, 60)],
      'fans': [
        {'rect': [0, 150, 240, 60], 'dir': 1, 'strength': 2},
      ],
      'jars': [
        {'color': 'blue', 'rect': [145, 330, 60, 40], 'fill': 0.4, 'purity': 0.8},
      ],
    });
    final off = runFor(l, 400);
    expect(off.jars.single.total, 0); // straight down misses the jar

    final live = LevelRun(l);
    live.toggleFan(0);
    for (var t = 0; t < 600 && live.status == RunStatus.playing; t++) {
      live.step();
    }
    expect(live.status, RunStatus.won);
    final again = LevelRun.play(l, Replay.fromJson(live.toReplay().toJson()), extraTicks: 0);
    expect(again.sim.stateHash(), live.sim.stateHash());
  });

  test('shiftGrains conserves sand and loses only what leaves the field', () {
    final sim = SandSim(20, 10);
    sim.fillRect(15, 2, 5, 3, Cell.firstSand);
    for (var i = 0; i < 3; i++) {
      sim.shiftGrains(0, 0, 20, 10, 1);
    }
    expect(sim.grains + sim.lost[Cell.firstSand], 15);
    expect(sim.lost[Cell.firstSand], 9); // three columns pushed out
  });

  test('a frame expands into a row of slots sharing walls', () {
    final l = lvl({
      'sand': [block('red', 60, 50, 40, 40)],
      'frames': [
        {'x': 60, 'y': 300, 'slot': [8, 12], 'colors': ['red', 'orange', 'yellow']},
      ],
    });
    expect(l.jars.map((j) => j.color), [SandColor.red, SandColor.orange, SandColor.yellow]);
    expect(l.jars.every((j) => j.slot), isTrue);
    expect([for (final j in l.jars) j.r.x], [60, 70, 80]);
    final sim = l.build();
    final c = Int32List(Cell.typeCount);
    sim.countRect(68, 300, 2, 12, c); // wall between slot 0 and 1
    expect(c[Cell.wall], 24);
  });
}
