// Ads: consent first (Google UMP), then rewarded + interstitial ads.
// The game asks [ads] in game terms; [AdBackend] does the SDK work, so tests
// use a fake. Ads are always optional: nothing waits on them, and with no ad
// (offline, no consent, SDK error) the buttons simply aren't offered.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../meta/economy.dart';
import '../meta/progress.dart';

abstract class AdBackend {
  /// Consent, then the SDK. False: no ads this session.
  Future<bool> init();
  bool get rewardedReady;

  /// Shows a rewarded ad; true if the player earned the reward.
  Future<bool> showRewarded();
  Future<void> showInterstitial();

  /// GDPR regions must offer a way back to the consent choices.
  Future<bool> privacyOptionsRequired();
  Future<void> showPrivacyOptions();

  /// Called when ad readiness changes.
  set onChanged(VoidCallback f);
}

class Ads extends ChangeNotifier {
  Ads({DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    _lastInterstitial = _clock(); // none in the first 3 minutes
  }

  final DateTime Function() _clock;
  late DateTime _lastInterstitial;
  AdBackend? _backend;
  bool _showing = false;

  Future<void> init(AdBackend backend) async {
    backend.onChanged = notifyListeners;
    try {
      if (await backend.init()) _backend = backend;
    } on Object catch (e) {
      debugPrint('ads off: $e');
    }
    notifyListeners();
  }

  bool get rewardedReady => !_showing && (_backend?.rewardedReady ?? false);

  /// Shows a rewarded ad. True at most once per call, and only if earned;
  /// a second tap while one is showing gets false.
  Future<bool> rewarded() async {
    final b = _backend;
    if (b == null || !rewardedReady) return false;
    _showing = true;
    notifyListeners();
    try {
      return await b.showRewarded();
    } on Object {
      return false;
    } finally {
      _showing = false;
      notifyListeners();
    }
  }

  /// After a win (never after a fail): maybe an interstitial, by the pacing
  /// rules. Completes when it's closed, or at once if none is shown.
  Future<void> afterWin(int level) async {
    final b = _backend;
    final now = _clock();
    if (b == null ||
        _showing ||
        !interstitialDue(level: level, sinceLast: now.difference(_lastInterstitial), removeAds: progress.removeAds)) {
      return;
    }
    _lastInterstitial = now;
    _showing = true;
    try {
      await b.showInterstitial();
    } on Object {
      // no ad: carry on
    } finally {
      _showing = false;
    }
  }

  Future<bool> privacyOptionsRequired() async => await _backend?.privacyOptionsRequired() ?? false;
  Future<void> showPrivacyOptions() async => _backend?.showPrivacyOptions();
}

Ads ads = Ads();

/// Google Mobile Ads + UMP. Uses Google's **test** ad units until the owner
/// supplies real ones (TODO.md); the app IDs live in AndroidManifest.xml / Info.plist.
class GoogleAds implements AdBackend {
  static final _rewardedId = Platform.isIOS
      ? 'ca-app-pub-3940256099942544/1712485313'
      : 'ca-app-pub-3940256099942544/5224354917';
  static final _interstitialId = Platform.isIOS
      ? 'ca-app-pub-3940256099942544/4411468910'
      : 'ca-app-pub-3940256099942544/1033173712';

  /// `--dart-define=UMP_EEA=true` shows the consent form as if in the EEA (testing).
  static const _debugEea = bool.fromEnvironment('UMP_EEA');

  RewardedAd? _rewarded;
  InterstitialAd? _interstitial;
  VoidCallback _changed = () {};
  int _retry = 0;

  @override
  set onChanged(VoidCallback f) => _changed = f;

  @override
  Future<bool> init() async {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(
        consentDebugSettings: _debugEea ? ConsentDebugSettings(debugGeography: DebugGeography.debugGeographyEea) : null,
      ),
      () => ConsentForm.loadAndShowConsentFormIfRequired((_) => done.complete()),
      (_) => done.complete(), // offline etc.: fall back to the stored choice
    );
    await done.future;
    if (!await ConsentInformation.instance.canRequestAds()) return false;
    await MobileAds.instance.initialize();
    _loadRewarded();
    _loadInterstitial();
    return true;
  }

  // Failed loads retry with backoff (30 s, 60 s, … capped at 5 min).
  void _later(void Function() load) {
    _retry++;
    Timer(Duration(seconds: (30 * _retry).clamp(30, 300)), load);
  }

  void _loadRewarded() => RewardedAd.load(
    adUnitId: _rewardedId,
    request: const AdRequest(),
    rewardedAdLoadCallback: RewardedAdLoadCallback(
      onAdLoaded: (ad) {
        _retry = 0;
        _rewarded = ad;
        _changed();
      },
      onAdFailedToLoad: (e) {
        debugPrint('rewarded failed: ${e.message}');
        _later(_loadRewarded);
      },
    ),
  );

  void _loadInterstitial() => InterstitialAd.load(
    adUnitId: _interstitialId,
    request: const AdRequest(),
    adLoadCallback: InterstitialAdLoadCallback(
      onAdLoaded: (ad) => _interstitial = ad,
      onAdFailedToLoad: (e) => _later(_loadInterstitial),
    ),
  );

  @override
  bool get rewardedReady => _rewarded != null;

  @override
  Future<bool> showRewarded() {
    final ad = _rewarded;
    if (ad == null) return Future.value(false);
    _rewarded = null;
    _changed();
    var earned = false;
    final closed = Completer<bool>();
    void finish() {
      ad.dispose();
      _loadRewarded();
      if (!closed.isCompleted) closed.complete(earned);
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) => finish(),
      onAdFailedToShowFullScreenContent: (_, _) => finish(),
    );
    ad.show(onUserEarnedReward: (_, _) => earned = true);
    return closed.future;
  }

  @override
  Future<void> showInterstitial() {
    final ad = _interstitial;
    if (ad == null) return Future.value();
    _interstitial = null;
    final closed = Completer<void>();
    void finish() {
      ad.dispose();
      _loadInterstitial();
      if (!closed.isCompleted) closed.complete();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) => finish(),
      onAdFailedToShowFullScreenContent: (_, _) => finish(),
    );
    ad.show();
    return closed.future;
  }

  @override
  Future<bool> privacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  @override
  Future<void> showPrivacyOptions() {
    final done = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((_) => done.complete());
    return done.future;
  }
}
