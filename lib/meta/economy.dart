// Coin and chest rules. Pure functions; tuned in one place.

const int starsPerChest = 20;
const int chestCoins = 50;

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

class Reward {
  const Reward({this.levelCoins = 0, this.streakBonus = 0, this.streak = 0});
  final int levelCoins, streakBonus, streak;
  int get total => levelCoins + streakBonus;
}
