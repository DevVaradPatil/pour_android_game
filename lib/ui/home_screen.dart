import 'dart:math' as math;

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

/// Title + World 1 map: a winding path of level nodes, boss every 10th.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const double _rowH = 104;
  late final Future<List<String>> _paths =
      rootBundle.loadString('assets/levels/levels.json').then(parseLevelIndex);
  final _scroll = ScrollController();
  bool _scrolledToCurrent = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Next level to play: first one without stars.
  int _current(List<String> paths) {
    final i = paths.indexWhere((p) => (sessionStars[p] ?? 0) == 0);
    return i < 0 ? paths.length - 1 : i;
  }

  /// Sequential unlocking; dev builds open everything for testing.
  bool _unlocked(List<String> paths, int i) => !kReleaseMode || i == 0 || (sessionStars[paths[i - 1]] ?? 0) > 0;

  Future<void> _play(List<String> paths, int i, {bool autoplay = false}) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => GameScreen(paths: paths, index: i, autoplay: autoplay)));
    setState(() {});
  }

  void _push(Widget screen) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  double _nodeX(int i, double width) => width / 2 + math.sin(i * 0.85) * width * 0.27;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<String>>(
          future: _paths,
          builder: (context, snap) {
            final paths = snap.data;
            if (paths == null) return const SizedBox.shrink();
            final current = _current(paths);
            final stars = paths.fold(0, (a, p) => a + (sessionStars[p] ?? 0));
            if (!_scrolledToCurrent) {
              _scrolledToCurrent = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scroll.hasClients) {
                  _scroll.jumpTo(math.max(0, math.min(_scroll.position.maxScrollExtent, (current - 1) * _rowH)));
                }
              });
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.xl, Space.s),
                  child: Row(
                    children: [
                      const Wordmark(height: 40),
                      const Spacer(),
                      CounterChip(icon: Icons.star_rounded, value: stars, iconColor: PourColors.accent, label: 'stars'),
                    ],
                  ),
                ),
                Text('World 1 · Desert Glass', style: PourText.heading.copyWith(color: PourColors.textMuted)),
                const SizedBox(height: Space.s),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) => SingleChildScrollView(
                      controller: _scroll,
                      child: SizedBox(
                        height: paths.length * _rowH + Space.xxl,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _PathPainter(paths.length, _rowH, (i) => _nodeX(i, c.maxWidth), current),
                              ),
                            ),
                            for (final (i, p) in paths.indexed)
                              Positioned(
                                left: _nodeX(i, c.maxWidth) - 40,
                                top: i * _rowH + Space.l,
                                width: 80,
                                child: Column(
                                  children: [
                                    LevelNode(
                                      number: i + 1,
                                      stars: sessionStars[p] ?? 0,
                                      state: !_unlocked(paths, i)
                                          ? LevelState.locked
                                          : (i == current ? LevelState.current : LevelState.open),
                                      onTap: () => _play(paths, i),
                                    ),
                                    if ((i + 1) % 10 == 0)
                                      Text('BOSS', style: PourText.label.copyWith(color: PourColors.accent)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.xl, Space.s, Space.xl, Space.m),
                  child: PourButton(
                    label: 'Play level ${current + 1}',
                    icon: Icons.play_arrow_rounded,
                    expand: true,
                    onPressed: () => _play(paths, current),
                  ),
                ),
                if (!kReleaseMode)
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      TextButton(onPressed: () => _push(const SandScreen()), child: const Text('Sandbox')),
                      TextButton(onPressed: () => _push(const GalleryScreen()), child: const Text('Design system')),
                      TextButton(onPressed: () => _play(paths, 0, autoplay: true), child: const Text('Autoplay all')),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Dotted trail between level nodes; the stretch already played is amber.
class _PathPainter extends CustomPainter {
  _PathPainter(this.count, this.rowH, this.x, this.current);
  final int count;
  final double rowH;
  final double Function(int) x;
  final int current;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < count - 1; i++) {
      final a = Offset(x(i), i * rowH + Space.l + 32), b = Offset(x(i + 1), (i + 1) * rowH + Space.l + 32);
      final dot = Paint()..color = i < current ? PourColors.accent.withValues(alpha: 0.7) : PourColors.outline;
      for (var t = 0.15; t < 0.9; t += 0.1) {
        canvas.drawCircle(Offset.lerp(a, b, t)!, 3, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_PathPainter old) => old.current != current || old.count != count;
}
