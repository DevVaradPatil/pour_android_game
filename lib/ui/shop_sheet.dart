import 'package:flutter/material.dart';

import '../meta/economy.dart';
import '../meta/progress.dart';
import '../services/store.dart';
import 'components.dart';
import 'tokens.dart';

/// Remove Ads, the Starter Pack (offered once level 10 is done), restore.
Future<void> showShop(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  builder: (context) => ListenableBuilder(
    listenable: Listenable.merge([store, progress]),
    builder: (context, _) {
      final noAds = progress.removeAds;
      final starter = progress.data.stars.length >= 10 || progress.data.owned.contains(starterPackId);
      Widget item(String id, String title, String body, {required bool owned}) {
        final p = store.products[id];
        return ListTile(
          title: Text(title, style: PourText.heading),
          subtitle: Text(body),
          trailing: owned
              ? Text('Owned', style: PourText.label.copyWith(color: PourColors.accent))
              : PourButton(label: p?.price ?? '—', onPressed: p == null ? null : () => store.buy(id)),
        );
      }

      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(0, Space.l, 0, Space.xl),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: Text('Shop', style: PourText.title),
          ),
          item(
            removeAdsId,
            'Remove ads',
            'No ads between levels. Ads you choose to watch for rewards stay.',
            owned: noAds,
          ),
          if (starter)
            item(
              starterPackId,
              'Starter Pack',
              'Remove ads + $starterPackCoins coins. One time only.',
              owned: progress.data.owned.contains(starterPackId),
            ),
          if (store.ready && store.products.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Space.l),
              child: Text(
                "The store isn't available right now.",
                style: PourText.body.copyWith(color: PourColors.textMuted),
              ),
            ),
          if (store.message case final m?)
            Padding(
              padding: const EdgeInsets.all(Space.l),
              child: Text(m, style: PourText.body),
            ),
          Center(
            child: TextButton(onPressed: store.restore, child: const Text('Restore purchases')),
          ),
        ],
      );
    },
  ),
);
