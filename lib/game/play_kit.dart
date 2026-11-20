// Pieces shared by the sandbox and the level screen: tilt input, the fixed-step
// clock, grid rendering, and the tilt settings sheet.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../meta/progress.dart';
import '../sim/sand_sim.dart';
import 'palette.dart';
import 'tilt.dart';

/// App-wide tilt mapper + neutral pose (one screen plays at a time). Its knobs
/// mirror the saved settings; call [applyTiltSettings] after they change.
final TiltMapper tiltMapper = TiltMapper();

void applyTiltSettings() {
  final s = progress.settings;
  tiltMapper
    ..sensitivity = s.sensitivity
    ..deadZoneDeg = s.deadZone
    ..invert = s.invert;
}

/// Accelerometer (or touch-tilt override) → gravity angle for the sim.
class TiltInput {
  TiltInput({Stream<AccelerometerEvent>? stream}) {
    _sub = (stream ?? accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval))
        .listen(_onAccel, onError: (Object _) {}); // no sensor → touch-tilt only
  }

  StreamSubscription<AccelerometerEvent>? _sub;
  final _filter = LowPass3();
  bool hasSensor = false;
  bool _recenterNext = true; // auto-recenter: the pose held at level start = straight down
  double rawRoll = 0;
  double? _touchDeg; // non-null while touch-tilting
  double _touchStartX = 0;

  double get angle => _touchDeg ?? (hasSensor && !progress.settings.touchOnly ? tiltMapper.map(rawRoll) : 0);
  bool get touching => _touchDeg != null;

  void _onAccel(AccelerometerEvent e) {
    _filter.add(e.x, e.y, e.z);
    rawRoll = rollDegFromAccel(_filter.x, _filter.y, _filter.z);
    hasSensor = true;
    if (_recenterNext) {
      _recenterNext = false;
      tiltMapper.recenter(rawRoll);
    }
  }

  void recenter() => hasSensor ? tiltMapper.recenter(rawRoll) : null;
  void recenterOnNextSample() => _recenterNext = true;

  void touchStart(double x) {
    _touchStartX = x;
    _touchDeg = 0;
  }

  void touchUpdate(double x, double screenWidth) => _touchDeg =
      ((x - _touchStartX) / (screenWidth * 0.35) * TiltMapper.maxDeg).clamp(-TiltMapper.maxDeg, TiltMapper.maxDeg);

  void touchEnd() => _touchDeg = null;

  void dispose() => _sub?.cancel();
}

/// Turns vsync timestamps into a whole number of fixed 60 Hz ticks.
class TickClock {
  static const double tickSec = 1 / 60;
  Duration _last = Duration.zero;
  double _acc = 0;

  int ticks(Duration elapsed) {
    _acc += (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    var n = 0;
    while (_acc >= tickSec && n < 3) {
      _acc -= tickSec;
      n++;
    }
    if (_acc > tickSec) _acc = 0; // fell behind: drop time instead of spiralling
    return n;
  }
}

/// Grid → ui.Image. Decodes are async (~1 frame), so up to 2 run in flight
/// over a ring of buffers, and nothing is uploaded while the grid is unchanged.
class GridRenderer {
  GridRenderer(this.width, this.height) : _pixels = List.generate(3, (_) => Uint32List(width * height));

  final int width, height;
  final List<Uint32List> _pixels;
  final image = ValueNotifier<ui.Image?>(null);
  bool dirty = true;
  int frames = 0; // images shown, for the fps overlay
  int _inFlight = 0, _seq = 0, _shownSeq = 0;
  bool _disposed = false;

  void renderIfDirty(SandSim sim) {
    if (!dirty || _inFlight >= 2) return;
    dirty = false;
    final seq = ++_seq;
    final buf = _pixels[seq % _pixels.length];
    renderPixels(sim, buf);
    _inFlight++;
    ui.decodeImageFromPixels(buf.buffer.asUint8List(), width, height, ui.PixelFormat.rgba8888, (img) {
      _inFlight--;
      if (_disposed || seq < _shownSeq) return img.dispose();
      _shownSeq = seq;
      final old = image.value;
      image.value = img;
      old?.dispose();
      frames++;
    });
  }

  void dispose() {
    _disposed = true;
    image.value?.dispose();
    image.dispose();
  }
}

class GridPainter extends CustomPainter {
  GridPainter(this.image, this.background) : super(repaint: image);
  final ValueListenable<ui.Image?> image;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = background);
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
  bool shouldRepaint(GridPainter old) => old.image != image;
}

/// Saved tilt settings as list tiles (used by the sheet and the settings screen).
List<Widget> tiltSettingTiles(StateSetter setState) {
  void set(void Function() change) => setState(() {
        progress.updateSettings((_) => change());
        applyTiltSettings();
      });
  final s = progress.settings;
  Widget slider(String label, double value, double min, double max, int div, ValueChanged<double> onChanged) => ListTile(
        title: Text('$label: ${value.toStringAsFixed(1)}'),
        subtitle: Slider(value: value, min: min, max: max, divisions: div, onChanged: onChanged),
      );
  return [
    slider('Sensitivity', s.sensitivity, 0.5, 2.0, 15, (v) => set(() => s.sensitivity = v)),
    slider('Dead zone °', s.deadZone, 0, 8, 16, (v) => set(() => s.deadZone = v)),
    SwitchListTile(title: const Text('Invert tilt'), value: s.invert, onChanged: (v) => set(() => s.invert = v)),
    SwitchListTile(
      title: const Text('Touch tilt only'),
      subtitle: const Text('Ignore the tilt sensor; drag the bottom of the screen'),
      value: s.touchOnly,
      onChanged: (v) => set(() => s.touchOnly = v),
    ),
  ];
}

/// Tilt settings sheet. [extra] adds screen-specific rows (e.g. dev sand speed).
Future<void> showTiltSettings(BuildContext context, {List<Widget> Function(StateSetter)? extra}) =>
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ...tiltSettingTiles(setSheet),
            ...?extra?.call(setSheet),
          ],
        ),
      ),
    );
