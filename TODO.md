# TODO — things only the owner can do

These are things Claude can't do alone: accounts, keys, payments, physical devices, and decisions.
Each item says **when** it blocks work (phase numbers refer to [PLAN.md](PLAN.md)).
Tick items off here and add notes (e.g. where a secret is stored, **never the secret itself**).

## Decisions needed

- [ ] **Git:** OK to `git init` and commit? (Phase 0, now)
- [ ] **Application ID / bundle ID.** Currently `com.pourgame.pour_sand_game`. It **can't change after the first Play upload**. Pick the final one. (Before Phase 11; ideally now)
- [ ] **Game name** (GDD §18 Q4: Pour / Sandfall / Tilt & Pour / Grain). Check Play Store search competition. (Phase 2)
  - The logo is built around **"P[jar]UR"**, with the jar standing in for the O. A name without an O (or similar) needs a new wordmark. The jar mark and app icon work with any name. Decide before store art (Phase 11).
- [ ] **Splitter & fan in MVP?** GDD §8 uses them at L15/L18, but MVP §16 leaves them out. The plan includes them because they're cheap. (Phase 4)
- [ ] **Target audience age.** Choosing under-13 brings Families policy ad limits. Recommended: 13+. (Phase 8)
- [ ] **Music:** license a track, or approve a generated one. (Phase 7)
- [ ] **AI image generation for album art / store graphics.** It spends your creative-tool credits. Approve per batch. (Phases 5, 11)
- [ ] Open GDD questions §18: landscape for tablets? free 360° tilt in painting levels? lives A/B? premium edition?

## Emulator / devices

- [ ] **Emulator storage.** `Medium_Phone_API_36.1` has ~470 MB free, so the 139 MB debug APK fails to install (`INSTALL_FAILED_INSUFFICIENT_STORAGE`). Profile builds work, but there's no hot reload. Pick one fix:
  - Free space by uninstalling unused apps on it (`in.sawari.sawari`, `com.varad.bolo`), or
  - Android Studio → Device Manager → the AVD → Edit → Advanced → Internal Storage 8 GB → Wipe Data, or
  - Tell Claude to create a separate project AVD with larger storage. It's local and reversible, and uses ~4–8 GB of host disk.
- [ ] **A real low-end Android phone** (2020-era, 3–4 GB RAM, e.g. Helio G-series) with USB debugging on. Needed for the performance gate. (Phase 1, again in 7 and 10)
- [ ] At least one more real Android phone, ideally a different maker, for tilt-feel calibration. (Phase 1)
- [ ] **Toy test:** hand the Phase 1 build to 5 people with no instructions and note whether they keep playing past 2 minutes. (End of Phase 1)
- [ ] **Play levels 1–4 on your phone** (dist/pour-phase3-arm64.apk) and report:
  - Does tilting past ~45° to pour feel right? Sand now pours over lips and out of uncorked jars at that tilt. The sandbox shows it too.
  - Is level 1 obvious without help?
  - Do the valve and filter read clearly?
  This is the last feel check before Phase 4 builds 60 levels on this physics. (Phase 3)
- [ ] **Playtest World 1 on a real phone** (Phase 4). The levels are proven solvable; whether they're *fun* and fairly paced is what only you can judge. Report where you got stuck, bored or confused, especially:
  - Bosses (10, 20, 30, …).
  - Mixer levels (16, 27, 35, 58): do you manage to tap both valves together?
  - Whether 21–60 feel too samey; they're remixes and combos of 1–20.
  - Dev builds unlock every level. "Watch solution" in the pause menu shows the intended play.

## Accounts & credentials (store secrets outside the repo; add the path here, not the value)

- [ ] **Google Play Console** developer account ($25 one-time). (Before Phase 11; the account takes days to verify, so start early)
  - New personal accounts must run a **closed test with 12+ testers for 14 consecutive days** before production. Start recruiting testers in Phase 8.
- [ ] **Firebase project.** Add the Android app with the final application ID, download `google-services.json`, and put it at `android/app/google-services.json` (git-ignored). (Phase 9)
- [ ] **AdMob account.** Create the app, then give Claude the **AdMob App ID** and the **ad unit IDs** (rewarded, interstitial). These aren't secret, but they're yours. Until then Claude uses Google's test IDs only. (Phase 8)
- [ ] **Payments profile + merchant account** in Play Console, needed for IAP. Then create the products `remove_ads` and `starter_pack`, and add license-tester Gmail accounts. (Phase 8)
- [ ] **Upload keystore.** Create it, back it up in two places, and fill in `android/key.properties` (git-ignored). Claude can give you the exact `keytool` command. (Phase 11)
- [ ] **Privacy policy URL**, hosted anywhere public (GitHub Pages, your site). Claude can draft the text. (Phase 11)
- [ ] Store listing assets sign-off, plus the Data safety form and content rating questionnaire answers. Claude drafts them, you submit. (Phase 11)
- [ ] Optional: **ElevenLabs** auth (`/mcp` in Claude) if you want AI-generated SFX/music instead of procedural ones. (Phase 7)

## iOS (later)

- [ ] A Mac with Xcode, plus an **Apple Developer Program** membership ($99/yr). The iOS build and test can't be done from this Windows PC. (Phase 12)
- [ ] App Store Connect app record, AdMob iOS app ID, StoreKit products. (Phase 12)
