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

### Phase 2 — Brand & design system `[ ]` (can overlap Phase 1)
- [ ] Name decision (GDD §18 Q4; owner, after a Play Store search check)
- [ ] **Palette:** sand colors (6 primaries + mixed: blue, yellow, red, green, purple, orange, white, black) tuned for colorblind distinction (deuteranopia/protanopia check) + each sand color gets a **pattern/glyph** fallback on jars (accessibility)
- [ ] UI tokens: warm "desert glass" theme (dark sand-brown background, cream text, amber accent), spacing scale (4/8/12/16/24/32), radius, elevation, motion durations/curves → `lib/ui/tokens.dart`
- [ ] Typography: one rounded display font + one body font, both OFL (Google Fonts), **bundled** in `assets/fonts` (no runtime fetching)
- [ ] Components: primary/secondary button (with press "squish"), icon button, coin/star counters, card, modal sheet, toggle/slider (settings), level node, star row, progress bar ("sand meter")
- [ ] **Logo:** vector SVG drawn in-repo (a jar with a sand stream forming the "O"), wordmark in the display font; export PNGs with a script in `tool/`
- [ ] **App icon:** adaptive Android icon (foreground + background layers, monochrome themed icon for Android 13+), iOS 1024 icon → `flutter_launcher_icons`
- [ ] Splash: `flutter_native_splash` (solid color + logo; Android 12+ splash API)
- [ ] `ui/gallery` debug screen showing every component (doubles as golden-test source)

**Tests:** golden tests of the component gallery; contrast check (text ≥ 4.5:1) as a unit test over the token pairs.
**Gate:** icon, splash and gallery verified on emulator (light/dark system theme both fine; game is always its own theme).

### Phase 3 — Core puzzle: jars, corks, level format `[ ]`
- [ ] Level format: PNG at grid res (palette-mapped colors → cell types) + JSON (jars: rect, target color, fill line, purity threshold; valves; filters; seed; sand budget; star thresholds)
- [ ] Loader + `tool/level_check.dart` validator
- [ ] Jar: counts grains by color inside its rect; fill line; purity; **cork** once fill + purity reached → jar becomes solid wall (sand can't leave)
- [ ] Uncorked jars spill when tilted (falls out of the sim naturally — verify it does)
- [ ] Void edges: grains leaving the field are counted as spill
- [ ] Win (all corked), soft lose ("Out of sand": remaining loose sand per color < needed), Retry
- [ ] Stars (GDD §6), live spill meter
- [ ] Elements: funnel (just walls), **valve hopper** (tap to toggle), **color filter** (pass-through only for its color)
- [ ] In-game **replay recorder** (debug builds): records tilt + taps per tick; save as `NNN.replay.json`
- [ ] Game HUD: pause, recenter, retry, spill meter, jar indicators

**Tests:** jar/cork/purity/star unit tests; filter & valve rule tests; loader round-trip; replay determinism (record → replay → same final hash).
**Gate:** a hand-made test level is playable start→win→stars on emulator with scripted tilt; replay of it passes headless.

### Phase 4 — Content: World 1 (60 levels) `[ ]`
- [ ] Remaining MVP elements: **mixer** (2 primaries → secondary), **splitter**, **fan** (GDD's first-20 list uses splitter at L15 and fan at L18, though MVP §16 omits them — see TODO decision; both are cheap)
- [ ] **Painting frame** (grid of slots, each needs a color) for 6 boss levels
- [ ] Levels 1–20 exactly per GDD §8, then 21–60 following the sawtooth curve (pleasure levels at x9, boss at x0)
- [ ] Every level ships with a recorded 3-star replay; `level_check` runs all of them
- [ ] Level select map (world 1 path, locked/unlocked, stars)
- [ ] Difficulty notes per level (`assets/levels/w1/notes.md`): intended solution, new concept, target fail rate

**Tests:** all 60 levels pass validator + replay (≥ 1 star; boss levels ≥ 1; non-boss 3-star replay exists); headless run of every level under 3 random "noisy tilt" bots to catch levels that are trivially solvable by shaking.
**Gate:** play-through of L1–L20 on emulator (scripted where possible, manual-by-screenshot otherwise).
**Owner gate:** human playtest of L1–L20 on a real phone; tune from notes.

### Phase 5 — Meta: progression, save, economy `[ ]`
- [ ] Save: single versioned JSON file (progress, stars, coins, album, streak, settings), atomic write (write temp → rename), migration by version number
- [ ] Coins (level rewards, chest), star chest every 20 stars
- [ ] **Sand Album:** 4 pictures × 12 tiles for World 1; tile fills with a pour animation per level; boss completes a picture → "sand art" reveal
- [ ] Album art pipeline: concept image → `tool/album_art.py` quantizes to the sand palette and downsamples to the tile grid (so pictures are literally made of our sand colors)
- [ ] Win-streak bonus (3/5/10)
- [ ] Settings screen (sensitivity, dead zone, invert, touch-tilt, sound, music, haptics, notifications, privacy/consent, credits)

**Tests:** save round-trip, corrupted-file recovery (falls back to backup, never loses progress), migration, economy unit tests, album tile mapping.
**Gate:** kill app mid-level / after win on emulator (`adb shell am force-stop`) → relaunch → progress intact.

### Phase 6 — Daily Jar, streak, sharing, notifications `[ ]`
- [ ] Daily Jar: same level worldwide **without a server** — pick from a hand-made daily pool (or a parametric generator) by `days since epoch (UTC)` + seed
- [ ] Score = purity × speed; streak + one free weekly freeze
- [ ] Share card: emoji grid + purity % + store link, via `share_plus`
- [ ] Local notification: max 1/day, opt-in ("Your daily jar is ready" / "Streak ends in 2h")
- [ ] Android 13+ `POST_NOTIFICATIONS` runtime permission, asked in context (not at first launch)

**Tests:** date→level mapping across timezones/DST and day boundaries; streak/freeze logic; share text snapshot test.
**Gate:** on emulator, change device date (`adb shell` / settings) → new daily, streak behaves; share sheet opens; notification fires.

### Phase 7 — Juice: audio, haptics, camera `[ ]`
- [ ] Sound list (see §4 Assets): granular sand hiss (volume/pitch follow active grain count & jar fill), cork thunk+pop, valve, filter, UI taps, star chime, album reveal, ambient music loop
- [ ] Haptics: continuous light buzz scaled to flow (amplitude control where supported), sharp click on cork
- [ ] Camera counter-rotation ≈10% of tilt; glass glare moving with tilt; per-grain color jitter; settled-sand shadow
- [ ] Completion sequence: corks pop in sequence, jar hop, tile flies to album
- [ ] Respect system silent mode / volume and in-app toggles

**Tests:** audio service unit test with a fake backend (events → calls); frame budget re-checked (`bench_sim` + profile mode) — juice must not drop fps.
**Gate:** emulator recording (`adb shell screenrecord`) of a full level reviewed; owner listens on a real phone speaker.

### Phase 8 — Monetization `[ ]`
- [ ] AdMob: rewarded (+Sand on fail, Undo, double coins, chest boost); interstitial (after win, level ≥ 15, ≥ 3 min apart, never after fail)
- [ ] **Google UMP consent** (GDPR/EEA required) before any ad request
- [ ] IAP: Remove Ads (non-consumable), Starter pack (once, after L10); restore purchases
- [ ] Boosters: Undo Pour (rewind 3 s — uses the replay/snapshot ring buffer), +Sand, Slow-mo
- [ ] Everything works offline / with ads failing to load (no blocked progress, ever)

**Tests:** ad pacing rules unit-tested with a fake clock; purchase state machine tests; emulator run with **Google test ad unit IDs only**; IAP via Play Console license testers (owner, TODO.md).
**Gate:** emulator: rewarded test ad grants reward exactly once; interstitial pacing correct; app usable in airplane mode.

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
| Emulator renders at 30 fps regardless of load | Treat emulator fps as functional only; use the overlay's `ticks` (must stay 60) and `tool/bench_sim.dart` as the perf signal until a real phone is connected |
| Levels solvable by random shaking | Noisy-tilt bot test in Phase 4 |
| Tilt feel differs by device | Calibration knobs (sensitivity, dead zone, invert) + touch-tilt; owner tests on 2+ phones |
| Play closed-testing requirement delays launch | Start recruiting 12+ testers during Phase 8 (TODO.md) |
