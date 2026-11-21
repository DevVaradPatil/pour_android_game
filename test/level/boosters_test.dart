import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pour_sand_game/level/level.dart';
import 'package:pour_sand_game/level/level_run.dart';

Level load(String p) => Level.fromJson(File('assets/levels/$p.json').readAsStringSync());
Replay replayOf(String p) => Replay.fromJson(File('assets/levels/$p.replay.json').readAsStringSync());

/// Steps [run] to [tick], feeding [events] that are due.
void playTo(LevelRun run, List<List<int>> events, int tick) {
  var e = events.indexWhere((x) => x[0] >= run.tick);
  if (e < 0) e = events.length;
  while (run.tick < tick) {
    while (e < events.length && events[e][0] <= run.tick) {
      run.apply(events[e++]);
    }
    run.step();
  }
}

void main() {
  test('undo rewinds exactly: continuing afterwards matches a run that never went further', () {
    const p = 'w1/006';
    final level = load(p), r = replayOf(p);
    final plain = LevelRun(level);
    playTo(plain, r.events, r.ticks);

    final undone = LevelRun(level);
    playTo(undone, r.events, 250);
    undone.undo();
    expect(undone.tick, 60); // newest snapshot ≥ 180 ticks old
    expect(undone.events.every((e) => e[0] <= 60), isTrue);
    playTo(undone, r.events, r.ticks);

    expect(undone.sim.cells, plain.sim.cells);
    expect(undone.status, plain.status);
    expect(undone.stars, plain.stars);
  });

  test('undo near the start goes back to the start', () {
    final run = LevelRun(load('w1/001'))..setGravityDegrees(30);
    for (var i = 0; i < 90; i++) {
      run.step();
    }
    run.undo();
    expect(run.tick, 0);
    expect(run.sim.cells, LevelRun(load('w1/001')).sim.cells);
  });

  test('+Sand rescues an out-of-sand run, and its replay reproduces the result', () {
    final level = load('w1/001');
    final run = LevelRun(level)..setGravityDegrees(70); // pour it all off the right edge
    while (run.status == RunStatus.playing && run.tick < 3000) {
      run.step();
    }
    expect(run.status, RunStatus.outOfSand);
    for (var i = 0; i < 30; i++) {
      run.step(); // the app keeps settling while the card is up
    }
    final short = run.shortColors.toList();
    for (final c in short) {
      run.addSand(c);
    }
    expect(run.status, RunStatus.playing);
    for (final c in short) {
      expect(run.sim.count[c.cellType], greaterThan(0));
    }
    run.setGravityDegrees(0);
    final solution = replayOf('w1/001');
    final offset = run.tick;
    for (final e in solution.events) {
      run.apply([e[0] + offset, e[1], e[2]]);
    }
    while (run.status == RunStatus.playing && run.tick < offset + 1500) {
      run.step();
    }

    final again = LevelRun.play(level, run.toReplay(), extraTicks: 0);
    expect(again.sim.cells, run.sim.cells);
    expect(again.status, run.status);
  });
}
