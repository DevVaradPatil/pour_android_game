import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:pour_sand_game/meta/economy.dart';
import 'package:pour_sand_game/meta/progress.dart';
import 'package:pour_sand_game/meta/save_data.dart';
import 'package:pour_sand_game/meta/save_store.dart';
import 'package:pour_sand_game/services/ads.dart';
import 'package:pour_sand_game/services/store.dart';

class FakeAds implements AdBackend {
  bool ready = true, earn = true;
  int interstitials = 0, rewardeds = 0;
  Completer<bool>? open; // set to keep a rewarded ad "on screen"

  @override
  Future<bool> init() async => true;
  @override
  bool get rewardedReady => ready;
  @override
  Future<bool> showRewarded() {
    rewardeds++;
    return open?.future ?? Future.value(earn);
  }

  @override
  Future<void> showInterstitial() async => interstitials++;
  @override
  Future<bool> privacyOptionsRequired() async => false;
  @override
  Future<void> showPrivacyOptions() async {}
  @override
  set onChanged(VoidCallback f) {}
}

class FakeIap implements InAppPurchase {
  final completed = <String>[];
  @override
  Future<void> completePurchase(PurchaseDetails purchase) async => completed.add(purchase.productID);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

PurchaseDetails purchase(String id, PurchaseStatus s, {bool complete = true}) => PurchaseDetails(
      productID: id,
      verificationData: PurchaseVerificationData(localVerificationData: '', serverVerificationData: '', source: 'test'),
      transactionDate: null,
      status: s,
    )..pendingCompletePurchase = complete;

void main() {
  setUp(() => progress = Progress());

  group('interstitial pacing', () {
    test('rules: level 15+, 3 min apart, never with Remove Ads', () {
      const long = Duration(minutes: 5);
      expect(interstitialDue(level: 14, sinceLast: long, removeAds: false), isFalse);
      expect(interstitialDue(level: 15, sinceLast: long, removeAds: false), isTrue);
      expect(interstitialDue(level: 15, sinceLast: const Duration(minutes: 2), removeAds: false), isFalse);
      expect(interstitialDue(level: 30, sinceLast: long, removeAds: true), isFalse);
    });

    test('with a fake clock: none in the first 3 minutes, then at most one per 3 minutes', () async {
      var now = DateTime(2026, 11, 20, 12);
      final fake = FakeAds();
      final a = Ads(clock: () => now);
      await a.init(fake);
      await a.afterWin(20);
      expect(fake.interstitials, 0); // session just started
      now = now.add(const Duration(minutes: 3));
      await a.afterWin(20);
      await a.afterWin(21);
      expect(fake.interstitials, 1);
      now = now.add(const Duration(minutes: 4));
      await a.afterWin(5); // early level: never
      expect(fake.interstitials, 1);
      progress.grant(removeAdsId);
      await a.afterWin(22);
      expect(fake.interstitials, 1);
    });
  });

  group('rewarded', () {
    test('a reward is granted once, and only when earned', () async {
      final fake = FakeAds()..open = Completer<bool>();
      final a = Ads();
      await a.init(fake);
      final first = a.rewarded();
      expect(await a.rewarded(), isFalse); // double tap while showing
      fake.open!.complete(true);
      expect(await first, isTrue);
      expect(fake.rewardeds, 1);
      fake
        ..open = null
        ..earn = false;
      expect(await a.rewarded(), isFalse); // closed early
    });

    test('no ad loaded (offline, no consent): nothing offered, nothing blocks', () async {
      final a = Ads();
      expect(a.rewardedReady, isFalse);
      expect(await a.rewarded(), isFalse);
      await a.afterWin(40); // returns at once
    });
  });

  group('store', () {
    test('purchased / restored grant once and are always completed; others grant nothing', () async {
      final iap = FakeIap();
      final s = Store(iap);
      await s.onPurchases([purchase(starterPackId, PurchaseStatus.purchased)]);
      expect(progress.removeAds, isTrue);
      expect(progress.data.coins, starterPackCoins);
      await s.onPurchases([purchase(starterPackId, PurchaseStatus.restored)]);
      expect(progress.data.coins, starterPackCoins); // not twice
      await s.onPurchases([
        purchase(removeAdsId, PurchaseStatus.pending, complete: false),
        purchase(removeAdsId, PurchaseStatus.error),
        purchase(removeAdsId, PurchaseStatus.canceled),
      ]);
      expect(progress.data.owned, {starterPackId});
      expect(iap.completed, [starterPackId, starterPackId, removeAdsId, removeAdsId]);
    });
  });

  test('coins: spend only what you have', () {
    progress.addCoins(50);
    expect(progress.spend(undoCoins), isTrue);
    expect(progress.spend(sandCoins), isFalse);
    expect(progress.data.coins, 50 - undoCoins);
  });

  test('a v2 save migrates to v3 with no purchases', () {
    final dir = Directory.systemTemp.createTempSync('pour_v2_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/save.json').writeAsStringSync(jsonEncode({'v': 2, 'coins': 7, 'stars': {'w1/001': 2}}));
    final d = SaveStore(dir).load();
    expect(d.coins, 7);
    expect(d.owned, isEmpty);
    expect(d.toJson()['v'], SaveData.version);
    expect(SaveData.version, 3);
  });
}
