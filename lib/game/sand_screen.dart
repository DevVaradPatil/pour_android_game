import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../sim/sand_sim.dart';
import '../sim/scenes.dart';
import '../ui/tokens.dart';
import 'play_kit.dart';

/// Dev sandbox (the Phase 1 toy): free sand in a glass box, tilt it, drag to add sand.
class SandScreen extends StatefulWidget {
  const SandScreen({super.key, this.accelStream});

  /// Injected in tests; defaults to the real accelerometer.
  final Stream<AccelerometerEvent>? accelStream;

  @override
  State<SandScreen> createState() => _SandScreenState();
}

class _SandScreenState extends State<SandScreen> with SingleTickerProviderStateMixin {
  SandSim _sim = toyBox();
  final _renderer = GridRenderer(gridW, gridH);
  final _clock = TickClock();
  final _stats = ValueNotifier<String>('');
  final _fieldKey = GlobalKey();
  late final TiltInput _tilt = TiltInput(stream: widget.accelStream);
  late final Ticker _ticker;

  bool _spawning = false;
  int _spawnColor = 0;
  int _substeps = 3;

  // Stats, reset every second.
  Duration _statsAt = Duration.zero;
  int _vsyncs = 0, _simTicks = 0, _simUs = 0;
  final _sw = Stopwatch();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _tilt.dispose();
    _renderer.dispose();
    _stats.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    _vsyncs++;
    final n = _clock.ticks(elapsed);
    _sw
      ..reset()
      ..start();
    for (var i = 0; i < n; i++) {
      _sim.setGravityDegrees(_tilt.angle);
      for (var s = 0; s < _substeps; s++) {
        _sim.step();
        if (_sim.moved > 0) _renderer.dirty = true;
      }
    }
    _sw.stop();
    _simUs += _sw.elapsedMicroseconds;
    _simTicks += n;
    _renderer.renderIfDirty(_sim);
    if (!kReleaseMode && elapsed - _statsAt >= const Duration(seconds: 1)) {
      final secs = (elapsed - _statsAt).inMicroseconds / 1e6;
      String rate(int n) => (n / secs).toStringAsFixed(0);
      _stats.value = 'fps ${rate(_renderer.frames)}  vsync ${rate(_vsyncs)}  ticks ${rate(_simTicks)}\n'
          'sim ${_simTicks == 0 ? '-' : (_simUs / _simTicks / 1000).toStringAsFixed(2)} ms/tick\n'
          'awake ${_sim.activeChunks}/${_sim.chunkCount}  grains ${_sim.grains}\n'
          'tilt ${_tilt.angle.toStringAsFixed(1)}°  ${_tilt.touching ? 'touch' : (_tilt.hasSensor ? 'sensor' : 'no sensor')}';
      _statsAt = elapsed;
      _renderer.frames = _vsyncs = _simTicks = _simUs = 0;
    }
  }

  // Lower third of the screen = touch-tilt zone; elsewhere = spawn sand.
  void _onPanStart(DragStartDetails d) {
    if (d.globalPosition.dy > MediaQuery.sizeOf(context).height * 2 / 3) {
      _tilt.touchStart(d.globalPosition.dx);
    } else {
      _spawning = true;
      _spawnColor = (_spawnColor + 1) % Cell.sandColors;
      _spawnAt(d.globalPosition);
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_tilt.touching) {
      _tilt.touchUpdate(d.globalPosition.dx, MediaQuery.sizeOf(context).width);
    } else if (_spawning) {
      _spawnAt(d.globalPosition);
    }
  }

  void _onPanEnd([Object? _]) {
    _tilt.touchEnd();
    _spawning = false;
  }

  void _spawnAt(Offset global) {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(global);
    _sim.spawnCircle(
      (local.dx / box.size.width * gridW).floor(),
      (local.dy / box.size.height * gridH).floor(),
      5,
      Cell.firstSand + _spawnColor,
    );
    _renderer.dirty = true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onPanCancel: _onPanEnd,
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Row(
                    children: [
                      const BackButton(),
                      Text('Sandbox', style: PourText.heading),
                      const Spacer(),
                      IconButton(tooltip: 'Recenter', icon: const Icon(Icons.center_focus_strong), onPressed: _tilt.recenter),
                      IconButton(
                        tooltip: 'Reset',
                        icon: const Icon(Icons.refresh),
                        onPressed: () {
                          _sim = toyBox(seed: _sim.seed + 1);
                          _renderer.dirty = true;
                        },
                      ),
                      IconButton(
                        tooltip: 'Settings',
                        icon: const Icon(Icons.tune),
                        onPressed: () => showTiltSettings(
                          context,
                          extra: (setSheet) => [
                            ListTile(
                              title: Text('Sand speed (steps/tick): $_substeps'),
                              subtitle: Slider(
                                value: _substeps.toDouble(),
                                min: 1,
                                max: 6,
                                divisions: 5,
                                onChanged: (v) => setSheet(() => _substeps = v.round()),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(Space.m),
                        child: AspectRatio(
                          aspectRatio: gridW / gridH,
                          child: CustomPaint(key: _fieldKey, painter: GridPainter(_renderer.image, PourColors.surface)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (!kReleaseMode)
                Positioned(
                  left: 24,
                  top: 56,
                  child: ValueListenableBuilder<String>(
                    valueListenable: _stats,
                    builder: (_, s, _) => Text(s, style: PourText.caption.copyWith(fontSize: 11, color: PourColors.textMuted)),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: Space.m,
                child: Text('← drag here to tilt →',
                    textAlign: TextAlign.center, style: PourText.caption.copyWith(color: PourColors.outline)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
