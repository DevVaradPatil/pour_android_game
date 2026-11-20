import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../sim/sand_sim.dart';
import '../sim/scenes.dart';
import 'palette.dart';
import 'tilt.dart';

/// Phase 1 toy: sand in a glass box, driven by tilt (or touch-tilt).
class SandScreen extends StatefulWidget {
  const SandScreen({super.key, this.accelStream});

  /// Injected in tests; defaults to the real accelerometer.
  final Stream<AccelerometerEvent>? accelStream;

  @override
  State<SandScreen> createState() => _SandScreenState();
}

class _SandScreenState extends State<SandScreen> with SingleTickerProviderStateMixin {
  static const double _tickSec = 1 / 60;
  static const bool _dev = !kReleaseMode;

  SandSim _sim = toyBox();
  // Decodes are async (~1 frame), so keep up to 2 in flight over a ring of buffers.
  final _pixels = List.generate(3, (_) => Uint32List(gridW * gridH));
  final _image = ValueNotifier<ui.Image?>(null);
  final _stats = ValueNotifier<String>('');
  final _fieldKey = GlobalKey();
  final _tilt = TiltMapper();
  final _filter = LowPass3();
  StreamSubscription<AccelerometerEvent>? _accelSub;
  late final Ticker _ticker;

  bool _hasSensor = false;
  double _rawRoll = 0;
  double? _touchDeg; // non-null while touch-tilting
  double _touchStartX = 0;
  bool _spawning = false;
  int _spawnColor = 0;
  int _substeps = 3;

  int _inFlight = 0, _seq = 0, _shownSeq = 0;
  bool _dirty = true; // grid changed since the last uploaded image
  Duration _last = Duration.zero;
  double _acc = 0;
  // Stats, reset every second.
  Duration _statsAt = Duration.zero;
  int _frames = 0, _vsyncs = 0, _simTicks = 0, _simUs = 0;
  final _sw = Stopwatch();

  double get _gravityDeg => _touchDeg ?? (_hasSensor ? _tilt.map(_rawRoll) : 0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    final stream = widget.accelStream ??
        accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval);
    _accelSub = stream.listen(_onAccel, onError: (Object _) {}); // no sensor → touch-tilt only
  }

  @override
  void dispose() {
    _ticker.dispose();
    _accelSub?.cancel();
    _image.value?.dispose();
    _image.dispose();
    _stats.dispose();
    super.dispose();
  }

  void _onAccel(AccelerometerEvent e) {
    _filter.add(e.x, e.y, e.z);
    _rawRoll = rollDegFromAccel(_filter.x, _filter.y, _filter.z);
    if (!_hasSensor) {
      _hasSensor = true;
      _tilt.recenter(_rawRoll); // auto-recenter: whatever pose the player holds = straight down
    }
  }

  void _onTick(Duration elapsed) {
    _acc += (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _vsyncs++;
    var n = 0;
    _sw
      ..reset()
      ..start();
    while (_acc >= _tickSec && n < 3) {
      _sim.setGravityDegrees(_gravityDeg);
      for (var s = 0; s < _substeps; s++) {
        _sim.step();
        if (_sim.moved > 0) _dirty = true;
      }
      _acc -= _tickSec;
      n++;
    }
    if (_acc > _tickSec) _acc = 0; // fell behind: drop time instead of spiralling
    _sw.stop();
    if (n > 0) {
      _simUs += _sw.elapsedMicroseconds;
      _simTicks += n;
    }
    if (_dirty) {
      _dirty = false;
      _render(); // only upload a new texture when something changed (re-sets _dirty if skipped)
    }
    if (_dev && elapsed - _statsAt >= const Duration(seconds: 1)) {
      final secs = (elapsed - _statsAt).inMicroseconds / 1e6;
      String rate(int n) => (n / secs).toStringAsFixed(0);
      _stats.value = 'fps ${rate(_frames)}  vsync ${rate(_vsyncs)}  ticks ${rate(_simTicks)}\n'
          'sim ${_simTicks == 0 ? '-' : (_simUs / _simTicks / 1000).toStringAsFixed(2)} ms/tick\n'
          'awake ${_sim.activeChunks}/${_sim.chunkCount}  grains ${_sim.grains}\n'
          'tilt ${_gravityDeg.toStringAsFixed(1)}°  ${_touchDeg != null ? 'touch' : (_hasSensor ? 'sensor' : 'no sensor')}';
      _statsAt = elapsed;
      _frames = _vsyncs = _simTicks = _simUs = 0;
    }
  }

  void _render() {
    if (_inFlight >= 2) {
      _dirty = true;
      return;
    }
    final seq = ++_seq;
    final buf = _pixels[seq % _pixels.length];
    renderPixels(_sim, buf);
    _inFlight++;
    ui.decodeImageFromPixels(buf.buffer.asUint8List(), gridW, gridH, ui.PixelFormat.rgba8888, (img) {
      _inFlight--;
      if (!mounted || seq < _shownSeq) return img.dispose();
      _shownSeq = seq;
      final old = _image.value;
      _image.value = img;
      old?.dispose();
      _frames++;
    });
  }

  // Lower third of the screen = touch-tilt zone; elsewhere (dev builds) = spawn sand.
  void _onPanStart(DragStartDetails d) {
    final h = MediaQuery.sizeOf(context).height;
    if (d.globalPosition.dy > h * 2 / 3) {
      _touchStartX = d.globalPosition.dx;
      _touchDeg = 0;
    } else if (_dev) {
      _spawning = true;
      _spawnColor = (_spawnColor + 1) % Cell.sandColors;
      _spawnAt(d.globalPosition);
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_touchDeg != null) {
      final w = MediaQuery.sizeOf(context).width;
      _touchDeg = ((d.globalPosition.dx - _touchStartX) / (w * 0.35) * TiltMapper.maxDeg)
          .clamp(-TiltMapper.maxDeg, TiltMapper.maxDeg);
    } else if (_spawning) {
      _spawnAt(d.globalPosition);
    }
  }

  void _onPanEnd([DragEndDetails? _]) {
    _touchDeg = null;
    _spawning = false;
  }

  void _spawnAt(Offset global) {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(global);
    final x = (local.dx / box.size.width * gridW).floor();
    final y = (local.dy / box.size.height * gridH).floor();
    _sim.spawnCircle(x, y, 5, Cell.firstSand + _spawnColor);
    _dirty = true;
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          Widget slider(String label, double value, double min, double max, int div, ValueChanged<double> set) =>
              ListTile(
                title: Text('$label: ${value.toStringAsFixed(1)}'),
                subtitle: Slider(
                  value: value,
                  min: min,
                  max: max,
                  divisions: div,
                  onChanged: (v) => setSheet(() => set(v)),
                ),
              );
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              slider('Sensitivity', _tilt.sensitivity, 0.5, 2.0, 15, (v) => _tilt.sensitivity = v),
              slider('Dead zone °', _tilt.deadZoneDeg, 0, 8, 16, (v) => _tilt.deadZoneDeg = v),
              SwitchListTile(
                title: const Text('Invert tilt'),
                value: _tilt.invert,
                onChanged: (v) => setSheet(() => _tilt.invert = v),
              ),
              if (_dev)
                slider('Sand speed (steps/tick)', _substeps.toDouble(), 1, 6, 5, (v) => _substeps = v.round()),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1410),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                    child: Row(
                      children: [
                        const Text('POUR', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 6)),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Recenter',
                          icon: const Icon(Icons.center_focus_strong),
                          onPressed: () => _tilt.recenter(_rawRoll),
                        ),
                        IconButton(
                          tooltip: 'Reset',
                          icon: const Icon(Icons.refresh),
                          onPressed: () {
                            _sim = toyBox(seed: _sim.seed + 1);
                            _dirty = true;
                          },
                        ),
                        IconButton(tooltip: 'Settings', icon: const Icon(Icons.tune), onPressed: _openSettings),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: AspectRatio(
                          aspectRatio: gridW / gridH,
                          child: CustomPaint(key: _fieldKey, painter: _GridPainter(_image)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_dev)
                Positioned(
                  left: 24,
                  top: 64,
                  child: ValueListenableBuilder<String>(
                    valueListenable: _stats,
                    builder: (_, s, _) => Text(s, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  ),
                ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: Text(
                  '← drag here to tilt →',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.white38),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.image) : super(repaint: image);
  final ValueListenable<ui.Image?> image;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF2A211B));
    final img = image.value;
    if (img == null) return;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.image != image;
}
