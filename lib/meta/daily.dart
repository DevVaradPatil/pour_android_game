// Daily Jar rules. Pure Dart: dates, score, streak, reminder timing, share text.
//
// No server: the jar is picked from the bundled pool by the player's *local
// calendar date* (like Wordle), so everyone on the same date plays the same jar.
import 'dart:math' as math;

import '../game/palette.dart';

/// Dev builds can step the daily clock forward to test rollover and streaks.
int debugDayOffset = 0;
DateTime dailyClock() => DateTime.now().add(Duration(days: debugDayOffset));

/// Daily Jar #1.
final DateTime dailyEpoch = DateTime.utc(2026, 11, 20);

/// Days are counted on calendar dates, so DST shifts and time zones can't
/// skip or repeat a day.
int dailyNumber(DateTime local) {
  final date = DateTime.utc(local.year, local.month, local.day);
  return math.max(1, date.difference(dailyEpoch).inDays + 1);
}

/// The pool cycles; [pool] is assets/levels/daily.json.
String dailyPath(int number, List<String> pool) => pool[(number - 1) % pool.length];

/// 0–1000: purity × speed, where finishing within 1.5× the solution's time
/// counts as full speed.
int dailyScore({required double purity, required int ticks, required int parTicks}) {
  final speed = ticks <= 0 ? 1.0 : math.min(1.0, parTicks * 1.5 / ticks);
  return (1000 * purity * speed).round().clamp(0, 1000);
}

/// Week index for the one-freeze-per-week rule.
int weekOf(int day) => (day + 3) ~/ 7;

class DailyStreak {
  DailyStreak({this.last = 0, this.streak = 0, this.best = 0, this.freezeWeek = -1});

  int last; // last completed daily number (0 = never)
  int streak;
  int best;
  int freezeWeek; // week whose freeze was spent (-1 = none yet)

  /// Records completing [day]. A single missed day is covered by that week's
  /// freeze; returns true if the freeze was spent.
  bool complete(int day) {
    if (day <= last) return false;
    var usedFreeze = false;
    final gap = day - last;
    if (last == 0 || gap > 2) {
      streak = 1;
    } else if (gap == 1) {
      streak++;
    } else if (freezeWeek != weekOf(day - 1)) {
      freezeWeek = weekOf(day - 1);
      usedFreeze = true;
      streak++;
    } else {
      streak = 1;
    }
    last = day;
    best = math.max(best, streak);
    return usedFreeze;
  }

  /// Streak to show on [today]: still alive if today or yesterday is done, or
  /// if only yesterday was missed and that week's freeze is unused.
  int current(int today) {
    if (last == today || last == today - 1) return streak;
    if (last == today - 2 && freezeWeek != weekOf(today - 1)) return streak;
    return 0;
  }
}

/// When to remind: today at [hour] if today's jar isn't done and that's still
/// ahead, otherwise tomorrow at [hour]. One reminder a day at most.
DateTime nextReminder(DateTime now, {required bool doneToday, int hour = 19}) {
  final today = DateTime(now.year, now.month, now.day, hour);
  return !doneToday && now.isBefore(today) ? today : DateTime(now.year, now.month, now.day + 1, hour);
}

const _squares = {
  SandColor.blue: '🟦',
  SandColor.yellow: '🟨',
  SandColor.red: '🟥',
  SandColor.green: '🟩',
  SandColor.purple: '🟪',
  SandColor.orange: '🟧',
  SandColor.white: '⬜',
  SandColor.black: '⬛',
};

// TODO(owner): final store listing URL once the application ID is decided (TODO.md).
const storeUrl = 'https://play.google.com/store/apps/details?id=com.pourgame.pour_sand_game';

/// Wordle-style share text: one row per jar, five squares showing its purity.
String shareText({
  required int number,
  required int stars,
  required double purity,
  required int ticks,
  required List<(SandColor, double)> jars,
  required int streak,
}) {
  final secs = (ticks / 60).round();
  final time = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
  final rows = [
    for (final (c, p) in jars) List.generate(5, (i) => i < (p * 5).round().clamp(1, 5) ? _squares[c]! : '⬛').join(),
  ];
  return [
    'Pour · Daily Jar #$number',
    '${'⭐' * stars}${'☆' * (3 - stars)}  ${(purity * 100).round()}% pure · $time',
    ...rows,
    if (streak > 1) '🔥 $streak-day streak',
    storeUrl,
  ].join('\n');
}
