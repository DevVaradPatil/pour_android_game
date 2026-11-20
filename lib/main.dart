import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'game/play_kit.dart';
import 'meta/progress.dart';
import 'meta/save_store.dart';
import 'services/ads.dart';
import 'services/audio.dart';
import 'services/notifications.dart';
import 'services/store.dart';

import 'ui/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  progress = Progress(SaveStore(await getApplicationSupportDirectory()));
  applyTiltSettings();
  runApp(const PourApp());
  audio.init(PluginAudio());
  unawaited(ads.init(GoogleAds())); // shows the consent form first where required
  unawaited(store.init());
  await notifications.init();
  await refreshReminder();
}

class PourApp extends StatelessWidget {
  const PourApp({super.key, this.home = const HomeScreen()});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pour',
      debugShowCheckedModeBanner: false,
      theme: buildPourTheme(),
      home: home,
    );
  }
}
