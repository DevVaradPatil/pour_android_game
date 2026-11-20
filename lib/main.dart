import 'package:flutter/material.dart';

import 'game/sand_screen.dart';

void main() => runApp(const PourApp());

class PourApp extends StatelessWidget {
  const PourApp({super.key, this.home = const SandScreen()});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pour',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE8A54B),
          brightness: Brightness.dark,
        ),
      ),
      home: home,
    );
  }
}
