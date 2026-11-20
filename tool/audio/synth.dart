// Procedural sound effects + ambient loop → assets/audio/*.wav (mono, 16-bit,
// 22.05 kHz). Deterministic (seeded), so re-running gives identical files.
//   dart run tool/audio/synth.dart
// WAV, not OGG: iOS can't play Vorbis and AAC adds gaps to loops; all files
// together stay well under 2 MB.
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int sr = 22050;
final _rng = math.Random(7);
double _noise() => _rng.nextDouble() * 2 - 1;

Float64List buf(double sec) => Float64List((sec * sr).round());

/// Adds a voice: [f] gives the sample at time t (s) from the voice's start.
void add(Float64List out, double at, double dur, double Function(double t) f, {bool wrap = false}) {
  final start = (at * sr).round(), n = (dur * sr).round(), tail = math.min(n ~/ 4, sr ~/ 50);
  for (var i = 0; i < n; i++) {
    var j = start + i;
    if (wrap) {
      j %= out.length;
    } else if (j >= out.length) {
      break;
    }
    // Last 20 ms fade out, so a voice cut short never clicks.
    out[j] += f(i / sr) * (i >= n - tail ? (n - i) / tail : 1);
  }
}

double sine(double hz, double t) => math.sin(2 * math.pi * hz * t);

/// Exponential pitch sweep a→b over [dur]; returns the phase-correct sample.
double sweep(double a, double b, double dur, double t) {
  final k = math.log(b / a) / dur;
  final tt = math.min(t, dur);
  final phase = a * (math.exp(k * tt) - 1) / k + b * math.max(0, t - dur);
  return math.sin(2 * math.pi * phase);
}

/// One-pole low-pass in place. [wrap] runs it twice so a loop has no seam.
void lowpass(Float64List x, double hz, {bool wrap = false}) {
  final a = 1 - math.exp(-2 * math.pi * hz / sr);
  var y = 0.0;
  for (var pass = 0; pass < (wrap ? 2 : 1); pass++) {
    for (var i = 0; i < x.length; i++) {
      y += a * (x[i] - y);
      if (pass == (wrap ? 1 : 0)) x[i] = y;
    }
  }
}

void highpass(Float64List x, double hz, {bool wrap = false}) {
  final lp = Float64List.fromList(x);
  lowpass(lp, hz, wrap: wrap);
  for (var i = 0; i < x.length; i++) {
    x[i] -= lp[i];
  }
}

Float64List normalize(Float64List x, double peak) {
  final m = x.fold(0.0, (a, v) => math.max(a, v.abs()));
  if (m > 0) {
    for (var i = 0; i < x.length; i++) {
      x[i] *= peak / m;
    }
  }
  return x;
}

/// Short fade at both ends so one-shots never click.
Float64List fade(Float64List x, [double sec = 0.004]) {
  final n = (sec * sr).round();
  for (var i = 0; i < n && i < x.length; i++) {
    x[i] *= i / n;
    x[x.length - 1 - i] *= i / n;
  }
  return x;
}

/// Grainy hiss: tiny windowed noise bursts. [density] grains/s at time t.
void grains(Float64List out, double at, double dur, double Function(double t) density, {bool wrap = false}) {
  var t = 0.0;
  while (t < dur) {
    final d = density(t);
    t += d <= 0 ? 0.01 : -math.log(1 - _rng.nextDouble()) / d;
    if (t >= dur) break;
    final len = 0.0015 + _rng.nextDouble() * 0.003, amp = 0.2 + _rng.nextDouble() * 0.8;
    add(out, at + t, len, (u) => _noise() * amp * math.pow(math.sin(math.pi * u / len), 2), wrap: wrap);
  }
}

double bell(double f0, double t) {
  const ratios = [1.0, 2.76, 5.4, 8.93], amps = [1.0, 0.5, 0.25, 0.12], decays = [0.6, 0.3, 0.15, 0.08];
  var s = 0.0;
  for (var k = 0; k < 4; k++) {
    if (f0 * ratios[k] > sr * 0.45) break; // above Nyquist it would alias
    s += amps[k] * math.exp(-t / decays[k]) * sine(f0 * ratios[k], t);
  }
  return s * math.min(1, t / 0.002);
}

double marimba(double f0, double t) =>
    (sine(f0, t) + 0.3 * sine(f0 * 4, t) * math.exp(-t / 0.05)) * math.exp(-t / 0.35) * math.min(1, t / 0.003);

double hz(int midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

Map<String, Float64List> sounds() {
  final s = <String, Float64List>{};

  // Pouring sand: seamless 2 s loop; the game sets its volume (and pitch) from the flow.
  final sand = buf(2);
  grains(sand, 0, 2, (_) => 2600, wrap: true);
  highpass(sand, 1400, wrap: true);
  lowpass(sand, 7000, wrap: true);
  s['sand_loop'] = normalize(sand, 0.8);

  // Cork: low thunk, then a bright pop.
  final cork = buf(0.25);
  add(cork, 0, 0.25, (t) => sweep(140, 55, 0.12, t) * math.exp(-t / 0.04));
  add(cork, 0.012, 0.06, (t) => 0.7 * sweep(500, 1100, 0.025, t) * math.exp(-t / 0.012));
  add(cork, 0.012, 0.02, (t) => 0.25 * _noise() * math.exp(-t / 0.004));
  s['cork'] = fade(normalize(cork, 0.9));

  // Valve: two mechanical clicks and a faint metallic ring.
  final valve = buf(0.22);
  for (final at in [0.0, 0.045]) {
    add(valve, at, 0.006, (t) => _noise() * math.exp(-t / 0.0015));
  }
  highpass(valve, 900);
  add(valve, 0.045, 0.17, (t) => 0.12 * (sine(1800, t) + 0.6 * sine(2710, t) + 0.3 * sine(4130, t)) * math.exp(-t / 0.05));
  s['valve'] = fade(normalize(valve, 0.8));

  // Fan: a soft whoosh.
  final fan = buf(0.45);
  add(fan, 0, 0.45, (t) => _noise() * (t < 0.08 ? t / 0.08 : math.exp(-(t - 0.08) / 0.12)));
  lowpass(fan, 900);
  lowpass(fan, 1400);
  s['fan'] = fade(normalize(fan, 0.7));

  // UI tap: a small wooden tick.
  final tap = buf(0.04);
  add(tap, 0, 0.04, (t) => (sine(1400, t) + 0.4 * sine(2900, t)) * math.exp(-t / 0.006));
  s['tap'] = fade(normalize(tap, 0.5), 0.001);

  // Star chimes, one per star, rising C6–E6–G6.
  for (final (i, m) in [84, 88, 91].indexed) {
    final b = buf(1.0);
    add(b, 0, 1.0, (t) => bell(hz(m), t));
    s['star${i + 1}'] = fade(normalize(b, 0.6));
  }

  // Win jingle: C major arpeggio, then a bell on top.
  final win = buf(1.4);
  for (final (i, m) in [72, 76, 79, 84].indexed) {
    add(win, i * 0.09, 1.0, (t) => marimba(hz(m), t));
  }
  add(win, 0.36, 1.0, (t) => 0.5 * bell(hz(96), t));
  s['win'] = fade(normalize(win, 0.7));

  // Out of sand: two soft falling notes.
  final fail = buf(0.8);
  for (final (i, m) in [67, 64].indexed) {
    add(fail, i * 0.22, 0.55, (t) => sine(hz(m) * (1 + 0.004 * sine(5, t)), t) * math.exp(-t / 0.2) * math.min(1, t / 0.01));
  }
  s['fail'] = fade(normalize(fail, 0.5));

  // Album reveal: a trickle of sand with chimes climbing a pentatonic scale.
  final reveal = buf(1.3);
  grains(reveal, 0, 0.9, (t) => 1800 * (1 - t / 0.9));
  highpass(reveal, 1800);
  for (final x in reveal.indexed) {
    reveal[x.$1] = x.$2 * 0.35;
  }
  for (final (i, m) in [79, 81, 84, 86, 88].indexed) {
    add(reveal, 0.1 + i * 0.12, 0.9, (t) => 0.45 * bell(hz(m), t));
  }
  s['reveal'] = fade(normalize(reveal, 0.6));

  s['music_loop'] = music();
  return s;
}

/// Ambient pad: four chords, 6 s each, cross-faded circularly so the 24 s
/// loop has no seam; sparse bell notes on top.
Float64List music() {
  const slot = 6.0, chords = [
    [48, 55, 59, 64], // Cmaj7
    [45, 52, 55, 60], // Am7
    [41, 48, 52, 57], // Fmaj7
    [43, 50, 55, 59], // G (add 3rd/5th)
  ];
  final out = buf(slot * chords.length);
  for (final (c, notes) in chords.indexed) {
    const len = slot + 3; // 1.5 s overlap each side
    double env(double t) => math.pow(math.sin(math.pi * t / len), 2).toDouble();
    for (final m in notes) {
      final f = hz(m);
      add(out, c * slot - 1.5, len, (t) {
        // Three slightly detuned voices for a soft chorus.
        final v = sine(f, t) + sine(f * 1.0015, t + 0.3) + sine(f * 0.9985, t + 0.7);
        return v * env(t) * (m < 50 ? 0.5 : 0.3);
      }, wrap: true);
    }
    // Two sparse bell notes per chord from C-major pentatonic, fixed pattern.
    const tops = [76, 79, 81, 84, 86];
    for (final k in [0, 1]) {
      add(out, c * slot + 1.2 + k * 2.6, 2.5, (t) => 0.18 * bell(hz(tops[(c * 2 + k * 3) % tops.length]), t), wrap: true);
    }
  }
  return normalize(out, 0.5);
}

Uint8List wav(Float64List x) {
  final b = ByteData(44 + x.length * 2);
  void str(int o, String s) {
    for (final (i, c) in s.codeUnits.indexed) {
      b.setUint8(o + i, c);
    }
  }
  str(0, 'RIFF');
  b.setUint32(4, 36 + x.length * 2, Endian.little);
  str(8, 'WAVEfmt ');
  b
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, sr, Endian.little)
    ..setUint32(28, sr * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  str(36, 'data');
  b.setUint32(40, x.length * 2, Endian.little);
  for (var i = 0; i < x.length; i++) {
    b.setInt16(44 + i * 2, (x[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return b.buffer.asUint8List();
}

void main() {
  final dir = Directory('assets/audio')..createSync(recursive: true);
  var total = 0;
  for (final MapEntry(:key, :value) in sounds().entries) {
    final bytes = wav(value);
    File('${dir.path}/$key.wav').writeAsBytesSync(bytes);
    total += bytes.length;
    print('$key.wav  ${(value.length / sr).toStringAsFixed(2)} s  ${(bytes.length / 1024).round()} KB');
  }
  print('total ${(total / 1024).round()} KB');
}
