# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is
"Pour": a portrait, tilt-to-pour colored-sand puzzle game in Flutter. It's Android-first; iOS stays buildable but is untested until a Mac is available.
- [pour-game-design.md](pour-game-design.md) is the game design doc. It defines *what* to build: mechanics, levels, meta, monetization.
- [PLAN.md](PLAN.md) holds the phased build plan and the test gate for each phase. Update its checkboxes as work lands.
- [TODO.md](TODO.md) lists owner-only items (keys, accounts, devices, decisions). Add to it whenever you're blocked on one of those, instead of guessing or hard-coding.

## Commands (Windows PowerShell 5.1: chain with `;`, never `&&`)
```powershell
flutter analyze; flutter test
flutter test test/path/to/file_test.dart          # one file
flutter test --plain-name "determinism"           # one test by name
flutter build apk --profile --target-platform android-x64
adb install -r build\app\outputs\flutter-apk\app-profile.apk; adb shell am start -n com.pourgame.pour_sand_game/.MainActivity
adb emu sensor set acceleration -6.3:7.5:0        # fake tilt: right edge down ~37° (x<0 = right edge down; upright 0:9.81:0)
dart compile exe tool/bench_sim.dart -o build/bench.exe; ./build/bench.exe   # sim benchmark (AOT, like the app)
```
- Emulator: AVD `Medium_Phone_API_36.1` (x86_64). Its data partition is nearly full, so the **debug APK doesn't install**. Use profile builds until TODO.md's storage item is resolved.
- `android/gradle.properties` has `kotlin.incremental=false`: the project is on E: and the pub cache on C:, which breaks Kotlin incremental caches ("Could not close incremental caches").
- Emulator fps is only a rough signal. After a long session it dropped to 30 vsyncs/s even when idle; a fresh boot gives 60 vsync and ~54 fps with sand moving. Trust the overlay's `ticks` (should be 60), the bench, and a real phone.
- Level workflow: levels are **code** in `tool/build_levels.dart` (helpers + each level's intended solution); never hand-edit `assets/levels/w1/*.json`. Run `dart compile exe tool/build_levels.dart -o build/build_levels.exe; ./build/build_levels.exe [N ...]` to write JSON + replays and get a won/stars report. To diagnose: `flutter test tool/level_preview_test.dart --dart-define=LEVEL=w1/NNN` (frames in `build/level_previews/`), `dart run tool/jar_contents.dart w1/NNN` (who's in each jar). Then `./build/level_report.exe` (from `tool/level_report.dart`) refreshes `docs/levels-w1.md`. Follow the level-design rules in PLAN.md Phase 3.
- On-device check of all levels: dev home → "Autoplay all", then `adb logcat -d | grep AUTOPLAY` must match the builder's report.
- Brand pipeline: the logo is code (`lib/ui/brand.dart`). After changing it, run `flutter test tool/brand_export_test.dart; dart run flutter_launcher_icons; dart run flutter_native_splash:create`. The splash generator **rewrites AndroidManifest.xml and drops `screenOrientation`**; `test/platform_config_test.dart` catches that.
- Golden: `flutter test test/ui/gallery_golden_test.dart --update-goldens` after intended UI changes. Goldens are rendered on Windows.
- UI rules: use tokens from `lib/ui/tokens.dart` (`PourColors`, `Space`, `Radii`, `Motion`, `PourText`), never raw colors. Every sand color is `SandColor`; show its glyph wherever color carries meaning. `test/ui/palette_test.dart` enforces ΔE2000 ≥ 12.5 under colorblind simulation and WCAG AA for text tokens.
- Screenshots: PowerShell `>` corrupts binary output. Use Git Bash: `MSYS_NO_PATHCONV=1 adb shell screencap -p /sdcard/s.png; adb pull /sdcard/s.png <dest>`.
- "Done" means `flutter analyze` and `flutter test` are clean **and** the change has been checked on the emulator: install, launch, drive tilt if relevant, screenshot, and check logcat for errors.

## Architecture (see PLAN.md §1)
- `lib/sim/sand_sim.dart` is a **pure Dart** cellular-automaton sand sim with no Flutter imports, a seeded RNG and a fixed 60 Hz step. It must stay deterministic: the same seed plus the same input stream gives an identical grid. Recorded level replays depend on this and serve as regression tests. The sim exposes counters (`moved`, `lost`, `grains`) and never calls out to audio, UI or anything else.
  - Randomness is a stateless hash of (x, y, tick, seed), and a grain's rest decision depends only on cells within 2 of it. That's why 16×16 chunks can sleep and still match processing everything exactly (`test/sim`). Keep both properties when adding elements, or widen the wake radius in `_wake`.
  - Moves: try the gravity direction (weighted between the two nearest of 8), then neighbours. A direction is allowed if it's within the repose cone. A shallow downhill direction is allowed only off a ledge (`_unsupported`).
  - Walls must be 4-connected (`line()` uses thickness ≥ 2), or sand leaks through diagonal gaps.
- Levels are JSON shape lists (`lib/level/level.dart`). `LevelRun` (`lib/level/level_run.dart`) is the pure-Dart rules layer: jars, corks, valves, win and out-of-sand, stars, replay recording. The app and the tools share it. Every level ships with `NNN.replay.json`; `test/level/levels_test.dart` replays them all, so a sim change that breaks a level fails `flutter test`.
- Cell types: 0 empty, 1 wall, 2 cork, 3 gate (closed valve), 4..11 filters, 12..19 sand. `Cell.isSand(t)` is `t >= 12`. Add new non-sand types below `firstSand`.
- Game loop: `Ticker` + `CustomPainter`. The grid is written to one RGBA buffer, then one `ui.Image`, then one nearest-neighbour quad. There's no game engine package, and state is plain `ChangeNotifier`/`ValueNotifier`.
- `lib/services/` holds thin wrappers (audio, haptics, ads, IAP, analytics) so tests can use fakes. Ads must never block progress.
- Portrait only. It's locked in `AndroidManifest.xml` and `ios/Runner/Info.plist` (with `UIRequiresFullScreen`).
- Ads use Google's test ad unit IDs until the owner supplies real ones. `google-services.json` and `key.properties` are git-ignored.
