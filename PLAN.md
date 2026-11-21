# POUR — Development Plan (Flutter, Android first)

Source of truth for *what* the game is: [pour-game-design.md](pour-game-design.md) (GDD).
This file is *how and in what order* we build it. Things only the owner can do (keys, accounts,
devices, decisions) live in [TODO.md](TODO.md).

Status legend: `[ ]` not started · `[~]` in progress · `[x]` done and verified on emulator.

---

## 0. Ground rules

1. **Every phase ends with a test gate.** A phase is not done until its gate passes on the
   Android emulator (`Medium_Phone_API_36.1`, x86_64, API 36) *and* `flutter analyze` + `flutter test`
   are clean. Real-device checks are listed separately because the emulator can't measure them.
2. **Feel before content.** Nothing past Phase 1 starts until the sand toy is fun with no goal (GDD pillar 1).
3. **The simulation is pure Dart with no Flutter imports** (`lib/sim/`). That makes it testable
   headless, replayable from a seed, and swappable for an FFI core if Dart is too slow.
4. **Deterministic everywhere.** Seeded RNG, fixed-timestep sim (60 Hz), tilt input recorded as a
   stream so any run can be replayed bit-for-bit. Replays become regression tests.
5. **Smallest thing that works.** Plain `ChangeNotifier`/`ValueNotifier` + `Navigator`; no state-
   management or game-engine package unless a concrete need shows up. A `Ticker` + `CustomPainter`
   is the game loop.
6. **iOS stays buildable but untested** until a Mac is available (TODO.md). No Android-only Dart
   APIs in shared code; platform-specific bits go behind a small interface.

### Engine note
The GDD suggests Godot/Unity. We are on **Flutter** by owner decision. The risk is sim + render
throughput in Dart (≈100k cells at 60 fps). Phase 1 measures this first, with fallbacks ready
(see §3 Risks).

---

## 1. Architecture

```
lib/
  main.dart              app entry, theme, routes
  sim/                   PURE DART. grid, cell types, CA step, RNG, elements (valve, filter, mixer, fan…)
  level/                 level model, PNG+JSON loader, win/lose/star evaluation
  game/                  game screen: loop (Ticker), renderer (grid → image), input (tilt/touch), HUD
  meta/                  save file, economy (coins, chests), album, daily jar, streak
  services/              audio, haptics, ads, IAP, analytics, notifications (each a thin wrapper)
  ui/                    design system (tokens, typography, components) + non-game screens
assets/
  levels/w1/NNN.png|json level art + metadata
  audio/  fonts/  images/
tool/                    dev CLIs: level validator, replay runner, sim benchmark, audio/icon scripts
test/                    unit + widget + golden tests
integration_test/        on-device flows (run on emulator)
```

Data flow per frame: `TiltInput → gravity angle → Sim.step() (fixed 60 Hz, n substeps) →
Uint32 RGBA buffer → ui.Image → CustomPainter (one quad, nearest-neighbour) + HUD widgets`.
Game events (`jarCorked`, `grainLost`, `flowRate`) leave the sim as a small per-step event list
that audio/haptics/HUD read. The sim never calls out.

### Planned packages (verify latest versions when added; add only in the phase that needs them)
| Need | Package | Phase |
|---|---|---|
| Tilt | `sensors_plus` (accelerometer + low-pass); platform channel to `TYPE_GRAVITY` only if jittery | 1 |
| Save file | `path_provider` (single JSON file, per GDD §14) | 5 |
| Audio | `flutter_soloud` (low latency, looping, pitch/volume per frame) | 7 |
| Haptics | `HapticFeedback` (built in) + `vibration` for amplitude control | 7 |
| Share | `share_plus` | 6 |
| Local notifications | `flutter_local_notifications` | 6 |
| Ads | `google_mobile_ads` | 8 |
| IAP | `in_app_purchase` | 8 |
| Analytics / crashes | `firebase_core`, `firebase_analytics`, `firebase_crashlytics` | 9 |
| Icons / splash | `flutter_launcher_icons`, `flutter_native_splash` (dev deps) | 2 |

---

## 2. Testing strategy (applies to every phase)

| Layer | What | How / where |
|---|---|---|
| Unit — sim | determinism (same seed+inputs ⇒ same grid hash), grain conservation (only the void removes sand), angle of repose within bounds, ±70° clamp, dead zone, sleeping cells give the same result as no sleeping on small boards, every element's rule | `test/sim/`, pure Dart, fast |
| Unit — rules | purity, fill line, cork, spill %, stars, out-of-sand detection, economy math, save migration | `test/level/`, `test/meta/` |
| Level tests | every level loads, validator passes (palette, jar defs, enough sand per color + margin), **recorded solution replay wins with ≥ expected stars** | `tool/level_check.dart`, also run from `flutter test` |
| Golden | grid→pixels renderer, key HUD/screens at fixed seed | `test/golden/` (regenerate with `--update-goldens`) |
| Widget | screens, navigation, settings persistence | `test/ui/` |
| Integration (emulator) | boot → play L1 with injected tilt → win → album tile; purchase/ad flows with test IDs | `integration_test/`, `flutter test integration_test -d emulator-5554` |
| Emulator smoke (every feature) | install profile APK, drive tilt with `adb emu sensor set acceleration x:y:z`, screenshot, read logcat for errors | see §5 commands |
| Performance | headless `tool/bench_sim.dart` (ms/step on worst-case level, run every phase); frame timings in profile mode on emulator (`adb shell dumpsys gfxinfo`) | emulator numbers are only a trend; **real low-end phone is the real gate** (TODO.md) |
| Human | toy test (5 people, no instructions), level difficulty playtests | owner (TODO.md) |

**Tilt on the emulator:** `adb emu sensor set acceleration x:y:z`. Upright `0:9.81:0`; right edge
down ~37° (sand flows right) `-6.3:7.5:0`; left edge down `6.3:7.5:0` (x is negative when the right edge is down). Integration tests can also bypass sensors through a test
`TiltSource` so tests don't depend on emulator state.

---

## 3. Phases

### Phase 0 — Foundations `[~]`
- [x] Flutter project (android + ios), app name "Pour", portrait lock (Android manifest + iOS Info.plist, `UIRequiresFullScreen`)
- [x] Placeholder title screen + smoke widget test; verified on emulator (profile build)
- [ ] `git init` + first commit (waiting on owner OK)
- [ ] Stricter lints in `analysis_options.yaml` (e.g. `prefer_const`, `avoid_print`, `unawaited_futures`)
- [ ] `tool/check.ps1`: analyze + test + build profile APK + install + launch + screenshot in one command
- [ ] Final `applicationId` / bundle id (owner decision, TODO.md — permanent after first Play upload)

**Gate:** `tool/check.ps1` passes end to end.

### Phase 1 — Toy prototype: sand + tilt in an empty box `[~]` (emulator gate passed; owner gate open)  ← the most important phase
Build the GDD §14 cellular automaton and nothing else.
- [x] `lib/sim/sand_sim.dart`: flat `Uint8List` cells + per-grain shade, 240×420; gravity step (two nearest of 8 dirs, weighted), fallbacks, repose cone (35°), **ledge rule** so cliffs steeper than repose relative to tilted gravity collapse, sweep from the downhill side, 16×16 sleeping chunks (radius-2 wake), stateless hash RNG ⇒ sleeping is bit-identical to processing everything
- [x] Fixed 60 Hz tick with accumulator, N substeps per tick (dev "sand speed" slider; default 3)
- [ ] Slow-mo (tap & hold) → moved to Phase 3: it's a limited per-level aid, and tap&hold collides with the dev spawn gesture
- [x] Renderer: RGBA `Uint32List` → `decodeImageFromPixels`, ring of 3 buffers / 2 decodes in flight; skips the upload when nothing moved; one nearest-neighbour quad
- [x] Tilt: accelerometer → low-pass → roll (works upright and lying flat) → recenter → dead zone → sensitivity → invert → clamp ±70°; auto-recenter on first sample; recenter button
- [x] Touch Tilt: drag in the lower third (always available, overrides the sensor while dragging)
- [x] Dev overlay (non-release builds): fps / vsync / sim ticks, ms per tick, awake chunks, grains, tilt source; drag elsewhere to spawn sand
- [x] Settings sheet (sensitivity, dead zone, invert, dev sand speed), in memory for now
- [x] `tool/bench_sim.dart`: headless worst case (nothing sleeps), exits 1 over budget

**Results (2026-11-20):**
- Bench, PC AOT: 1.08 ms/step avg (p95 1.33), pixel fill 0.12 ms ⇒ ~3.4 ms per 60 Hz tick at 3 substeps.
- Emulator (profile): sim keeps 60 ticks/s at ~1.6–2.7 ms/tick while active, ~0.05 ms settled. Display is **30 fps, but that's the emulator**: Flutter gets only 30 vsync callbacks/s even with zero work per frame (sand settled, no uploads). A real phone must confirm 60.
- Scripted sensor tilt (±37°), touch tilt (45°), recenter, settings verified by screenshots; no errors in logcat.

**Tests:** determinism hash, conservation, repose angle, clamp/dead-zone math, recenter math, benchmark budget (≤ 6 ms/step on the dev PC as the early alarm).
**Gate:** on emulator, scripted tilt sequence (left → right → upright) visibly moves sand; profile build holds ~60 fps; no logcat errors.
**Owner gate:** real low-end phone ≥ 55 fps sustained; 5-person toy test ("do they keep playing 2+ min?"). Fix feel before Phase 3.

**Performance fallbacks (in order, only if the gate fails):**
1. Dirty-rect texture updates / lower grid res (e.g. 180×320) with bigger pixels (still looks fine)
2. Move the sim into a background isolate, double-buffer the RGBA buffer via `TransferableTypedData`
3. Rewrite only `sim_step` in C via `dart:ffi` (the pure-Dart boundary in `lib/sim/` makes this a contained swap)
4. Fragment shader to colorize a 1-byte-per-cell texture (cuts CPU color work)

### Phase 2 — Brand & design system `[x]` (name decision still open — owner)
- [ ] Name decision (GDD §18 Q4; owner, after a Play Store search check)
- [x] **Palette** (`SandColor` in `lib/game/palette.dart`): 8 sand colors; every pair ≥ 12.9 ΔE2000 under normal, protan, deutan and tritan simulation (was 1.3 for blue/purple under deutan). Each color has a **glyph** (circle, triangle, square, diamond, star, plus, ring, cross); dark sand gets a glass rim
- [x] UI tokens (`lib/ui/tokens.dart`): Desert Glass colors, spacing, radii, motion; theme in `lib/ui/theme.dart` (always dark, own theme)
- [x] Typography: Fredoka (display) + Nunito (body), OFL, bundled, licences registered in-app, `assets/CREDITS.md`
- [x] Components (`lib/ui/components.dart`): `PourButton` (squish + lip), `RoundIconButton`, `CounterChip`, `StarRow`, `SandMeter`, `LevelNode`, `PourCard`; sliders/switches/sheets are themed Material
- [x] **Logo** drawn in code (`LogoMarkPainter`): a corked jar of layered pixel sand tipped 10°, sand level with the world; `Wordmark` = P[jar]UR. Painted in code rather than SVG so the app, icon, splash and store art share one source; `tool/brand_export_test.dart` exports PNGs to `branding/`
- [x] **App icon:** adaptive (fg/bg) + monochrome themed icon + iOS 1024 (no alpha) + 512 Play Store icon → `flutter_launcher_icons`
- [x] Splash: `flutter_native_splash` incl. Android 12+ API
- [x] Gallery screen (dev button in the top bar) = golden source `test/ui/goldens/gallery.png`

**Results (2026-11-20):** palette/contrast tests, gallery golden, and a platform-config test (portrait lock, which the splash generator had silently removed) pass; 20 tests total. On the emulator: launcher icon, Android 12 splash, wordmark top bar, and gallery verified by screenshot.

**Tests:** golden tests of the component gallery; contrast check (text ≥ 4.5:1) as a unit test over the token pairs.
**Gate:** icon, splash and gallery verified on emulator (light/dark system theme both fine; game is always its own theme).

### Phase 3 — Core puzzle: jars, corks, level format `[x]`
- [x] Level format: **JSON shape lists** (`lib/level/level.dart`: rect/line/circle walls, sand, jars, valves, filters, star overrides) instead of PNG: easier to generate, diff and validate. PNG import can come later if a human designer wants to paint levels
- [x] Validation (`Level.problems()`): bounds, jar size, label room, fill ≤ 0.85, filter ≤ 2 thick, sand budget per color
- [x] Rules engine (`lib/level/level_run.dart`, pure Dart): jar fill + purity → **cork** (top row sealed); void = spill; win; **out of sand** (a color short, *or* too few grains left overall to reach fill lines; the second check came from a test that hung); stars; result frozen at the win
- [x] Sim additions: cork, valve gate, color filter cells (matching grains hop through ≤ 2 filter cells), per-type counts, wake radius 3
- [x] **Physics fix:** sand never moved up the screen, so it could never pour over a lip or out of a jar. Now ledge moves may go up-screen when they're still downhill relative to gravity (only past 45° tilt), and real falls always win over ledge moves (fixed a "fountain" artefact)
- [x] Slow-mo: hold anywhere = 1 substep instead of 3 (unlimited for now; the limit comes with boosters, Phase 8). Recorded in replays
- [x] Replays: `[tick, kind, value]` events (gravity half-degrees, valve toggles, slow-mo); deterministic re-play; in-app "Save replay (dev)" writes to app external files (`adb pull /sdcard/Android/data/com.pourgame.pour_sand_game/files/replays/`)
- [x] Tools: `tool/level_check.dart` (validate + play every solution), `tool/solve_level.dart` (brute-forces 1- and 2-move tilt scripts; **the number of winning scripts measures how forgiving a level is**), `tool/level_preview_test.dart` (contact sheet of a replay → `build/level_previews/`)
- [x] Game screen: fill lines, jar glyph + progress ring (red = purity too low), corked check, valve buttons, hint, spill meter with 3★ line, pause / win / out-of-sand cards, next/replay/retry
- [x] Home screen: wordmark + level list + Play (next unbeaten). Stars are in memory until Phase 5
- [x] Levels 001 First Pour (tilt), 002 Two Colors, 003 Valve, 004 Filter, each with a 3★ solution

**Results (2026-11-20):** 41 tests (incl. every level's solution replay via `test/level/levels_test.dart`). On the emulator: L1 3★ by tilt, L2 3★ (right then left), L3 3★ by tapping the valve, L4 filter sorting visible, out-of-sand card + retry, pause card, home progress. Bench 1.18 ms/step.

**Level-design rules learned (apply in Phase 4):**
1. A stream must land on a jar's **uphill** side. Past ~38° of tilt, sand stacks up the jar's downhill wall and spills over the brim before the fill line, so land it far from that wall.
2. A fill line must be reachable **at the tilt used to pour**. Size jars to the sand that actually arrives (`solve_level` shows what it reaches).
3. Sand on a flat shelf holds below ~35° and slides above it; containers with lips only pour past 45°. Use shelves for gentle early levels and lips for "tilt hard" levels.
4. Filters sort a **thin stream landing on a resting filter**. An avalanche sliding over a filter doesn't sort (only its bottom layer touches it).
5. Surplus sand piles on top of a corked jar and spills when you tilt later; budget it, or relax that level's `stars.spill`.
6. Target forgiveness for tutorial levels: ≥ 30 winning one-move scripts (L1 has 32).

### Phase 4 — Content: World 1 (60 levels) `[x]` (owner playtest open)
- [x] Elements: **mixer** (stirs per row, converts touching primary pairs; out-of-sand counts ingredients), **fan** (tap-toggled sideways push, `sim.shiftGrains`), **splitter** (wall wedge), **sloped filters** (1-thick 4-connected lines)
- [x] **Painting frames**: rows of slot jars sharing walls (`frames` in level JSON); bosses use a splitter wedge over each slot pair
- [x] **Level source in code**: `tool/build_levels.dart` (helpers: shelf, hopper, funnel, wedge, tier/drop modules, remix = recolor/mirror/tighten) writes the JSON + replays. **Never hand-edit level JSON**
- [x] 60 levels: 1–20 per GDD §8; 21–60 = module combinations + remixes of 1–20; breathers at x9, bosses at x0 (paint-then-pour)
- [x] Every level ships with a solution replay; 53/60 earn 3★, the rest 2★; `test/level/levels_test.dart` replays all of them
- [x] `tool/level_report.dart` → `docs/levels-w1.md`: forgiveness (16 sloppy replays: timing ±20 ticks, angles ±4°) and a shake bot (random tilts/taps)
- [x] World map (winding path, boss markers, star total, sequential unlock; all open in dev builds)
- [x] Dev autoplay ("Watch solution" in pause, "Autoplay all" on home) logs `AUTOPLAY ...` results to logcat

**Results (2026-11-20):** 106 tests. **Emulator gate: all 60 levels autoplayed on device; status + stars identical to headless for every level.** Forgiveness: bosses 88–100%, mixers 50–75%, most others 63–100%.

Bugs found and fixed along the way: closing a valve mid-flow left holes (the hopper kept leaking); the map didn't refresh stars for levels reached with Next; painting-boss precision was impossible (0–6% forgiveness → redesigned).

**Known gaps (for the owner playtest / polish pass):**
- 21–60 reuse 1–20's mechanics and modules; the difficulty curve is flatter than GDD's sawtooth (later levels are about as forgiving as earlier ones). Tighten using playtest data.
- Mixer levels want both valves tapped within ~0.3 s.
- A few levels are winnable by shaking (tutorials, breathers, three tier levels); see the report.
- Painting frames are 8 slots (4 color pairs), not GDD's 12.

### Phase 5 — Meta: progression, save, economy `[x]`
- [x] Save (`lib/meta/save_store.dart`): one versioned JSON file (stars, coins, streak, chests, seen album tiles, settings), written temp → backup → rename; a torn or corrupt save falls back to the backup, and both bad = fresh start; v0 → v1 migration
- [x] Economy (`lib/meta/economy.dart`): first clear 10 + 5 per new star, bosses double, replays pay only for improvements; win-streak bonus 10/20/50 at 3/5/10 (a fail or mid-level restart ends the streak); star chest (50 coins) every 20 stars
- [x] `Progress` (`lib/meta/progress.dart`): every change saves + notifies; replaced the in-memory session stars
- [x] **Sand Album: 6 pictures × 10 tiles** (not 4 × 12: World 1 has 60 levels and a boss every 10, so each boss completes a picture). The pictures are pixel art drawn in code from the sand palette (`lib/meta/album.dart`), so no image pipeline is needed; new tiles pour in bottom-up (whole reveal ≤ ~3 s)
- [x] Settings screen: sensitivity, dead zone, invert, **touch tilt only**, sound/music (stored; audio is Phase 7), vibration (live), licences
- [ ] Notifications and privacy/consent settings → Phases 6 and 8

**Results (2026-11-20):** 120 tests. Emulator gate: on a fresh save, autoplayed levels 1–11, then **force-stopped mid-level 12** and relaunched: 31 stars and 370 coins, exactly matching the economy rules; chest ready, then opened (+50); album showed picture 1 complete and picture 2 at 1/10 with the pour animation; a settings change survived a second kill.

### Phase 6 — Daily Jar, streak, sharing, notifications `[x]`
- [x] Daily Jar with **no server**: a 30-jar pool (`assets/levels/daily/`, built and verified by `tool/build_levels.dart` as remixes of World 1 mechanics). The jar is chosen by the player's **local calendar date** (Wordle-style; DST-safe because it counts calendar days); #1 = 2026-11-20; the pool cycles
- [x] Score 0–1000 = purity × speed (full speed within 1.5× the solution's time); the first daily win of the day pays 20 coins; the day's best result is kept; replays don't touch map stars or the album
- [x] Daily streak with one automatic freeze per week (covers a single missed day); days at or before the last completed one count as done, so moving the clock back can't farm coins
- [x] Share card via `share_plus`: "Daily Jar #N", stars, purity, time, one emoji row per jar, streak, store link
- [x] Opt-in reminder ("Daily reminder" in settings, or offered on the daily win card): one inexact notification a day (no exact-alarm permission), today 7 pm if not played, else tomorrow 7 pm; rescheduled on launch and after a daily win; Android 13+ permission requested only when turned on
- [x] Save v2 (+ migration test); `.gitattributes` keeps text files LF (stops CRLF churn on Windows)
- [x] Dev: "+1 day" (day offset) and "Test reminder" on home; "Watch solution" works for dailies too

**Results (2026-11-20):** 163 tests (dates/DST, pool, score, streak/freeze, reminder time, share text, clock rollback, migration, all 30 daily solutions). Emulator gate, using the dev day offset because this Play Store emulator image can't change its date without root:
- Daily #1 won: 1000 pts, 🔥1, +20; the share sheet showed the card text.
- Stepped to #2 and won: 🔥2.
- Skipped #3: the streak stayed alive (freeze available).
- Won #4: "A streak freeze covered yesterday", 🔥3.
- The test reminder posted about 10 s after the permission prompt.
- The settings toggle scheduled exactly one alarm (tomorrow 19:00).

**Known limits:** `flutter_local_notifications` pinned to 22.x (23.x needs compileSdk 37; see TODO.md toolchain item). The "streak ends in 2h" variant was dropped to keep one notification a day.

### Phase 7 — Juice: audio, haptics, camera `[x]`
- [x] Sounds synthesized in code (`tool/audio/synth.dart` → `assets/audio/*.wav`, 1.4 MB): granular sand hiss loop (volume follows grains moving, pitch rises as the jar fills), cork thunk+pop, valve, fan whoosh, UI tap, three star chimes, win jingle, out-of-sand, album reveal, 24 s ambient music loop. WAV because iOS can't play OGG and AAC loops have gaps
- [x] `lib/services/audio.dart`: game-level API (`sfx`, `flow`, `syncMusic`) over a swappable backend (`audioplayers`; fake in tests). Loops pause when the app is hidden
- [x] Haptics: light ticks whose rate follows the flow (up to ~15/s), heavy click on each cork
- [x] Board leans ~10% against the phone's tilt (with it for touch tilt; off with the system's reduce-motion), glass glare slides with tilt, per-grain shade jitter (since Phase 1), grains under sand drawn darker than the top layer
- [x] Win sequence: corks pop down the line with a hop and a ring each, then the card: jingle, stars light one by one with chimes, and on a first win the album tile flies into the album icon
- [x] Mixes with other apps' audio (no audio focus); Android plays on the media stream (volume buttons), iOS uses the ambient category (silent switch mutes it); sound / music / vibration toggles apply at once

**Tests:** audio service unit test with a fake backend (events → calls); frame budget re-checked (`bench_sim` + profile mode) — juice must not drop fps.
**Gate:** emulator recording (`adb shell screenrecord`) of a full level reviewed; owner listens on a real phone speaker.

**Results (2026-11-20):** 170 tests (audio service vs a fake backend: music toggle, sound-off, flow → volume/pitch with release to silence and no chatter while quiet, level-to-level handover, background pause; sand shading). Bench: render 0.09 → 0.16 ms/frame, tick 3.8 ms of 16.7. Emulator: 30 s recording of autoplayed levels 1–7 reviewed frame by frame (lean, cork rings, stars lighting, tile fly, all levels won as in the report); `dumpsys audio` shows the players as `USAGE_GAME` with no focus request (fixed: the music player first came up as plain media because audioplayers copies its global context at creation). The final glare tweak (fainter, narrower) wasn't re-checked on the emulator: its storage filled up (TODO.md).

**Known limits:** waveforms checked by spectrogram only — nobody has listened yet (owner, real phone). The jar "hop" moves the jar's glyph, not the jar pixels. No filter sound and no vibration amplitude control (would need the `vibration` package + VIBRATE permission). Music is a generated placeholder (TODO.md).

### Phase 8 — Monetization `[~]` (code done; device gate on the owner's phone)
- [x] AdMob (`google_mobile_ads`, Google **test** IDs): rewarded for +Sand, Undo, double level coins, chest boost; interstitial only when leaving a won level, level ≥ 15, ≥ 3 min apart and ≥ 3 min after launch, never after a fail, never with Remove Ads (`interstitialDue` in economy.dart)
- [x] **Google UMP consent** before any ad request; "Ad privacy choices" in Settings where required. `--dart-define=UMP_EEA=true` forces the EEA form (test devices only)
- [x] IAP (`in_app_purchase`): `remove_ads`, `starter_pack` (remove ads + 500 coins; offered once 10 levels are done), restore; grant once per save (save v3 `owned`), always acknowledged. Shop sheet from home
- [x] Boosters: Undo (rewind ~3 s via sim snapshots every 60 ticks; replay stays exact) and +Sand (drops the missing color where it started; replay event kind 4) for 30 / 40 coins or an ad. Slow-mo stays free (hold): it's an accessibility aid and limiting it would be pay-to-win
- [x] Never blocks: no ad (offline, no consent, load failure) = the option is greyed ("No ad right now") or hidden; the level waits while a booster offer is open

**Tests:** ad pacing rules unit-tested with a fake clock; purchase state machine tests; emulator run with **Google test ad unit IDs only**; IAP via Play Console license testers (owner, TODO.md).
**Gate:** emulator: rewarded test ad grants reward exactly once; interstitial pacing correct; app usable in airplane mode.

**Results (2026-11-21):** 182 tests: pacing with a fake clock, reward once / double-tap / closed early, no-ad path, purchase state machine (grant once, always complete, pending/error/cancel grant nothing), coins, save v2→v3, undo exactness against a replay, +Sand replay reproduction, AdMob ids and keep rule present. Emulator: the release build installed once and **crashed at launch** (R8 renamed WorkManager's Room database, pulled in by the ads SDK) → fixed with `proguard-rules.pro`. The fixed build couldn't be installed (emulator storage, TODO.md), so the device gate moves to the owner's phone:

Phone checklist (`dist/pour-phase8-arm64.apk`, installs over Phase 7):
1. App opens (the crash fix); home shows a shop (storefront) button. Shop says the store isn't available (expected until Play Console products exist).
2. In a level, tilt the wrong way until **Out of sand** → **Add sand** → **Watch an ad**: a Google "Test Ad" plays; close it after the reward → sand appears and play continues. Repeat with the coins option (40).
3. Mid-level, tap ↶ (rewind) → coins or ad → the board jumps back ~3 s.
4. Win a level that pays coins → **Watch an ad: +N more** → coin total doubles once.
5. After 3+ minutes in the app, win level 15 or later and tap **Next**: one full-screen test ad. Win again right away: no ad. Never after Out of sand.
6. Airplane mode: everything still works; ad options show "No ad right now" or disappear.
7. Star chest dialog: **Ad: +50 more**.

**Known limits:** consent form not seen on a device yet (needs an EEA test device or the owner's AdMob consent message, TODO.md). IAP untestable until Play Console products + a testing track exist. No server-side receipt check.

### Phase 9 — Analytics & crash reporting `[ ]`
- [ ] Firebase Analytics events from GDD §14 (+ `level_quit` with time-in-level)
- [ ] Crashlytics (+ non-fatal logging for save/ads errors)
- [ ] Respect consent (analytics collection off until consent where required)

**Tests:** analytics wrapper unit tests with fake sink (event names/params locked by test); DebugView check on emulator (`adb shell setprop debug.firebase.analytics.app <id>`).
**Gate:** events visible in Firebase DebugView from the emulator; forced test crash appears in Crashlytics.

### Phase 10 — Performance, QA, accessibility, polish `[ ]`
- [ ] Profile on real low-end device (owner): 60 fps target, no jank in menus, cold start < 3 s, APK/AAB size check
- [ ] Memory: no leak over 30-level session (DevTools memory)
- [ ] Battery/thermal: 15-minute session on real phone
- [ ] Accessibility: color glyphs on jars, touch-tilt mode completes all levels (replays recorded in touch mode for a sample), text scaling up to 1.3×, TalkBack labels on menus, reduced-motion option (disables camera rotation)
- [ ] Edge cases: app backgrounded mid-pour (pause sim), rotation lock, small screens (≤ 360 dp wide), tall screens (20:9+), display cutouts, Android back button/gesture on every screen
- [ ] Localization-ready strings (`flutter gen-l10n`), English only at launch
- [ ] Full regression: all tests + all level replays + integration suite

**Gate:** checklist above all green; zero crashes in a 1-hour emulator monkey run (`adb shell monkey -p com.pourgame.pour_sand_game -v 20000` with throttle).

### Phase 11 — Release to Google Play `[ ]`
- [ ] Release signing (upload keystore — owner creates & stores, TODO.md); `key.properties` git-ignored
- [ ] Build `flutter build appbundle --release --obfuscate --split-debug-info=build/symbols`
- [ ] R8/proguard check, upload native debug symbols
- [ ] Store listing: title, short/long description, feature graphic 1024×500, phone screenshots (captured from emulator, framed by a script), promo video (tilt-to-pour clip)
- [ ] Privacy policy (hosted URL — owner), Data safety form, content rating questionnaire, target audience & ads declaration, IARC
- [ ] Internal testing track → closed testing (new personal accounts need **12+ testers opted-in for 14 days** before production) → soft launch in 1–2 test countries
- [ ] KPI dashboard from Firebase (GDD §15)

**Gate:** internal-testing build installed from the Play Store on a real phone; clean pre-launch report.

### Phase 12 — iOS (after Android soft launch) `[ ]`
- [ ] Mac + Xcode + Apple Developer account (owner)
- [ ] Signing, Info.plist privacy strings (ATT for ads, motion if needed), `CMMotionManager` via `sensors_plus`
- [ ] AdMob iOS app id, StoreKit products, TestFlight

### Post-launch (from GDD "Out" list, ordered by expected value)
Weekly "Sand Rush" events → auto-clip share → World 2 → cosmetics store + gems → Sand Art mode → cloud save → leaderboards.

---

## 4. Asset plan

| Asset | Approach | Who |
|---|---|---|
| Logo + wordmark | Hand-authored SVG in repo, PNG export script | Claude |
| App icon (adaptive + monochrome + iOS) | From logo SVG → `flutter_launcher_icons` | Claude |
| Splash | `flutter_native_splash` from logo | Claude |
| Fonts | 2 OFL Google Fonts, bundled, `OFL.txt` included | Claude |
| Sand visuals | Code-generated (palette + per-grain jitter); sand skins are palette+noise presets | Claude |
| UI icons | Material Symbols (bundled, tree-shaken) + a few custom SVGs (jar, cork, valve) | Claude |
| Sound effects | Procedural synthesis script (`tool/audio/`, filtered noise, pops, chimes) → OGG; optional upgrade via ElevenLabs SFX | Claude; ElevenLabs needs owner auth |
| Music | 1 calm ambient loop — licensed track or generated; needs owner choice/licence | Owner decides |
| Album pictures (4 for W1) | Concept images (AI image generation — spends owner credits, ask first — or hand pixel art) → palette-quantize script | Claude + owner OK |
| Store feature graphic & screenshots | Emulator captures + framing script; feature graphic composed from game art | Claude |
| Levels | PNG + JSON, drawn programmatically by a generator script where geometric, hand-tuned after playtest | Claude, owner playtests |

All third-party assets get an entry in `assets/CREDITS.md` with licence.

---

## 5. Everyday commands (Windows PowerShell; chain with `;`)

```powershell
flutter analyze; flutter test
flutter test test/sim/sand_sim_test.dart                    # one file
flutter test --plain-name "determinism"                     # one test by name
flutter build apk --profile --target-platform android-x64   # emulator build (debug APK is too big for this AVD's storage)
adb install -r build\app\outputs\flutter-apk\app-profile.apk; adb shell am start -n com.pourgame.pour_sand_game/.MainActivity
adb emu sensor set acceleration 4.9:8.5:0                   # tilt ~30° right
adb logcat -d | Select-String "flutter|FATAL"
```
Screenshot (Git Bash; PowerShell `>` corrupts binary): `MSYS_NO_PATHCONV=1 adb shell screencap -p /sdcard/s.png; adb pull /sdcard/s.png`

---

## 6. Risks specific to this plan

| Risk | Plan |
|---|---|
| Dart sim/render too slow on low-end phones | Measured in Phase 1 before any content; 4 ordered fallbacks; pure-Dart `sim/` boundary keeps the FFI swap contained |
| Emulator perf ≠ real perf | Emulator only for function + trends; real low-end phone gate (owner) in Phases 1, 7, 10 |
| Emulator has ~470 MB free; debug APK (139 MB) won't install | Use profile builds; owner can wipe/enlarge the AVD (TODO.md) to get hot-reload debug runs |
| Emulator fps varies (30 vsync after a long session, 60 vsync / ~54 fps on a fresh boot) | Treat emulator fps as a rough signal; use the overlay's `ticks` (must stay 60), `tool/bench_sim.dart`, and a real phone |
| Levels solvable by random shaking | Noisy-tilt bot test in Phase 4 |
| Tilt feel differs by device | Calibration knobs (sensitivity, dead zone, invert) + touch-tilt; owner tests on 2+ phones |
| Play closed-testing requirement delays launch | Start recruiting 12+ testers during Phase 8 (TODO.md) |
