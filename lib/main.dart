import 'package:flutter/material.dart';

import 'ui/home_screen.dart';
import 'ui/theme.dart';

void main() {
  registerFontLicenses();
  runApp(const PourApp());
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
