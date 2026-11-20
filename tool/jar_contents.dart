// Plays a level's solution and prints what each jar ended up holding, by color.
//   dart run tool/jar_contents.dart w1/020
// The first question when a jar fills but won't cork: who got in?
import 'dart:io';
import 'dart:typed_data';

import 'package:pour_sand_game/game/palette.dart';
import 'package:pour_sand_game/level/level.dart';
import 'package:pour_sand_game/level/level_run.dart';
import 'package:pour_sand_game/sim/sand_sim.dart';

void main(List<String> args) {
  final p = args.first;
  final level = Level.fromJson(File('assets/levels/$p.json').readAsStringSync());
  final run = LevelRun.play(level, Replay.fromJson(File('assets/levels/$p.replay.json').readAsStringSync()));
  stdout.writeln(run.summary());
  final c = Int32List(Cell.typeCount);
  for (final (i, j) in run.jars.indexed) {
    final r = j.def.r;
    run.sim.countRect(r.x, r.y, r.w, r.h, c);
    final parts = [for (final s in SandColor.values) if (c[s.cellType] > 0) '${s.name}=${c[s.cellType]}'];
    stdout.writeln('jar $i (${j.def.color.name}, x${r.x}..${r.x + r.w - 1}) needs ${j.def.target}: ${parts.join(' ')}'
        '${j.corked ? '  [corked]' : ''}');
  }
}
