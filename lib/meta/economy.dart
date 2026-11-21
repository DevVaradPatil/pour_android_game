// Coin and chest rules. Pure functions; tuned in one place.

const int starsPerChest = 20;
const int chestCoins = 50;

// Store products (Play Console / App Store Connect ids, see TODO.md).
const String removeAdsId = 'remove_ads', starterPackId = 'starter_pack';
const int starterPackCoins = 500;

/// Boosters: coins, or a rewarded ad instead.
const int undoCoins = 30, sandCoins = 40;

/// Interstitials: only after a win, from level 15 on, at least 3 minutes after
/// the last one (and after app start), never for Remove Ads owners.
const Duration interstitialGap = Duration(minutes: 3);
bool interstitialDue({required int level, required Duration sinceLast, required bool removeAds}) =>
    !removeAds && level >= 15 && sinceLast >= interstitialGap;

/// Coins for the first Daily Jar win of each day.
const int dailyCoins = 20;

/// Coins for a win: a first clear pays 10, every newly earned star pays 5,
/// bosses pay double. Replays that don't improve pay nothing.
int levelCoins({required int oldStars, required int newStars, required bool boss}) {
  if (newStars <= oldStars) return 0;
  final first = oldStars == 0 ? 10 : 0;
  return (first + 5 * (newStars - oldStars)) * (boss ? 2 : 1);
}

/// Bonus for reaching a win streak of 3, 5 or 10 levels without a fail or restart.
int streakBonus(int streak) => switch (streak) {
  3 => 10,
  5 => 20,
  10 => 50,
  _ => 0,
};

/// Chests unlocked so far by total stars (one per [starsPerChest]).
int chestsEarned(int totalStars) => totalStars ~/ starsPerChest;

class DailyOutcome {
  const DailyOutcome({
    required this.first,
    required this.newBest,
    required this.coins,
    required this.streak,
    required this.usedFreeze,
  });
  final bool first, newBest, usedFreeze;
  final int coins, streak;
}

class Reward {
  const Reward({this.levelCoins = 0, this.streakBonus = 0, this.streak = 0});
  final int levelCoins, streakBonus, streak;
  int get total => levelCoins + streakBonus;
}
