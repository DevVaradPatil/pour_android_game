// The player's progress: the save file plus the rules that change it.
// Every mutation saves and notifies, so screens just listen.
import 'package:flutter/foundation.dart';

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
