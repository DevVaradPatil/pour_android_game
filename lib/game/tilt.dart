// Phone pose → gravity angle for the sim. Pure Dart so it's unit-testable.
import 'dart:math' as math;

/// Roll in degrees from an accelerometer sample (m/s², Android/iOS device axes).
/// Positive = right edge down = sand flows toward +x. Works both held upright
/// (steering-wheel roll) and lying flat (tilting left/right), so playing in bed works.
double rollDegFromAccel(double ax, double ay, double az) =>
    math.atan2(-ax, math.sqrt(ay * ay + az * az)) * 180 / math.pi;

/// Maps raw roll to the sim's gravity angle. Real sensors drift and differ per
/// device, so every knob here is exposed in settings.
class TiltMapper {
  double sensitivity = 1.0;
  double deadZoneDeg = 3.0;
  bool invert = false;
  double neutralDeg = 0;
  static const double maxDeg = 70;

  /// Makes the current pose "straight down".
  void recenter(double rawDeg) => neutralDeg = rawDeg;

  double map(double rawDeg) {
    var a = rawDeg - neutralDeg;
    if (a.abs() <= deadZoneDeg) return 0;
    a -= a.sign * deadZoneDeg; // continuous at the dead-zone edge
    if (invert) a = -a;
    return (a * sensitivity).clamp(-maxDeg, maxDeg);
  }
}

/// Exponential low-pass filter for accelerometer axes (removes hand jitter
/// and linear shakes, keeps gravity). First sample initializes with no lag.
class LowPass3 {
  LowPass3([this.alpha = 0.2]);
  final double alpha;
  double x = 0, y = 0, z = 0;
  bool _init = false;
  bool get hasValue => _init;

  void add(double ax, double ay, double az) {
    if (!_init) {
      x = ax;
      y = ay;
      z = az;
      _init = true;
      return;
    }
    x += alpha * (ax - x);
    y += alpha * (ay - y);
    z += alpha * (az - z);
  }
}
