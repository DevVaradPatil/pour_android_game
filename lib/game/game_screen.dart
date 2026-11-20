import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../level/level.dart';
import '../level/level_run.dart';
import '../meta/daily.dart';
import '../meta/economy.dart';
import '../meta/progress.dart';
import '../services/notifications.dart';
import '../ui/brand.dart';
import '../ui/components.dart';
import '../ui/tokens.dart';
import 'play_kit.dart';

/// Haptics, unless the player turned them off.
void haptic(Future<void> Function() feedback) {
  if (progress.settings.haptics) feedback();
}

/// Plays `paths[index]` (paths relative to assets/levels/, e.g. "w1/001").
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.paths,
    required this.index,
    this.accelStream,
    this.autoplay = false,
    this.daily,
  });

  final List<String> paths;
  final int index;
  final Stream<AccelerometerEvent>? accelStream;

  /// Dev: play the recorded solution instead of reading input, log the result
  /// (`AUTOPLAY ...` in logcat) and move on to the next level.
  final bool autoplay;

  /// Daily Jar number when this is the daily (scored, shared; no map stars).
  final int? daily;

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
  Reward? _reward; // what the last win paid
  DailyOutcome? _dailyOutcome;
  int _dailyScore = 0;
  int _parTicks = 0; // the solution's length, for the daily score
  Replay? _auto; // drives input while watching a solution
  int _autoEvent = 0;

  String get _path => widget.paths[widget.index];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _load();
  }

  Future<void> _load() async {
    final level = Level.fromJson(await rootBundle.loadString('assets/levels/$_path.json'));
    if (widget.autoplay) _auto = await _loadReplay();
    if (widget.daily != null) _parTicks = (await _loadReplay()).ticks;
    if (!mounted) return;
    _level = level;
    _restart();
  }

  Future<Replay> _loadReplay() async =>
      Replay.fromJson(await rootBundle.loadString('assets/levels/$_path.replay.json'));

  Future<void> _watchSolution() async {
    _auto = await _loadReplay();
    _restart();
  }

  void _restart() {
    // Restarting a level in progress counts as a retry: the win streak ends.
    if (_run?.status == RunStatus.playing && (_run?.tick ?? 0) > 60 && _auto == null && widget.daily == null) {
      progress.recordFail();
    }
    setState(() {
      _run = LevelRun(_level!);
      _shown = RunStatus.playing;
      _paused = false;
      _autoEvent = 0;
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
      final auto = _auto;
      if (auto == null) {
        run.setGravityDegrees(_tilt.angle);
      } else {
        // Same event application as LevelRun.play, so on-device results match level_check.
        while (_autoEvent < auto.events.length && auto.events[_autoEvent][0] <= run.tick) {
          final [_, kind, value] = auto.events[_autoEvent++];
          switch (kind) {
            case 0:
              run.setGravityDegrees(value / 2);
            case 1:
              run.toggleValve(value);
            case 2:
              run.setSlowMo(value == 1);
            case 3:
              run.toggleFan(value);
          }
        }
      }
      run.step();
      if (run.moved > 0) _renderer.dirty = true;
      if (run.tick % 6 == 0) _hud.value++;
    }
    _renderer.renderIfDirty(run.sim);
    if (run.status != _shown) {
      _shown = run.status;
      final daily = widget.daily;
      if (run.status == RunStatus.won && daily != null) {
        _dailyScore = dailyScore(purity: run.avgPurity, ticks: run.tick, parTicks: _parTicks);
        _dailyOutcome = progress.recordDaily(
          daily,
          score: _dailyScore,
          stars: run.stars,
          purity: run.avgPurity,
          ticks: run.tick,
          jars: [for (final j in run.jars) (j.def.color, j.purity)],
        );
        refreshReminder(); // today is done: move the reminder to tomorrow
        haptic(HapticFeedback.mediumImpact);
      } else if (run.status == RunStatus.won) {
        _reward = progress.recordWin(_path, run.stars, boss: (widget.index + 1) % 10 == 0);
        haptic(HapticFeedback.mediumImpact);
      } else if (run.status == RunStatus.outOfSand && daily == null) {
        progress.recordFail();
      }
      setState(() {});
      if (widget.autoplay) _autoplayNext(run);
    }
  }

  Future<void> _autoplayNext(LevelRun run) async {
    debugPrint('AUTOPLAY $_path ${run.summary()}');
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    if (widget.index + 1 < widget.paths.length) {
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => GameScreen(paths: widget.paths, index: widget.index + 1, autoplay: true),
      ));
    } else {
      debugPrint('AUTOPLAY done');
      Navigator.of(context).pop();
    }
  }

  void _toggleFan(int i) {
    _run?.toggleFan(i);
    haptic(HapticFeedback.selectionClick);
    setState(() {});
  }

  void _toggleValve(int i) {
    _run?.toggleValve(i);
    haptic(HapticFeedback.selectionClick);
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
                  Text(widget.daily != null ? 'DAILY JAR #${widget.daily}' : 'LEVEL ${widget.index + 1}',
                      style: PourText.label.copyWith(color: PourColors.textMuted)),
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
                  for (final j in run.jars) j.def.slot ? _slotGlyph(j, scale) : _jarLabel(j, scale, glyph),
                  for (final m in run.level.mixers) _mixerBadge(m, scale),
                  for (final (i, v) in run.level.valves.indexed) _valveButton(run, i, v, scale),
                  for (final (i, f) in run.level.fans.indexed) _fanButton(run, i, f, scale),
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

  /// Painting slots show their target glyph inside, above the fill line.
  Widget _slotGlyph(JarState j, double scale) {
    final r = j.def.r;
    final size = math.min(r.w * scale * 0.85, 18.0);
    return Positioned(
      left: (r.x + r.w / 2) * scale - size / 2,
      top: (r.y + (j.def.fillLineY - r.y) / 2) * scale - size / 2,
      child: ValueListenableBuilder<int>(
        valueListenable: _hud,
        builder: (_, _, _) => Opacity(opacity: j.corked ? 0 : 0.9, child: SandGlyph(j.def.color, size: size)),
      ),
    );
  }

  Widget _mixerBadge(MixerDef m, double scale) => Positioned(
        left: (m.r.x + m.r.w) * scale - 22,
        top: m.r.y * scale + 4,
        child: const Icon(Icons.cyclone_rounded, size: 18, color: PourColors.textMuted, semanticLabel: 'Mixer'),
      );

  Widget _fanButton(LevelRun run, int i, FanDef f, double scale) {
    const size = 40.0;
    final on = run.fanOn[i];
    // Sits on the upwind edge of its zone.
    final x = f.dir > 0 ? f.r.x * scale : (f.r.x + f.r.w) * scale - size;
    return Positioned(
      left: x.clamp(0, levelW * scale - size),
      top: (f.r.y + f.r.h / 2) * scale - size / 2,
      child: Semantics(
        button: true,
        label: on ? 'Turn fan off' : 'Turn fan on',
        excludeSemantics: true,
        child: Squish(
          onTap: run.status == RunStatus.playing ? () => _toggleFan(i) : null,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: on ? PourColors.accent : PourColors.surfaceHigh.withValues(alpha: 0.9),
              shape: BoxShape.circle,
              border: Border.all(color: PourColors.text, width: 2),
            ),
            child: Icon(Icons.air_rounded, size: 22, color: on ? PourColors.onAccent : PourColors.text),
          ),
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
        if (!kReleaseMode) TextButton(onPressed: _watchSolution, child: const Text('Watch solution (dev)')),
      ]);

  Future<void> _share() async {
    final text = progress.dailyShare(widget.daily!);
    if (text != null) await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _enableReminders() async {
    final granted = await notifications.requestPermission();
    progress.updateSettings((s) => s.reminders = granted);
    await refreshReminder();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(granted ? "We'll remind you when tomorrow's jar is ready" : 'Notifications are off for Pour'),
      ));
      setState(() {});
    }
  }

  Widget _dailyWonCard(LevelRun run) {
    final o = _dailyOutcome;
    return _card([
      Text('Daily Jar #${widget.daily}', style: PourText.title),
      const SizedBox(height: Space.l),
      StarRow(stars: run.stars, size: 44),
      const SizedBox(height: Space.m),
      Text('$_dailyScore', style: PourText.display.copyWith(fontSize: 40)),
      Text(o != null && !o.newBest ? 'points (best today is higher)' : 'points',
          style: PourText.caption.copyWith(color: PourColors.textMuted)),
      if (o != null) ...[
        const SizedBox(height: Space.m),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🔥 ${o.streak}-day streak', style: PourText.label.copyWith(color: PourColors.accent)),
            if (o.coins > 0) ...[
              const SizedBox(width: Space.m),
              const Icon(Icons.monetization_on_rounded, color: PourColors.coin, size: 20),
              Text(' +${o.coins}', style: PourText.number),
            ],
          ],
        ),
        if (o.usedFreeze)
          Text('A streak freeze covered yesterday', style: PourText.caption.copyWith(color: PourColors.textMuted)),
      ],
      const SizedBox(height: Space.xl),
      PourButton(label: 'Share', icon: Icons.ios_share_rounded, expand: true, onPressed: _share),
      const SizedBox(height: Space.m),
      PourButton(
        label: 'Done',
        style: PourButtonStyle.secondary,
        expand: true,
        onPressed: () => Navigator.of(context).pop(),
      ),
      if (!progress.settings.reminders)
        TextButton(onPressed: _enableReminders, child: const Text('Remind me when the next jar is ready')),
    ]);
  }

  Widget _wonCard(LevelRun run) {
    if (widget.daily != null) return _dailyWonCard(run);
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
      if (_reward case final r? when r.total > 0) ...[
        const SizedBox(height: Space.m),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.monetization_on_rounded, color: PourColors.coin),
            const SizedBox(width: Space.xs),
            Text('+${r.total}', style: PourText.number),
            if (r.streakBonus > 0) ...[
              const SizedBox(width: Space.m),
              Text('${r.streak} in a row!', style: PourText.label.copyWith(color: PourColors.accent)),
            ],
          ],
        ),
      ],
      if ((widget.index + 1) % 10 == 0) ...[
        const SizedBox(height: Space.s),
        Text('Album picture complete!', style: PourText.label.copyWith(color: PourColors.accent)),
      ],
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
    for (final m in run.level.mixers) {
      final rr = RRect.fromRectAndRadius(
          Rect.fromLTWH(m.r.x * s, m.r.y * s, m.r.w * s, m.r.h * s), const Radius.circular(6));
      canvas.drawRRect(rr, Paint()..color = PourColors.glass.withValues(alpha: 0.06));
      canvas.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = PourColors.glass.withValues(alpha: 0.35));
    }
    for (final (i, f) in run.level.fans.indexed) {
      if (!run.fanOn[i]) continue;
      // Wind streaks drifting downwind.
      final wind = Paint()
        ..color = PourColors.glass.withValues(alpha: 0.35)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      final phase = (run.tick * 2 * f.dir) % 24;
      for (var y = f.r.y + 6; y < f.r.y + f.r.h; y += 14) {
        for (var x = f.r.x + phase; x < f.r.x + f.r.w; x += 24) {
          canvas.drawLine(Offset(x * s, y * s), Offset((x + 8 * f.dir) * s, y * s), wind);
        }
      }
    }
    for (final j in run.jars) {
      final r = j.def.r;
      if (j.def.slot) {
        if (!j.corked) {
          canvas.drawRect(Rect.fromLTWH(r.x * s, r.y * s, r.w * s, r.h * s),
              Paint()..color = Color(0xFF000000 | j.def.color.rgb).withValues(alpha: 0.18));
          final y = j.def.fillLineY * s;
          canvas.drawLine(Offset(r.x * s, y), Offset((r.x + r.w) * s, y), line);
        }
        continue;
      }
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
