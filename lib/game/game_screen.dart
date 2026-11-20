import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../level/level.dart';
import '../level/level_run.dart';
import '../ui/brand.dart';
import '../ui/components.dart';
import '../ui/tokens.dart';
import 'play_kit.dart';

/// Best stars per level path this session.
// ponytail: in memory until the Phase 5 save file.
final Map<String, int> sessionStars = {};

/// Plays `paths[index]` (paths relative to assets/levels/, e.g. "w1/001").
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.paths, required this.index, this.accelStream});

  final List<String> paths;
  final int index;
  final Stream<AccelerometerEvent>? accelStream;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  late final TiltInput _tilt = TiltInput(stream: widget.accelStream);
  final _renderer = GridRenderer(levelW, levelH);
  final _clock = TickClock();
  final _hud = ValueNotifier<int>(0); // bumped ~10x/s to repaint HUD and overlays
  late final Ticker _ticker;

  Level? _level;
  LevelRun? _run;
  RunStatus _shown = RunStatus.playing;
  bool _paused = false;

  String get _path => widget.paths[widget.index];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _load();
  }

  Future<void> _load() async {
    final level = Level.fromJson(await rootBundle.loadString('assets/levels/$_path.json'));
    if (!mounted) return;
    _level = level;
    _restart();
  }

  void _restart() {
    setState(() {
      _run = LevelRun(_level!);
      _shown = RunStatus.playing;
      _paused = false;
    });
    _tilt.recenterOnNextSample();
    _renderer.dirty = true;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _tilt.dispose();
    _renderer.dispose();
    _hud.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final run = _run;
    final n = _clock.ticks(elapsed);
    if (run == null || _paused) return;
    for (var i = 0; i < n; i++) {
      run.setGravityDegrees(_tilt.angle);
      run.step();
      if (run.moved > 0) _renderer.dirty = true;
      if (run.tick % 6 == 0) _hud.value++;
    }
    _renderer.renderIfDirty(run.sim);
    if (run.status != _shown) {
      _shown = run.status;
      if (run.status == RunStatus.won) {
        sessionStars[_path] = math.max(sessionStars[_path] ?? 0, run.stars);
        HapticFeedback.mediumImpact();
      }
      setState(() {});
    }
  }

  void _toggleValve(int i) {
    _run?.toggleValve(i);
    HapticFeedback.selectionClick();
    _renderer.dirty = true;
    setState(() {});
  }

  // Lower third: drag = touch-tilt. Anywhere: hold = slow-mo.
  void _onPanStart(DragStartDetails d) {
    if (d.globalPosition.dy > MediaQuery.sizeOf(context).height * 2 / 3) _tilt.touchStart(d.globalPosition.dx);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_tilt.touching) _tilt.touchUpdate(d.globalPosition.dx, MediaQuery.sizeOf(context).width);
  }

  void _setSlow(bool on) {
    _run?.setSlowMo(on);
    _hud.value++;
  }

  Future<void> _saveReplay() async {
    final run = _run!;
    final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/replays/${run.level.id}.replay.json')..createSync(recursive: true);
    file.writeAsStringSync('${run.toReplay().toJson()}\n');
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved ${file.path}')));
  }

  void _next() => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => GameScreen(paths: widget.paths, index: widget.index + 1, accelStream: widget.accelStream),
      ));

  @override
  Widget build(BuildContext context) {
    final run = _run;
    return Scaffold(
      body: SafeArea(
        child: run == null
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: (_) => _tilt.touchEnd(),
                    onPanCancel: _tilt.touchEnd,
                    onLongPressStart: (_) => _setSlow(true),
                    onLongPressEnd: (_) => _setSlow(false),
                    child: Column(
                      children: [
                        _topBar(run),
                        Expanded(child: _field(run)),
                        _bottomBar(run),
                      ],
                    ),
                  ),
                  if (_paused) _pauseCard(),
                  if (run.status == RunStatus.won) _wonCard(run),
                  if (run.status == RunStatus.outOfSand) _lostCard(run),
                ],
              ),
      ),
    );
  }

  Widget _topBar(LevelRun run) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.s, 0),
        child: Row(
          children: [
            RoundIconButton(icon: Icons.arrow_back_rounded, tooltip: 'Levels', onPressed: () => Navigator.of(context).pop()),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('LEVEL ${widget.index + 1}', style: PourText.label.copyWith(color: PourColors.textMuted)),
                  Text(run.level.name, style: PourText.heading, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            RoundIconButton(icon: Icons.center_focus_strong_rounded, tooltip: 'Recenter', onPressed: _tilt.recenter),
            const SizedBox(width: Space.s),
            RoundIconButton(icon: Icons.refresh_rounded, tooltip: 'Restart', onPressed: _restart),
            const SizedBox(width: Space.s),
            RoundIconButton(
              icon: Icons.pause_rounded,
              tooltip: 'Pause',
              onPressed: run.status == RunStatus.playing ? () => setState(() => _paused = true) : null,
            ),
          ],
        ),
      );

  Widget _field(LevelRun run) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.m),
          child: AspectRatio(
            aspectRatio: levelW / levelH,
            child: LayoutBuilder(builder: (context, c) {
              final scale = c.maxWidth / levelW;
              final glyph = math.min(jarLabelRows * scale * 0.9, 30.0);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: CustomPaint(painter: GridPainter(_renderer.image, PourColors.surface))),
                  Positioned.fill(child: CustomPaint(painter: _OverlayPainter(run, _hud, glyph))),
                  for (final j in run.jars) _jarLabel(j, scale, glyph),
                  for (final (i, v) in run.level.valves.indexed) _valveButton(run, i, v, scale),
                  if (run.level.hint != null) _hint(run),
                ],
              );
            }),
          ),
        ),
      );

  Widget _jarLabel(JarState j, double scale, double size) {
    final r = j.def.r;
    return Positioned(
      left: (r.x + r.w / 2) * scale - size / 2,
      top: (r.y + r.h + jarWall + jarLabelRows / 2) * scale - size / 2,
      child: ValueListenableBuilder<int>(
        valueListenable: _hud,
        builder: (_, _, _) => Stack(
          clipBehavior: Clip.none,
          children: [
            SandGlyph(j.def.color, size: size),
            if (j.corked)
              Positioned(
                right: -size * 0.25,
                top: -size * 0.25,
                child: Icon(Icons.check_circle_rounded, size: size * 0.6, color: PourColors.accent),
              ),
          ],
        ),
      ),
    );
  }

  Widget _valveButton(LevelRun run, int i, ValveDef v, double scale) {
    const size = 40.0;
    final open = run.valveOpen[i];
    return Positioned(
      left: (v.r.x + v.r.w / 2) * scale - size / 2,
      top: (v.r.y + v.r.h / 2) * scale - size / 2,
      child: Semantics(
        button: true,
        label: open ? 'Close valve' : 'Open valve',
        excludeSemantics: true,
        child: Squish(
          onTap: run.status == RunStatus.playing ? () => _toggleValve(i) : null,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: open ? PourColors.surfaceHigh.withValues(alpha: 0.85) : PourColors.accent,
              shape: BoxShape.circle,
              border: Border.all(color: PourColors.text, width: 2),
            ),
            child: Icon(open ? Icons.lock_open_rounded : Icons.lock_rounded,
                size: 20, color: open ? PourColors.text : PourColors.onAccent),
          ),
        ),
      ),
    );
  }

  Widget _hint(LevelRun run) => Positioned(
        left: 0,
        right: 0,
        top: Space.m,
        child: ValueListenableBuilder<int>(
          valueListenable: _hud,
          builder: (_, _, _) => AnimatedOpacity(
            opacity: run.tick < 240 && run.status == RunStatus.playing ? 1 : 0,
            duration: Motion.slow,
            child: Text(run.level.hint!, textAlign: TextAlign.center, style: PourText.heading),
          ),
        ),
      );

  Widget _bottomBar(LevelRun run) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
        child: ValueListenableBuilder<int>(
          valueListenable: _hud,
          builder: (_, _, _) {
            final spill = run.spill;
            const full = 0.3; // meter is full at 30% spilled
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text('SPILL ${(spill * 100).round()}%', style: PourText.label.copyWith(color: PourColors.textMuted)),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (_, c) => Stack(
                          clipBehavior: Clip.none,
                          children: [
                            SandMeter(
                              value: spill / full,
                              height: 10,
                              label: 'Spilled sand',
                              color: spill <= run.level.starSpill ? PourColors.accent : PourColors.danger,
                            ),
                            // Third-star line.
                            Positioned(
                              left: c.maxWidth * (run.level.starSpill / full) - 1,
                              top: -3,
                              child: Container(width: 2, height: 16, color: PourColors.text),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (run.slowMo) ...[
                      const SizedBox(width: Space.m),
                      Text('SLOW', style: PourText.label.copyWith(color: PourColors.accent)),
                    ],
                  ],
                ),
                const SizedBox(height: Space.s),
                Text('drag here to tilt  ·  hold to slow down',
                    style: PourText.caption.copyWith(color: PourColors.outline)),
              ],
            );
          },
        ),
      );

  Widget _card(List<Widget> children) => Positioned.fill(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.55),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: PourCard(
                padding: const EdgeInsets.all(Space.xl),
                child: Column(mainAxisSize: MainAxisSize.min, children: children),
              ),
            ),
          ),
        ),
      );

  Widget _pauseCard() => _card([
        Text('Paused', style: PourText.title),
        const SizedBox(height: Space.xl),
        PourButton(label: 'Resume', expand: true, onPressed: () => setState(() => _paused = false)),
        const SizedBox(height: Space.m),
        PourButton(label: 'Restart', style: PourButtonStyle.secondary, expand: true, onPressed: _restart),
        const SizedBox(height: Space.m),
        PourButton(
          label: 'Tilt settings',
          style: PourButtonStyle.secondary,
          expand: true,
          onPressed: () => showTiltSettings(context),
        ),
        const SizedBox(height: Space.m),
        PourButton(
          label: 'Levels',
          style: PourButtonStyle.secondary,
          expand: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ]);

  Widget _wonCard(LevelRun run) {
    final hasNext = widget.index + 1 < widget.paths.length;
    return _card([
      Text('Level complete!', style: PourText.title),
      const SizedBox(height: Space.l),
      StarRow(stars: run.stars, size: 44),
      const SizedBox(height: Space.m),
      Text(
        'Purity ${(run.avgPurity * 100).round()}%  ·  Spill ${(run.spill * 100).round()}%',
        style: PourText.body.copyWith(color: PourColors.textMuted),
      ),
      const SizedBox(height: Space.xl),
      PourButton(
        label: hasNext ? 'Next' : 'Done',
        icon: hasNext ? Icons.arrow_forward_rounded : null,
        expand: true,
        onPressed: hasNext ? _next : () => Navigator.of(context).pop(),
      ),
      const SizedBox(height: Space.m),
      PourButton(label: 'Replay', style: PourButtonStyle.secondary, expand: true, onPressed: _restart),
      if (!kReleaseMode) TextButton(onPressed: _saveReplay, child: const Text('Save replay (dev)')),
    ]);
  }

  Widget _lostCard(LevelRun run) => _card([
        Text('Out of sand', style: PourText.title),
        const SizedBox(height: Space.m),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [for (final c in run.shortColors) Padding(padding: const EdgeInsets.all(4), child: SandGlyph(c))],
        ),
        const SizedBox(height: Space.m),
        Text('Not enough sand is left to fill the jars.',
            textAlign: TextAlign.center, style: PourText.body.copyWith(color: PourColors.textMuted)),
        const SizedBox(height: Space.xl),
        PourButton(label: 'Retry', icon: Icons.refresh_rounded, expand: true, onPressed: _restart),
        const SizedBox(height: Space.m),
        PourButton(
          label: 'Levels',
          style: PourButtonStyle.secondary,
          expand: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ]);
}

/// Fill lines on open jars, and a progress ring around each jar's glyph
/// (amber = filling, red = purity too low to cork).
class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.run, Listenable repaint, this.glyph) : super(repaint: repaint);
  final LevelRun run;
  final double glyph;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / levelW;
    final line = Paint()
      ..color = PourColors.glass.withValues(alpha: 0.8)
      ..strokeWidth = 1.5;
    for (final j in run.jars) {
      final r = j.def.r;
      if (!j.corked) {
        // Dashed fill line.
        final y = j.def.fillLineY * s;
        for (var x = r.x * s; x < (r.x + r.w) * s; x += 8) {
          canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, (r.x + r.w) * s), y), line);
        }
      }
      final center = Offset((r.x + r.w / 2) * s, (r.y + r.h + jarWall + jarLabelRows / 2) * s);
      final rect = Rect.fromCircle(center: center, radius: glyph / 2 + 4);
      canvas.drawArc(rect, 0, math.pi * 2, false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = PourColors.surfaceHigh);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * (j.corked ? 1 : j.fillProgress),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = j.corked || j.purityOk ? PourColors.accent : PourColors.danger,
      );
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => old.run != run || old.glyph != glyph;
}
