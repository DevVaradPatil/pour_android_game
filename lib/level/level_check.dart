// Validates a level and plays its recorded solution headlessly.
// Shared by tool/level_check.dart (CLI) and test/level/levels_test.dart.
import 'dart:convert';

import 'level.dart';
import 'level_run.dart';

class LevelCheckResult {
  LevelCheckResult(this.path, this.problems, this.summary);
  final String path;
  final List<String> problems;
  final String summary;
  bool get ok => problems.isEmpty;
}

LevelCheckResult checkLevel(String path, String levelJson, String? replayJson, {void Function(LevelRun)? onTick}) {
  final Level level;
  try {
    level = Level.fromJson(levelJson);
  } on Object catch (e) {
    return LevelCheckResult(path, ['does not parse: $e'], '');
  }
  final problems = level.problems();
  if (replayJson == null) return LevelCheckResult(path, [...problems, 'no solution replay'], '');
  final replay = Replay.fromJson(replayJson);
  if (replay.levelId != level.id) problems.add('replay is for ${replay.levelId}, level is ${level.id}');
  final run = LevelRun.play(level, replay, onTick: onTick);
  if (run.status != RunStatus.won) problems.add('solution replay ends ${run.status.name}, not won');
  if (run.stars < replay.stars) problems.add('solution earned ${run.stars} stars, recorded ${replay.stars}');
  return LevelCheckResult(path, problems, run.summary());
}

/// assets/levels/levels.json: ordered paths relative to assets/levels/, e.g. "w1/001".
List<String> parseLevelIndex(String json) => (jsonDecode(json) as List).cast<String>();
