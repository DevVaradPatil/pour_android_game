// The player's progress: the save file plus the rules that change it.
// Every mutation saves and notifies, so screens just listen.
import 'package:flutter/foundation.dart';

import '../game/palette.dart';
import 'daily.dart';
import 'economy.dart';
import 'save_data.dart';
import 'save_store.dart';

class Progress extends ChangeNotifier {
  /// [store] null = in memory only (tests, previews).
  Progress([this._store]) : data = _store?.load() ?? SaveData();

  final SaveStore? _store;
  final SaveData data;

  int starsFor(String path) => data.stars[path] ?? 0;
  int get chestsReady => chestsEarned(data.totalStars) - data.chestsOpened;
  Settings get settings => data.settings;
  bool get removeAds => data.owned.contains(removeAdsId) || data.owned.contains(starterPackId);

  /// Pays [coins] if there are enough; false (and no change) otherwise.
  bool spend(int coins) {
    if (data.coins < coins) return false;
    data.coins -= coins;
    _changed();
    return true;
  }

  void addCoins(int coins) {
    data.coins += coins;
    _changed();
  }

  /// A store purchase arrived (bought or restored). Grants it once per save;
  /// false if this save already had it.
  bool grant(String product) {
    if (!data.owned.add(product)) return false;
    if (product == starterPackId) data.coins += starterPackCoins;
    _changed();
    return true;
  }

  /// A level was won. Keeps the best stars, pays coins for improvements and
  /// streak milestones.
  Reward recordWin(String path, int stars, {required bool boss}) {
    final old = starsFor(path);
    final coins = levelCoins(oldStars: old, newStars: stars, boss: boss);
    if (stars > old) data.stars[path] = stars;
    data.winStreak++;
    final bonus = streakBonus(data.winStreak);
    data.coins += coins + bonus;
    _changed();
    return Reward(levelCoins: coins, streakBonus: bonus, streak: data.winStreak);
  }

  /// Ran out of sand or restarted mid-level: the win streak ends.
  void recordFail() {
    if (data.winStreak == 0) return;
    data.winStreak = 0;
    _changed();
  }

  /// Opens one ready chest; returns the coins it held (0 if none was ready).
  int openChest() {
    if (chestsReady <= 0) return 0;
    data.chestsOpened++;
    data.coins += chestCoins;
    _changed();
    return chestCoins;
  }

  /// Days up to the last completed one count as done, so moving the clock
  /// back can't replay old jars for coins or streak.
  bool dailyDone(int day) => data.daily.last >= day;

  /// A Daily Jar was won. Keeps the day's best score; the first win of the day
  /// pays [dailyCoins] and advances the daily streak (spending the weekly
  /// freeze for a single missed day).
  DailyOutcome recordDaily(
    int day, {
    required int score,
    required int stars,
    required double purity,
    required int ticks,
    required List<(SandColor, double)> jars,
  }) {
    final first = !dailyDone(day);
    final usedFreeze = first && data.daily.complete(day);
    final prev = data.dailyResult;
    final prevScore = prev != null && prev['n'] == day ? (prev['score'] as num).toInt() : -1;
    final best = score > prevScore;
    if (best) {
      data.dailyResult = {
        'n': day,
        'score': score,
        'stars': stars,
        'purity': purity,
        'ticks': ticks,
        'jars': [
          for (final (c, p) in jars) [c.name, p],
        ],
      };
    }
    if (first) data.coins += dailyCoins;
    _changed();
    return DailyOutcome(
      first: first,
      newBest: best,
      coins: first ? dailyCoins : 0,
      streak: data.daily.streak,
      usedFreeze: usedFreeze,
    );
  }

  /// Share text for [day]'s best result, or null if it isn't done.
  String? dailyShare(int day) {
    final r = data.dailyResult;
    if (r == null || r['n'] != day) return null;
    return shareText(
      number: day,
      stars: (r['stars'] as num).toInt(),
      purity: (r['purity'] as num).toDouble(),
      ticks: (r['ticks'] as num).toInt(),
      jars: [
        for (final j in (r['jars'] as List).cast<List>())
          (SandColor.values.byName(j[0] as String), (j[1] as num).toDouble()),
      ],
      streak: data.daily.current(day),
    );
  }

  void markTileSeen(String key) {
    if (data.seenTiles.add(key)) _changed();
  }

  void updateSettings(void Function(Settings s) change) {
    change(data.settings);
    _changed();
  }

  void _changed() {
    _store?.save(data);
    notifyListeners();
  }
}

/// App-wide progress. In memory until main() swaps in the file-backed one.
Progress progress = Progress();
