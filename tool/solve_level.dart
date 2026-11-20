// Brute-forces simple tilt scripts for a level, to find and record a solution replay.
//   dart compile exe tool/solve_level.dart -o build/solve.exe
//   build/solve.exe w1/001                 try "hold angle A from tick 30 for T ticks, then 0"
//   build/solve.exe w1/001 --write         also write the best result to <level>.replay.json
//   build/solve.exe w1/003 --valves 0@20   toggle valve 0 at tick 20 in every candidate
//   build/solve.exe w1/002 --two           "angle A for T1, then the other way B for T2, then 0"
// The count of winning scripts is the level's forgiveness: few wins = fragile level.
import 'dart:io';

import 'package:pour_sand_game/level/level.dart';
import 'package:pour_sand_game/level/level_run.dart';

void main(List<String> args) {
  final path = args.first;
  final write = args.contains('--write');
  final valveArg = args.indexOf('--valves');
  final valves = valveArg < 0
      ? <List<int>>[]
      : [
          for (final v in args[valveArg + 1].split(','))
            [int.parse(v.split('@')[1]), 1, int.parse(v.split('@')[0])],
        ];
  final level = Level.fromJson(File('assets/levels/$path.json').readAsStringSync());
  final results = <(int stars, int tick, double spill, Replay r)>[];
  void attempt(List<List<int>> tilts, int end) {
    final events = [...valves, ...tilts]..sort((x, y) => x[0].compareTo(y[0]));
    final run = LevelRun.play(level, Replay(level.id, events, end), extraTicks: 900);
    if (run.status == RunStatus.won) {
      results.add((run.stars, run.tick, run.spill, Replay(level.id, events, run.tick, stars: run.stars)));
    }
  }

  if (args.contains('--two')) {
    for (final sign in [1, -1]) {
      for (final a in [38, 44, 50]) {
        for (final t1 in [60, 120, 240]) {
          for (final b in [38, 44, 50]) {
            for (final t2 in [60, 120, 240]) {
              final s1 = 30 + t1, s2 = s1 + t2;
              attempt([
                [30, 0, sign * a * 2],
                [s1, 0, -sign * b * 2],
                [s2, 0, 0],
              ], s2);
            }
          }
        }
      }
    }
  } else {
    for (final sign in [1, -1]) {
      for (var a = 10; a <= 66; a += 4) {
        for (final hold in [60, 120, 180, 240, 330, 450, 600]) {
          attempt([
            [30, 0, sign * a * 2],
            [30 + hold, 0, 0],
          ], 30 + hold);
        }
      }
    }
  }
  results.sort((a, b) => a.$1 != b.$1 ? b.$1.compareTo(a.$1) : a.$2.compareTo(b.$2));
  stdout.writeln('${results.length} winning scripts');
  for (final (stars, tick, spill, r) in results.take(40)) {
    stdout.writeln('  $stars★ t=$tick spill=${(spill * 100).toStringAsFixed(1)}%  ${r.events}');
  }
  if (write && results.isNotEmpty) {
    File('assets/levels/$path.replay.json').writeAsStringSync('${results.first.$4.toJson()}\n');
    stdout.writeln('wrote assets/levels/$path.replay.json');
  }
}
