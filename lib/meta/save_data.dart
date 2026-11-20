// Everything the player keeps between sessions. Pure Dart; one JSON document.
// Bump [SaveData.version] and add a step to [migrate] when the shape changes.

class Settings {
  double sensitivity = 1.0;
  double deadZone = 3.0;
  bool invert = false;
  bool touchOnly = false; // ignore the tilt sensor; drag to tilt
  bool sound = true;
  bool music = true;
  bool haptics = true;

  Map<String, Object?> toJson() => {
        'sensitivity': sensitivity,
        'deadZone': deadZone,
        'invert': invert,
        'touchOnly': touchOnly,
        'sound': sound,
        'music': music,
        'haptics': haptics,
      };

  static Settings fromJson(Map<String, Object?> m) => Settings()
    ..sensitivity = (m['sensitivity'] as num?)?.toDouble() ?? 1.0
    ..deadZone = (m['deadZone'] as num?)?.toDouble() ?? 3.0
    ..invert = m['invert'] as bool? ?? false
    ..touchOnly = m['touchOnly'] as bool? ?? false
    ..sound = m['sound'] as bool? ?? true
    ..music = m['music'] as bool? ?? true
    ..haptics = m['haptics'] as bool? ?? true;
}

class SaveData {
  SaveData({
    Map<String, int>? stars,
    this.coins = 0,
    this.winStreak = 0,
    this.chestsOpened = 0,
    Set<String>? seenTiles,
    Settings? settings,
  })  : stars = stars ?? {},
        seenTiles = seenTiles ?? {},
        settings = settings ?? Settings();

  static const int version = 1;

  /// Best stars per level path ("w1/001").
  final Map<String, int> stars;
  int coins;

  /// Levels won in a row without a fail or restart.
  int winStreak;
  int chestsOpened;

  /// Album tiles whose reveal animation has been shown ("picture:tile").
  final Set<String> seenTiles;
  Settings settings;

  int get totalStars => stars.values.fold(0, (a, b) => a + b);

  Map<String, Object?> toJson() => {
        'v': version,
        'stars': stars,
        'coins': coins,
        'winStreak': winStreak,
        'chestsOpened': chestsOpened,
        'seenTiles': seenTiles.toList()..sort(),
        'settings': settings.toJson(),
      };

  /// Reads any known version (unknown fields are ignored).
  static SaveData fromJson(Map<String, Object?> raw) {
    final m = migrate(raw);
    return SaveData(
      stars: {for (final e in (m['stars'] as Map? ?? const {}).entries) e.key as String: (e.value as num).toInt()},
      coins: (m['coins'] as num?)?.toInt() ?? 0,
      winStreak: (m['winStreak'] as num?)?.toInt() ?? 0,
      chestsOpened: (m['chestsOpened'] as num?)?.toInt() ?? 0,
      seenTiles: {...((m['seenTiles'] as List?) ?? const []).cast<String>()},
      settings: Settings.fromJson((m['settings'] as Map?)?.cast<String, Object?>() ?? const {}),
    );
  }

  /// Upgrades an older document step by step to [version].
  static Map<String, Object?> migrate(Map<String, Object?> m) {
    var v = (m['v'] as num?)?.toInt() ?? 0;
    final out = Map<String, Object?>.from(m);
    if (v == 0) {
      // v0 (pre-release builds): stars only, under "levels".
      out['stars'] ??= out.remove('levels');
      v = 1;
    }
    out['v'] = v;
    return out;
  }
}
