# POUR — Game Design Document

> Working title. Android-first, portrait, free-to-play, hybrid-casual puzzle.
> Version 0.1 · 2026-11-20

---

## 1. One-liner

**Tilt your phone to pour colored sand through a little glass machine and fill every jar with the right color.**

It's understood in 2 seconds, satisfying to watch, and each level is a 30–90 second puzzle about *flow*. Puzzle players get to plan, casual players get to tilt and watch.

## 2. Why this game, why now

- "Flow" and sort puzzles are the fastest-rising puzzle segment of 2026. Sort revenue more than tripled YoY, and flowing-material games (sand, marbles, pixels) dominate the hybrid-casual charts.
- Nearly all of them are **tap-to-select** games. **Tilt as the main control** is our point of difference: it's physical, it's new, and it looks great on camera (hands tilting a phone + sand flowing = a ready-made TikTok clip).
- It builds on our Cosmo Drop physics experience and Chroma's color work.

## 3. Design pillars

1. **Feels good in the hands.** Every tilt has a visible, audible and haptic response within 1 frame. If it isn't satisfying with no goal at all, nothing else matters.
2. **Readable at a glance.** Every level makes sense from one screenshot. No text needed to play.
3. **Calm by default, tense by choice.** No timers in the main path. Tension comes from spill risk and purity, not from the clock.
4. **Every pour is shareable.** The game makes clipping and sharing a good moment effortless.

---

## 4. Core loop

### Moment to moment (seconds)
Tilt → sand slides, piles up and streams through channels → it lands in jars → a jar reaches its fill line at the required purity → **the cork pops in** (locked, safe) → next jar.

### Level (30–90 s)
Read the machine → open valves / tilt to guide sand → fill and cork all jars → stars → reward.

### Session (8–12 min)
Play 5–10 levels → fill a mosaic tile per level → finish the daily jar → open a star chest → done for now (streak saved).

### Long term (weeks)
Complete themed **Sand Albums** (mosaic pictures) → unlock new worlds and sand types → weekly events → keep the streak.

---

## 5. Controls

| Input | Action |
|---|---|
| **Tilt phone** | Sets the gravity direction for all loose sand |
| **Tap a valve** | Opens / closes a hopper or gate |
| **Tap & hold anywhere** | Slow-mo (sand runs at 30% speed) — precision help, limited per level once it's earned |
| **Recenter button** | Sets the current hold position as "neutral" |

### Tilt rules
- Read Android's `TYPE_GRAVITY` sensor (fallback: accelerometer + low-pass filter).
- Map phone roll to the gravity angle, **clamped to ±70°** from straight down. Sand never falls "up", so you can't break a level by flipping the phone.
- **Dead zone** of ~3° around neutral so a resting hand doesn't trickle sand.
- **Auto-recenter** at the start of each level (whatever pose the player holds = straight down). This fixes the "playing in bed / on the bus" problem.
- Settings: sensitivity slider, dead-zone slider, invert. Real sensors drift and differ between devices, so expose the knobs.

### Accessibility / no-gyro mode
**Touch Tilt:** drag left/right anywhere on the lower third of the screen to tilt. On by default if the device reports no gravity sensor. Every level must be solvable in both modes.

---

## 6. Level anatomy

```
 ┌──────────────────────────┐
 │   [HOPPER: blue] [HOPPER: yellow]   ← sand sources, valves on top
 │      \\        //                  │
 │       \\ FUNNEL//                  │
 │  ═══════  ═══════  ═══════        │ ← walls / channels
 │        [FILTER: blue]              │ ← gate that only lets one color through
 │   ┌───┐          ┌───┐             │
 │   │ B │          │ Y │             │ ← jars: target color + fill line
 │   └───┘          └───┘             │
 └──────────────────────────┘
       (screen edges = void: sand that leaves is lost)
```

### Win condition
Every jar is **corked**. A jar corks automatically once sand reaches its fill line **and** purity is ≥ 90% (early levels: 80%).

### The core tension
**Uncorked jars spill when you tilt.** A half-filled jar is at risk every time you change the angle for the next one. That's the whole puzzle: *in what order, and from which angle, do I fill these?*

### Lose condition (soft)
There isn't enough loose sand left to fill the remaining jars. The game detects this, shows "Out of sand", and offers:
- **Retry** (free, instant)
- **+Sand** (rewarded ad: drops a small hopper of the needed color)

### Stars
| ★ | Condition |
|---|---|
| ★ | Complete |
| ★★ | Average purity ≥ 95% |
| ★★★ | Purity ≥ 95% **and** spill ≤ 10% of total sand |

Players can see their spill % live as a small "sand meter", which encourages replaying for 3 stars.

---

## 7. Elements (introduced roughly one every 8–10 levels)

| Element | Behaviour | Introduced |
|---|---|---|
| Colored sand | Falls, piles at ~35° angle of repose, slides | L1 |
| Walls / glass | Static solid | L1 |
| Jar | Collects sand, has fill line + target color, corks on success | L1 |
| Funnel | Narrows a stream (just wall shapes, but taught as a concept) | L5 |
| Valve hopper | Holds sand until tapped open | L7 |
| Color filter | Gate that lets only its color pass; other colors pile up on it | L11 |
| Splitter | Wedge that splits a stream 50/50 left/right | L15 |
| Mixer | Blue + yellow in → green out (any 2 primaries) | L16 |
| Fan | Tap to toggle; pushes sand sideways in its zone | L18 |
| Painting frame | A grid of small slots, each needing a color → completes a picture | L20 (boss levels) |
| Heat lamp | Turns sand it touches into glass (a permanent wall you build) | W2 |
| Water | Wet sand clumps and stops sliding until it dries (~3 s) | W2 |
| Conveyor | Moves sand horizontally regardless of tilt | W3 |
| Portal pair | Sand entering A comes out of B | W3 |
| Black sand | Contaminates; must be dumped in the void, never in a jar | W4 |
| Rotating jar | Jar slowly swings on a hinge | W4 |

Rule: **never introduce two new elements in one level.** A new element first appears in a level that is easy on purpose.

---

## 8. First 20 levels

| # | New concept | Setup | Teaches |
|---|---|---|---|
| 1 | Tilt | 1 open hopper, 1 jar straight below-right | "Tilt and sand moves" |
| 2 | Aim | Jar offset behind a small wall | Angle matters |
| 3 | Two jars, one color | Jars far left and far right | Tilting back spills — cork saves you |
| 4 | Two colors | Blue and yellow piles, matching jars | Purity |
| 5 | Funnel | Wide pile → narrow neck → small jar | Control the stream |
| 6 | Order | Jar near the edge, must be filled first | Which jar first? |
| 7 | Valve | Sand held in a hopper, tap to open | Pacing |
| 8 | Two valves | Opening order changes the outcome | Planning |
| 9 | Zigzag | Long channel maze | Pleasure level (easy, very satisfying) |
| 10 | **Boss: Hourglass** | Uses everything so far, 3 jars | Mastery check, bigger reward |
| 11 | Filter | Mixed pile; a blue filter above the blue jar | Filters sort for you |
| 12 | Filter + shared channel | Both colors must use one channel | Timing through a filter |
| 13 | Three jars | Three colors | Load management |
| 14 | Tight budget | Only 10% extra sand | Spill matters |
| 15 | Splitter | One stream must fill two jars | Symmetry |
| 16 | Mixer | No green sand anywhere, but a green jar | "Aha" moment |
| 17 | Mixer + filter | Need green and blue from the same source | Combining tools |
| 18 | Fan | Fan pushes the stream across a gap | Active control |
| 19 | Pleasure level | Big cascading machine, generous | Breather before the boss |
| 20 | **Boss: Desert Sunset** | Painting frame of 12 slots | Unlocks the first Album picture |

**Difficulty curve:** sawtooth. Each 10-level block ramps up, drops to a "pleasure level" at 9 and 19, then spikes at the boss. Target first-try fail rate: L1–10 under 5%, L11–30 about 15%, later boss levels 30–40%.

---

## 9. Meta progression

### Sand Albums (the main collection)
- Each world has an album of 4 mosaic pictures × 12 tiles.
- Every level completed fills one tile with a small sand-pour animation. Boss levels finish a picture.
- A completed picture plays a short "sand art" reveal that's made to be screenshotted.

### Worlds
1. **Desert Glass** (tutorial world, warm tones)
2. **Tide Pools** (water, heat lamps)
3. **Candy Factory** (conveyors, portals)
4. **Neon Night** (black sand, glowing sand)
5. **Volcano Lab** (lava sand: melts glass walls)

About 60 levels per world. Ship world 1–2 at launch (120 levels) and add a world every 4–6 weeks.

### Currencies
- **Coins** (soft): from levels, chests, daily. Spent on boosters and cosmetics.
- **Gems** (hard): IAP and rare rewards. Spent on premium sand skins and event passes.

### Cosmetics (no gameplay advantage)
- **Sand skins:** glitter, rainbow, lava, starlight, pixel, gold. The particle look and sound change too.
- **Jar skins:** bottles, test tubes, fish bowls, potion flasks.
- **Cork pop effects.**

### Boosters
| Booster | Effect | How to get |
|---|---|---|
| Undo Pour | Rewinds the last 3 seconds | Coins / rewarded ad |
| +Sand | Small hopper of a chosen color | Coins / rewarded ad |
| Slow-mo | 10 s at 30% speed | Coins |
| Steady Hand | Locks corks at 70% fill instead of 100% for one jar | Gems / event reward |

---

## 10. Retention systems

| System | How it works | Why |
|---|---|---|
| **Daily Jar** | One special level a day, the same for everyone worldwide. Score = purity × speed. | Daily habit + comparison |
| **Share card** | After the Daily Jar: a pattern of colored emoji squares (e.g. 🟦🟦🟨⬛) with your purity %, plus a link | Wordle-style organic spread (we know this from Vertigo) |
| **Streak** | Consecutive days with a Daily Jar done. One free freeze per week. | Loss aversion |
| **Win streak bonus** | 3 / 5 / 10 levels without retrying → stacking coin bonus + a starting booster | Standard hybrid-casual retention |
| **Star chest** | Every 20 stars → chest | Short-term goal |
| **Weekly event "Sand Rush"** | 7-day event track of 15 special levels with a new element preview. Reward: an exclusive sand skin. | Brings players back, tests new mechanics |
| **Notifications** | Max 1 a day: "Your daily jar is ready" / "Your streak ends in 2h". Opt-in, honest. | Re-engagement without spam |

Not at launch: energy/lives system. Retrying is free; ads pay instead. Revisit after soft-launch data.

---

## 11. Virality features

1. **Auto-clip.** The last 8 s of every level are kept in a low-res ring buffer. A 3-star finish, a near-miss save, or a completed album picture shows a **"Share clip"** button (exports MP4 with a small watermark + game name).
2. **Daily Jar share card** (see above).
3. **"Sand Art" mode** (unlocked at L20): free sandbox to pour pictures and export them. Gives creators content even when they're not playing levels.
4. **Clip-able sound design.** Every pour should sound great on a phone speaker (see §12).
5. **Marketing creative test** before full production: 3 × 15 s videos (tilt-to-pour, near-spill save, painting reveal). Measure CPI/CTR in one test market. If tilt videos don't beat a plain sort-puzzle video, rethink before building content.

---

## 12. Game feel ("juice")

- **Sound:** a granular "hiss" whose volume and pitch follow how many grains are moving. Pitch rises as a jar nears its line. A deep *thunk* + glassy *pop* when the cork goes in.
- **Haptics:** light continuous buzz scaled to flow rate (Android `VibrationEffect` amplitude control where supported), a sharp click on cork.
- **Visuals:** each grain has a slight color variation; settled sand gets a subtle shadow so piles read as 3D; the glass gets a soft glare that moves with tilt.
- **Camera:** the whole level very slightly counter-rotates (≈ 10% of the tilt) so the player *feels* the tilt without losing readability.
- **Completion:** all corks pop in sequence, jars do a little hop, the mosaic tile flies to the album.

---

## 13. Monetization

| Source | Placement | Notes |
|---|---|---|
| Rewarded ads | +Sand on fail, Undo, double level coins, chest boost | Primary revenue, always optional |
| Interstitials | After a level completion, only from level 15+, at most 1 per 3 min, never after a fail | Keep them off the first session |
| Remove Ads | One-time IAP (~$3.99) | Removes interstitials, keeps optional rewarded ads |
| Sand / jar skin packs | IAP or gems | Pure cosmetics |
| Event pass | Free + premium track (~$4.99) per Sand Rush | Add after soft launch, not MVP |
| Starter pack | Once, after L10: gems + 2 skins + remove ads | Common best-converting offer |

No pay-to-win. Every level is solvable for free, every time.

---

## 14. Technical design

### Engine
Use whatever engine Cosmo Drop shipped on, since the team already knows the build/store pipeline. If starting fresh: **Godot 4 (C#)** or **Unity (C# + Burst)**. Both handle this fine. Don't use GDScript for the simulation loop (too slow).

### Sand simulation: grid cellular automaton (not rigid-body physics)
- The playfield is a grid of cells (≈ **240 × 420** for portrait, upscaled with nearest-neighbour filtering for a crisp pixel-sand look).
- Each cell = 1 byte type (empty, wall, sand-color-N, water, …) in a flat array.
- Each frame, for each sand cell, try to move **in the gravity direction**:
  1. Snap the gravity angle to its two nearest of 8 neighbour directions; pick one at random, weighted by how close the angle is (this gives smooth flow at any tilt with no rigid 45° steps).
  2. If blocked, try the two diagonals beside it (random order).
  3. If still blocked, it rests. Resting cells are skipped until a neighbour changes (sleeping = big performance win).
- Sweep the grid starting from the side gravity points to, so grains don't "teleport" several cells per frame.
- Render: write the grid into a texture every frame (one upload), draw it as a single quad.
- Use a **seeded RNG**. Each level/daily jar always starts the same, and replays are reproducible for debugging.
- Target: **60 fps on a 2020 budget Android** (e.g. 3–4 GB RAM, Helio G-series). Profile on a cheap phone in week 1, not week 8.

> Why not Box2D particles: thousands of rigid bodies are slow on low-end phones, look like marbles rather than sand, and are hard to keep consistent across devices. A cellular automaton is cheaper, more predictable, and looks more like real sand.

### Levels as images (cheap content pipeline)
- Each level is a **PNG** at grid resolution: pixel colors map to element types (black = wall, blue = blue sand, etc.), plus a tiny JSON next to it for jars (position, color, fill line, purity), valves and fans.
- Designers can draw levels in any image editor (Aseprite, Photoshop, even MS Paint).
- Add a debug in-game level editor later, only once level count passes ~100 and the PNG workflow starts to hurt.

### Save data
Local only for MVP (progress, coins, cosmetics, streak) in a single JSON file. Add Google Play Games cloud save when players start asking for it.

### Analytics events (minimum)
`level_start`, `level_complete {stars, purity, spill, time, retries}`, `level_fail {reason}`, `booster_used`, `ad_shown {type}`, `iap_purchase`, `daily_jar_complete`, `share_clicked {type}`, `tilt_mode {sensor|touch}`, `recenter_pressed`.
Use these to find the levels where players quit and to tune them.

---

## 15. KPI targets (soft launch)

| Metric | Target | Notes |
|---|---|---|
| D1 retention | ≥ 40% | Below 35% → first-session problem |
| D7 retention | ≥ 15% | Hybrid-casual benchmark range 15–22% |
| D30 retention | ≥ 6% | |
| Avg session length | 8–12 min | |
| Sessions per day | ≥ 3 | |
| L10 reached (D0) | ≥ 70% of installs | Tutorial health |
| Share rate (Daily Jar) | ≥ 5% of completions | Viral health |
| CPI (test market) | Lower than a generic sort-puzzle creative | Validates the tilt hook |

---

## 16. MVP scope (≈ 8 weeks, small team)

**In:**
- Sand simulation + tilt + touch-tilt + recenter + calibration settings
- 7 elements: sand, walls, jars (with cork), funnels, valves, filters, mixer
- 60 levels (world 1) incl. 6 painting boss levels
- Album (1 world), stars, star chests, coins
- Daily Jar + share card + streak
- Undo / +Sand boosters, rewarded ads, capped interstitials, Remove Ads IAP
- Sound + haptics pass
- Analytics

**Out (add after soft-launch data):** weekly events, event pass, gems, cosmetic store, auto-clip export, Sand Art mode, worlds 2+, cloud save, leaderboards.

### Milestones
| Week | Goal |
|---|---|
| 1–2 | **Toy prototype:** sand + tilt in an empty box. Hand it to 5 people with no instructions. If they don't keep playing with it for 2+ minutes, fix the feel before anything else. |
| 2 | Marketing creative test (§11.5) in parallel |
| 3–4 | Jars, corks, valves, filters, 20 levels, star rating |
| 5–6 | Mixer, 60 levels, album, Daily Jar, share card, sound/haptics |
| 7 | Ads, IAP, analytics, settings, low-end performance pass |
| 8 | Closed test (Play Console internal testing), bug fixing → soft launch |

---

## 17. Risks

| Risk | Mitigation |
|---|---|
| Tilt is awkward lying down / on transport | Auto-recenter per level, recenter button, touch-tilt mode |
| Motion sickness / wrist fatigue | ±70° clamp, small camera counter-rotation, pleasure levels, short levels |
| Sort/flow genre is crowded and cooling | Tilt is the hook, not the theme. Validate with the creative test before building content. |
| Performance on cheap phones | Cellular automaton with sleeping cells; profile a low-end device from week 1 |
| Levels feel random / unfair | Seeded RNG, purity threshold with slack, Undo booster |
| Easy to clone | Speed to market + live ops (weekly events, new elements) + the album/collection as long-term value |

---

## 18. Open questions

1. Portrait only, or allow landscape for tablets?
2. Should painting boss levels allow free tilt (all 360°) as a special treat?
3. Lives system: test in soft launch as an A/B, or stay life-free?
4. Name: "Pour", "Sandfall", "Tilt & Pour", "Grain"? Check Play Store search competition before deciding.
5. Do we want a premium (paid, no ads) edition too?
