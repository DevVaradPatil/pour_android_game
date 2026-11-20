import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pour_sand_game/game/palette.dart';
import 'package:pour_sand_game/meta/daily.dart';
import 'package:pour_sand_game/meta/economy.dart';
import 'package:pour_sand_game/meta/progress.dart';
import 'package:pour_sand_game/meta/save_data.dart';
import 'package:pour_sand_game/meta/save_store.dart';

void main() {
  group('daily number', () {
    test('counts calendar days from the epoch, whatever the time of day', () {
      expect(dailyNumber(DateTime(2026, 11, 20, 0, 1)), 1);
      expect(dailyNumber(DateTime(2026, 11, 20, 23, 59)), 1);
      expect(dailyNumber(DateTime(2026, 11, 21, 0, 0)), 2);
      expect(dailyNumber(DateTime(2027, 1, 1)), 43);
    });

    test('DST switch days and UTC vs local dates do not skip or repeat a day', () {
      // US and EU DST transitions in 2027.
      for (final (y, m, d) in [(2027, 3, 14), (2027, 3, 28), (2027, 10, 31), (2027, 11, 7)]) {
        final before = dailyNumber(DateTime(y, m, d - 1, 12));
        expect(dailyNumber(DateTime(y, m, d, 1, 30)), before + 1);
        expect(dailyNumber(DateTime(y, m, d, 23, 30)), before + 1);
        expect(dailyNumber(DateTime.utc(y, m, d, 12)), before + 1);
      }
    });

    test('clocks set before launch still get jar #1; the pool cycles', () {
      expect(dailyNumber(DateTime(2020)), 1);
      final pool = ['a', 'b', 'c'];
      expect([for (var n = 1; n <= 7; n++) dailyPath(n, pool)], ['a', 'b', 'c', 'a', 'b', 'c', 'a']);
    });
  });

  test('score: purity × speed, capped at 1000', () {
    expect(dailyScore(purity: 1, ticks: 300, parTicks: 300), 1000);
    expect(dailyScore(purity: 1, ticks: 450, parTicks: 300), 1000); // within 1.5× par
    expect(dailyScore(purity: 1, ticks: 900, parTicks: 300), 500);
    expect(dailyScore(purity: 0.9, ticks: 300, parTicks: 300), 900);
  });

  group('streak', () {
    test('consecutive days grow it; replaying a day changes nothing', () {
      final s = DailyStreak();
      s.complete(10);
      s.complete(11);
      s.complete(11);
      s.complete(12);
      expect((s.streak, s.best), (3, 3));
    });

    test('one missed day is covered by the weekly freeze, a second one that week is not', () {
      final s = DailyStreak()..complete(10)..complete(11);
      expect(s.complete(13), isTrue); // missed 12: freeze
      expect(s.streak, 3);
      expect(s.complete(15), weekOf(14) == weekOf(12) ? isFalse : isTrue);
    });

    test('two missed days reset it', () {
      final s = DailyStreak()..complete(10)..complete(11);
      s.complete(14);
      expect(s.streak, 1);
      expect(s.best, 2);
    });

    test('shown streak survives until it can no longer be saved', () {
      final s = DailyStreak()..complete(10)..complete(11);
      expect(s.current(11), 2);
      expect(s.current(12), 2); // not played yet today
      expect(s.current(13), 2); // yesterday missed, freeze still available
      expect(s.current(14), 0);
    });
  });

  group('reminder time', () {
    test('today at 7 pm if not done and still ahead, else tomorrow', () {
      expect(nextReminder(DateTime(2026, 11, 20, 9), doneToday: false), DateTime(2026, 11, 20, 19));
      expect(nextReminder(DateTime(2026, 11, 20, 20), doneToday: false), DateTime(2026, 11, 21, 19));
      expect(nextReminder(DateTime(2026, 11, 20, 9), doneToday: true), DateTime(2026, 11, 21, 19));
      expect(nextReminder(DateTime(2026, 12, 31, 22), doneToday: true), DateTime(2027, 1, 1, 19));
    });
  });

  test('share text', () {
    expect(
      shareText(
        number: 12,
        stars: 2,
        purity: 0.96,
        ticks: 754,
        jars: [(SandColor.blue, 1.0), (SandColor.yellow, 0.72)],
        streak: 5,
      ),
      'Pour · Daily Jar #12\n'
      '⭐⭐☆  96% pure · 0:13\n'
      '🟦🟦🟦🟦🟦\n'
      '🟨🟨🟨🟨⬛\n'
      '🔥 5-day streak\n'
      '$storeUrl',
    );
  });

  group('progress', () {
    test('first daily win of the day pays once and keeps the best score', () {
      final p = Progress();
      final first = p.recordDaily(3, score: 700, stars: 2, purity: 0.9, ticks: 400, jars: [(SandColor.red, 0.9)]);
      expect((first.first, first.coins, first.streak), (true, dailyCoins, 1));
      final again = p.recordDaily(3, score: 650, stars: 2, purity: 0.9, ticks: 450, jars: [(SandColor.red, 0.9)]);
      expect((again.first, again.coins, again.newBest), (false, 0, false));
      expect(p.data.dailyResult!['score'], 700);
      expect(p.dailyShare(3), contains('Daily Jar #3'));
      expect(p.dailyShare(4), isNull);
    });

    test('moving the clock back cannot replay old jars for coins', () {
      final p = Progress()..recordDaily(5, score: 900, stars: 3, purity: 1, ticks: 100, jars: const []);
      expect(p.dailyDone(3), isTrue);
      final back = p.recordDaily(3, score: 900, stars: 3, purity: 1, ticks: 100, jars: const []);
      expect(back.coins, 0);
      expect(p.data.daily.streak, 1);
    });

    test('a v1 save migrates to v2 with no daily history', () {
      final dir = Directory.systemTemp.createTempSync('pour_v1_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/save.json').writeAsStringSync(jsonEncode({
        'v': 1,
        'stars': {'w1/001': 3},
        'coins': 40,
        'settings': {'haptics': false},
      }));
      final d = SaveStore(dir).load();
      expect(d.coins, 40);
      expect(d.daily.last, 0);
      expect(d.settings.reminders, isFalse);
      expect(d.toJson()['v'], SaveData.version);
      expect(SaveData.version, 2);
    });
  });
}
