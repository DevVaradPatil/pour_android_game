// In-app purchases: Remove Ads and the Starter Pack (both one-time).
// Purchases are granted locally through progress.grant (once per save) and
// always acknowledged, so Google Play doesn't refund them after 3 days.
// ponytail: no server-side receipt check; add one if fraud ever matters.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../meta/economy.dart';
import '../meta/progress.dart';

class Store extends ChangeNotifier {
  Store([InAppPurchase? iap]) : _iapOverride = iap;

  final InAppPurchase? _iapOverride;
  InAppPurchase get _iap => _iapOverride ?? InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Products the store returned (empty until the owner creates them in Play Console).
  Map<String, ProductDetails> products = {};
  bool ready = false; // init() finished
  bool pending = false; // a purchase is waiting (e.g. cash payment)
  String? message; // last thing to tell the player

  Future<void> init() async {
    _sub ??= _iap.purchaseStream.listen(onPurchases, onError: (Object e) => debugPrint('store: $e'));
    try {
      if (await _iap.isAvailable()) {
        final r = await _iap.queryProductDetails({removeAdsId, starterPackId});
        products = {for (final p in r.productDetails) p.id: p};
      }
    } on Object catch (e) {
      debugPrint('store unavailable: $e');
    }
    ready = true;
    notifyListeners();
  }

  /// The purchase state machine: grant on purchased/restored, report errors,
  /// and always complete what the platform says needs completing.
  @visibleForTesting
  Future<void> onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          pending = false;
          if (progress.grant(p.productID)) {
            message = p.productID == starterPackId
                ? 'Starter Pack unlocked: no ads, +$starterPackCoins coins'
                : 'Ads removed. Thank you!';
          }
        case PurchaseStatus.pending:
          pending = true;
          message = 'Purchase pending…';
        case PurchaseStatus.error:
          pending = false;
          message = 'Purchase failed: ${p.error?.message ?? 'unknown error'}';
        case PurchaseStatus.canceled:
          pending = false;
      }
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
    notifyListeners();
  }

  Future<void> buy(String id) async {
    final p = products[id];
    if (p == null) return;
    message = null;
    try {
      await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: p));
    } on Object catch (e) {
      message = 'Purchase failed: $e';
      notifyListeners();
    }
  }

  Future<void> restore() async {
    message = 'Restoring purchases…';
    notifyListeners();
    try {
      await _iap.restorePurchases();
    } on Object catch (e) {
      message = 'Restore failed: $e';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

Store store = Store();
