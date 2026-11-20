import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/game_screen.dart';
import '../game/sand_screen.dart';
import '../level/level_check.dart';
import 'brand.dart';
import 'components.dart';
import 'gallery_screen.dart';
import 'tokens.dart';

/// Title + World 1 level list. (Phase 4 replaces the list with the world map.)
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Future<List<String>> _paths =
      rootBundle.loadString('assets/levels/levels.json').then(parseLevelIndex);

  Future<void> _play(List<String> paths, int i) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GameScreen(paths: paths, index: i)));
    setState(() {}); // refresh stars
  }

  void _push(Widget screen) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<String>>(
          future: _paths,
          builder: (context, snap) {
            final paths = snap.data;
            if (paths == null) return const SizedBox.shrink();
            final current = paths.indexWhere((p) => (sessionStars[p] ?? 0) == 0);
            return Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Column(
                children: [
                  const SizedBox(height: Space.xxl),
                  const Wordmark(height: 64),
                  const SizedBox(height: Space.s),
                  Text('World 1 · Desert Glass', style: PourText.heading.copyWith(color: PourColors.textMuted)),
                  const SizedBox(height: Space.xxl),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: Space.xl,
                        runSpacing: Space.xl,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final (i, p) in paths.indexed)
                            LevelNode(
                              number: i + 1,
                              stars: sessionStars[p] ?? 0,
                              state: i == current ? LevelState.current : LevelState.open,
                              onTap: () => _play(paths, i),
                            ),
                        ],
                      ),
                    ),
                  ),
                  PourButton(
                    label: 'Play',
                    icon: Icons.play_arrow_rounded,
                    expand: true,
                    onPressed: () => _play(paths, current < 0 ? 0 : current),
                  ),
                  if (!kReleaseMode)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(onPressed: () => _push(const SandScreen()), child: const Text('Sandbox')),
                        TextButton(onPressed: () => _push(const GalleryScreen()), child: const Text('Design system')),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
