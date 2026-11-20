import 'package:flutter_test/flutter_test.dart';
import 'package:pour_sand_game/game/tilt.dart';

void main() {
  test('roll from accelerometer', () {
    expect(rollDegFromAccel(0, 9.81, 0), closeTo(0, 1e-9)); // upright
    expect(rollDegFromAccel(-4.905, 8.496, 0), closeTo(30, 0.1)); // right edge down
    expect(rollDegFromAccel(4.905, 8.496, 0), closeTo(-30, 0.1)); // left edge down
    expect(rollDegFromAccel(-4.905, 0, 8.496), closeTo(30, 0.1)); // lying flat, tilted right
  });

  test('dead zone, sensitivity, invert, clamp', () {
    final m = TiltMapper();
    expect(m.map(2.9), 0);
    expect(m.map(-2.9), 0);
    expect(m.map(13), closeTo(10, 1e-9));
    expect(m.map(-13), closeTo(-10, 1e-9));
    expect(m.map(200), TiltMapper.maxDeg);
    m.sensitivity = 2;
    expect(m.map(13), closeTo(20, 1e-9));
    m.invert = true;
    expect(m.map(13), closeTo(-20, 1e-9));
  });

  test('recenter makes the current pose neutral', () {
    final m = TiltMapper()..recenter(25);
    expect(m.map(25), 0);
    expect(m.map(38), closeTo(10, 1e-9));
  });

  test('low-pass starts at the first sample and converges', () {
    final f = LowPass3();
    f.add(1, 2, 3);
    expect([f.x, f.y, f.z], [1, 2, 3]);
    for (var i = 0; i < 100; i++) {
      f.add(0, 9.81, 0);
    }
    expect(f.y, closeTo(9.81, 1e-3));
  });
}
