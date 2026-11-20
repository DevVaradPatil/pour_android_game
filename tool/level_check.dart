// Validates every level in assets/levels/levels.json and plays its solution replay.
//   dart run tool/level_check.dart            all levels
//   dart run tool/level_check.dart -v w1/003  one level, with a per-second trace
// Exits 1 if any level fails.
import 'dart:io';

import 'package:pour_sand_game/level/level_check.dart';

void main(List<String> args) {
  final verbose = args.contains('-v');
  final filter = args.where((a) => !a.startsWith('-')).firstOrNull;
  final paths = parseLevelIndex(File('assets/levels/levels.json').readAsStringSync());
  var failed = 0;
  for (final p in paths) {
    if (filter != null && !p.contains(filter)) continue;
    final replay = File('assets/levels/$p.replay.json');
    final r = checkLevel(
      p,
      File('assets/levels/$p.json').readAsStringSync(),
      replay.existsSync() ? replay.readAsStringSync() : null,
      onTick: verbose ? (run) => run.tick % 60 == 0 ? stdout.writeln('  ${run.summary()}') : null : null,
    );
    stdout.writeln('${r.ok ? 'OK  ' : 'FAIL'} $p  ${r.summary}');
    for (final pr in r.problems) {
      stdout.writeln('      - $pr');
    }
    if (!r.ok) failed++;
  }
  stdout.writeln(failed == 0 ? 'all levels OK' : '$failed level(s) failed');
  exit(failed == 0 ? 0 : 1);
}
