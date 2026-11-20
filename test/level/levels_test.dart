import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pour_sand_game/level/level_check.dart';

/// Every shipped level must validate and its recorded solution must still win
/// with the recorded stars. Catches sim/rule changes that break levels.
void main() {
  final paths = [
    ...parseLevelIndex(File('assets/levels/levels.json').readAsStringSync()),
    ...parseLevelIndex(File('assets/levels/daily.json').readAsStringSync()),
  ];
  for (final p in paths) {
    test('level $p is valid and solvable', () {
      final replay = File('assets/levels/$p.replay.json');
      final r = checkLevel(
        p,
        File('assets/levels/$p.json').readAsStringSync(),
        replay.existsSync() ? replay.readAsStringSync() : null,
      );
      expect(r.problems, isEmpty, reason: r.summary);
    });
  }
}
