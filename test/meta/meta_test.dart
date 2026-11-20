import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pour_sand_game/game/palette.dart';
import 'package:pour_sand_game/meta/album.dart';
import 'package:pour_sand_game/meta/economy.dart';
import 'package:pour_sand_game/meta/progress.dart';
import 'package:pour_sand_game/meta/save_data.dart';
import 'package:pour_sand_game/meta/save_store.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('pour_save_'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('save store', () {
    test('round-trips everything', () {
      final store = SaveStore(dir);
      final d = SaveData(stars: {'w1/001': 3, 'w1/002': 1}, coins: 120, winStreak: 4, chestsOpened: 1)
        ..seenTiles.add('0:1')
        ..settings.sensitivity = 1.4
        ..settings.touchOnly = true
        ..settings.haptics = false;
      store.save(d);
      final back = store.load();
      expect(back.toJson(), d.toJson());
    });

    test('a corrupted save falls back to the backup', () {
      final store = SaveStore(dir);
      store.save(SaveData(coins: 10));
      store.save(SaveData(coins: 20)); // backup now holds coins: 10
      File('${dir.path}/save.json').writeAsStringSync('{"v":1,"coins":'); // torn write
      expect(store.load().coins, 10);
    });

    test('both files unreadable → fresh start instead of a crash', () {
      File('${dir.path}/save.json').writeAsStringSync('not json');
      File('${dir.path}/save.bak.json').writeAsStringSync('[]');
      expect(SaveStore(dir).load().coins, 0);
    });

    test('a leftover temp file from a crash is ignored', () {
      final store = SaveStore(dir)..save(SaveData(coins: 7));
      File('${dir.path}/save.tmp').writeAsStringSync('garbage');
      expect(store.load().coins, 7);
      store.save(SaveData(coins: 8));
      expect(store.load().coins, 8);
    });

    test('migrates a v0 save and ignores unknown fields', () {
      final v0 = {
        'levels': {'w1/001': 2},
        'coins': 5,
        'somethingNew': true,
      };
      File('${dir.path}/save.json').writeAsStringSync(jsonEncode(v0));
      final d = SaveStore(dir).load();
      expect(d.stars, {'w1/001': 2});
      expect(d.coins, 5);
      expect(d.toJson()['v'], SaveData.version);
    });
  });

  group('economy', () {
    test('level coins: first clear, improvements only, bosses double', () {
      expect(levelCoins(oldStars: 0, newStars: 1, boss: false), 15);
      expect(levelCoins(oldStars: 0, newStars: 3, boss: false), 25);
      expect(levelCoins(oldStars: 1, newStars: 3, boss: false), 10);
      expect(levelCoins(oldStars: 3, newStars: 2, boss: false), 0);
      expect(levelCoins(oldStars: 0, newStars: 3, boss: true), 50);
    });

    test('streak milestones and chests', () {
      expect([for (var i = 1; i <= 10; i++) streakBonus(i)], [0, 0, 10, 0, 20, 0, 0, 0, 0, 50]);
      expect(chestsEarned(19), 0);
      expect(chestsEarned(40), 2);
    });
  });

  group('progress', () {
    test('wins pay coins, keep best stars, build a streak; fails reset it', () {
      final p = Progress();
      expect(p.recordWin('w1/001', 2, boss: false).total, 20);
      expect(p.recordWin('w1/001', 1, boss: false).total, 0); // worse replay
      expect(p.starsFor('w1/001'), 2);
      final third = p.recordWin('w1/002', 3, boss: false);
      expect(third.streak, 3);
      expect(third.streakBonus, 10);
      p.recordFail();
      expect(p.data.winStreak, 0);
    });

    test('chests open once per 20 stars', () {
      final p = Progress();
      for (var i = 1; i <= 7; i++) {
        p.recordWin('w1/00$i', 3, boss: false);
      }
      expect(p.chestsReady, 1);
      final before = p.data.coins;
      expect(p.openChest(), chestCoins);
      expect(p.data.coins, before + chestCoins);
      expect(p.openChest(), 0);
    });

    test('every change is saved', () {
      Progress(SaveStore(dir))
        ..recordWin('w1/005', 3, boss: false)
        ..updateSettings((s) => s.invert = true);
      final again = Progress(SaveStore(dir));
      expect(again.starsFor('w1/005'), 3);
      expect(again.settings.invert, isTrue);
    });
  });

  group('album', () {
    test('six pictures of ten tiles cover sixty levels; bosses finish pictures', () {
      expect(world1Album.length * tilesPerPicture, 60);
      expect(tileOf(0), (0, 0));
      expect(tileOf(9), (0, 9)); // level 10, the first boss: last tile of picture 1
      expect(tileOf(59), (5, 9));
    });

    test('every tile has some detail and avoids invisible black sand', () {
      for (final pic in world1Album) {
        final colors = pic.pixels.map((i) => SandColor.values[i]).toSet();
        expect(colors.contains(SandColor.black), isFalse, reason: pic.name);
        expect(colors.length, greaterThan(2), reason: pic.name);
      }
    });
  });
}
