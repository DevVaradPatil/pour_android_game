// Level source for World 1. Each level = geometry built from helpers + the
// intended solution. Writes assets/levels/w1/NNN.json, plays the solution
// headlessly, writes NNN.replay.json with the real end tick and stars, and
// rewrites assets/levels/levels.json.
//   dart run tool/build_levels.dart            build all, print a report
//   dart run tool/build_levels.dart 5 12       build only levels 5 and 12
// Field is 240 x 420 cells. Physics notes for designing: PLAN.md Phase 3/4.
import 'dart:convert';
import 'dart:io';

import 'package:pour_sand_game/level/level.dart';
import 'package:pour_sand_game/level/level_run.dart';

// ---------------------------------------------------------------- helpers

typedef J = Map<String, Object?>;

J rect(int x, int y, int w, int h) => {'rect': [x, y, w, h]};
J line(int x0, int y0, int x1, int y1, [int t = 3]) => {'line': [x0, y0, x1, y1], 't': t};
J sand(String c, int x, int y, int w, int h) => {'color': c, 'rect': [x, y, w, h]};
J jar(String c, int x, int y, int w, int h, {double fill = 0.3, double purity = 0.8}) =>
    {'color': c, 'rect': [x, y, w, h], 'fill': fill, 'purity': purity};

/// Flat shelf from x0 to x1 at y, with optional walls (height h) at either end.
List<J> shelf(int x0, int x1, int y, {int? leftWall, int? rightWall}) => [
      rect(x0, y, x1 - x0, 3),
      if (leftWall != null) rect(x0 - 3, y - leftWall, 3, leftWall + 3),
      if (rightWall != null) rect(x1, y - rightWall, 3, rightWall + 3),
    ];

/// Box hopper (inside x..x+w, top y, floor at y+h) whose floor has an outlet
/// [ox, ox+ow) closed by a valve. Returns walls; add [valveAt] to "valves".
List<J> hopper(int x, int y, int w, int h) => [
      rect(x - 3, y, 3, h + 3),
      rect(x + w, y, 3, h + 3),
      rect(x, y + h, w, 3),
    ];
J valveAt(int ox, int y, int ow, {bool open = false}) => {'rect': [ox, y, ow, 3], 'open': open};

/// Funnel from a mouth (x0..x1 at yTop) down to a neck centered on cx with
/// half-width nh at yBottom.
List<J> funnel(int x0, int x1, int yTop, int cx, int nh, int yBottom) =>
    [line(x0, yTop, cx - nh - 2, yBottom), line(x1, yTop, cx + nh + 2, yBottom)];

/// Inverted V that splits a falling stream.
List<J> wedge(int cx, int y, int halfW, int h) => [line(cx, y, cx - halfW, y + h), line(cx, y, cx + halfW, y + h)];

/// Solution step helpers ([tick, kind, value]).
List<int> tilt(int t, double deg) => [t, 0, (deg * 2).round()];
List<int> valve(int t, int i) => [t, 1, i];
List<int> fan(int t, int i) => [t, 3, i];

class Lv {
  Lv(this.name, this.concept, this.data, this.solution, {this.hint, this.seed});
  final String name, concept;
  final String? hint;
  final int? seed;
  final J data; // walls, sand, jars, valves, filters, mixers, fans, frames, stars
  final List<List<int>> solution;
}

// ---------------------------------------------------------------- World 1

final levels = <Lv>[
  // 1 — tilt
  Lv('First Pour', 'Tilt and sand moves', hint: 'Tilt your phone to pour', {
    'walls': [rect(20, 60, 3, 93), line(21, 150, 150, 150)],
    'sand': [sand('blue', 23, 110, 77, 38)],
    'jars': [jar('blue', 157, 175, 80, 60)],
  }, [tilt(30, 46), tilt(90, 0)]),

  // 2 — aim: the jar's left wall rises into a baffle; a shallow pour hits it
  Lv('Aim High', 'Angle matters: a steeper tilt clears the wall', hint: 'Tilt further to clear the wall', {
    'walls': [...shelf(20, 112, 150, leftWall: 90), rect(150, 190, 2, 25)],
    'sand': [sand('blue', 20, 112, 50, 38)],
    'jars': [jar('blue', 152, 215, 80, 50, fill: 0.25)],
  }, [tilt(30, 47), tilt(160, 0)]),

  // 3 — two jars, one color: fill one, it corks, then tilt the other way
  Lv('Both Ways', 'Tilting back spills: a cork keeps a finished jar safe', hint: 'Finish one jar, then the other', {
    'walls': [...shelf(60, 180, 140), rect(119, 105, 3, 38)],
    'sand': [sand('blue', 82, 118, 37, 22), sand('blue', 122, 118, 37, 22)],
    'jars': [jar('blue', 4, 165, 58, 45, fill: 0.2), jar('blue', 178, 165, 58, 45, fill: 0.2)],
  }, [tilt(30, -42), tilt(150, 0), tilt(200, 42), tilt(330, 0)]),

  // 4 — two colors (from Phase 3)
  Lv('Two Colors', 'Purity: each jar wants its own color', hint: 'Each jar wants its own color', {
    'walls': [rect(20, 40, 3, 73), rect(20, 110, 110, 3), rect(217, 230, 3, 73), rect(110, 300, 110, 3)],
    'sand': [sand('blue', 23, 72, 58, 38), sand('yellow', 160, 262, 57, 38)],
    'jars': [jar('blue', 155, 145, 80, 50), jar('yellow', 5, 335, 80, 50)],
  }, [tilt(30, 38), tilt(90, -44), tilt(150, 0)]),

  // 5 — funnel: a wide mouth catches the pour, the neck aims it
  Lv('Funnel', 'A funnel turns a wide pour into a precise stream', hint: 'Pour into the funnel, then level out', {
    'walls': [...shelf(18, 105, 110, leftWall: 70), ...funnel(110, 220, 150, 155, 5, 215)],
    'sand': [sand('green', 18, 74, 46, 36)],
    'jars': [jar('green', 137, 235, 36, 50, fill: 0.45)],
  }, [tilt(30, 42), tilt(130, 0)]),

  // 6 — order: yellow pours at 40°, blue (behind a lip) only past 45° and its
  // stream crosses the yellow jar, so yellow must be finished first.
  Lv('First Things First', 'Order: the steep pour for blue would also fling yellow past its jar', {
    'walls': [...shelf(15, 95, 100, leftWall: 60, rightWall: 30), ...shelf(15, 90, 230, leftWall: 40)],
    'sand': [sand('blue', 15, 72, 80, 28), sand('yellow', 15, 198, 40, 32)],
    'jars': [jar('blue', 140, 115, 70, 45, fill: 0.18), jar('yellow', 146, 290, 30, 50, fill: 0.35)],
  }, [tilt(30, 40), tilt(150, 0), tilt(180, 52), tilt(450, 0)]),

  // 7 — valve (from Phase 3)
  Lv('Valve', 'Valves hold sand until you tap them', hint: 'Tap the valve to open it', {
    'walls': hopper(83, 60, 74, 89),
    'valves': [valveAt(110, 149, 20)],
    'sand': [sand('purple', 83, 95, 74, 54)],
    'jars': [jar('purple', 90, 250, 60, 60, fill: 0.45)],
  }, [valve(40, 0)]),

  // 8 — two valves: drain the lower (blue) hopper first, then the upper (yellow)
  // one through it; the corked blue jar then sheds yellow to the right.
  Lv('Two Valves', 'Planning: the order you open valves matters', {
    'walls': [...hopper(93, 40, 54, 68), ...hopper(80, 150, 80, 78)],
    'valves': [valveAt(110, 228, 20), valveAt(110, 108, 20)],
    'sand': [sand('blue', 80, 190, 80, 38), sand('yellow', 93, 70, 54, 38)],
    'jars': [jar('blue', 95, 268, 50, 40, fill: 0.5), jar('yellow', 165, 320, 70, 45, fill: 0.25)],
  }, [valve(30, 0), valve(170, 1), tilt(175, 30), tilt(400, 0)]),

  // 9 — pleasure: zigzag ramps carry the sand down on their own
  Lv('Zigzag', 'A breather: watch it flow', hint: 'Open the valve and enjoy', {
    'walls': [
      ...hopper(20, 20, 60, 60),
      line(30, 100, 150, 220),
      line(215, 210, 100, 325),
    ],
    'valves': [valveAt(40, 80, 20)],
    'sand': [sand('orange', 20, 40, 60, 40)],
    'jars': [jar('orange', 25, 345, 90, 45, fill: 0.35)],
  }, [valve(30, 0)]),

  // 10 — boss: hourglass. Blue drains first (bottom layer), corks the middle jar,
  // then yellow piles on the cork; tilt left then right to fill both yellow jars.
  Lv('Hourglass', 'Boss: valve, funnel, cork protection and aim together', {
    'walls': [...funnel(50, 190, 40, 120, 6, 150), rect(47, 0, 3, 41), rect(190, 0, 3, 41)],
    'valves': [valveAt(110, 150, 21)],
    'sand': [sand('yellow', 50, 5, 140, 20), sand('blue', 50, 25, 140, 15)],
    'jars': [
      jar('yellow', 29, 250, 62, 40, fill: 0.2),
      jar('blue', 95, 235, 50, 45, fill: 0.5, purity: 0.75),
      jar('yellow', 149, 250, 62, 40, fill: 0.2),
    ],
    'stars': {'purity': 0.9},
  }, [valve(30, 0), tilt(260, -38), tilt(380, 38), tilt(500, 0)]),

  // 11 — filter (from Phase 3)
  Lv('Filter', 'Filters sort for you', hint: 'Filters only let their own color through', {
    'walls': [...hopper(73, 30, 54, 89), rect(57, 160, 3, 42), rect(150, 200, 11, 2)],
    'valves': [valveAt(90, 119, 20)],
    'filters': [
      {'color': 'blue', 'rect': [60, 200, 90, 2]},
    ],
    'sand': [sand('blue', 73, 55, 27, 64), sand('yellow', 100, 55, 27, 64)],
    'jars': [jar('blue', 60, 260, 88, 50, fill: 0.3), jar('yellow', 166, 235, 68, 55, fill: 0.35, purity: 0.7)],
    'stars': {'purity': 0.9, 'spill': 0.25},
  }, [valve(40, 0), tilt(250, 38), tilt(400, 0)]),
  // 12 — filter fed through a shared ramp
  Lv('Shared Chute', 'Both colors use one channel; the filter sorts at the end', {
    'walls': [
      ...hopper(150, 20, 54, 70),
      line(205, 110, 115, 200),
      rect(37, 190, 3, 42),
      rect(135, 230, 11, 2),
    ],
    'valves': [valveAt(167, 90, 20)],
    'filters': [
      {'color': 'blue', 'rect': [40, 230, 95, 2]},
    ],
    'sand': [sand('blue', 150, 40, 27, 50), sand('yellow', 177, 40, 27, 50)],
    'jars': [jar('blue', 40, 280, 93, 45, fill: 0.25), jar('yellow', 160, 265, 70, 50, fill: 0.3, purity: 0.7)],
    'stars': {'purity': 0.9, 'spill': 0.25},
  }, [valve(30, 0), tilt(330, 38), tilt(480, 0)]),

  // 13 — three tiers, three colors; right pours blue and red, left pours yellow
  Lv('Three Tiers', 'Load management: three jars, three colors', {
    'walls': [
      rect(15, 20, 3, 63), rect(15, 80, 95, 3),
      rect(222, 140, 3, 63), rect(130, 200, 95, 3),
      rect(15, 270, 3, 63), rect(15, 330, 95, 3),
    ],
    'sand': [sand('blue', 18, 50, 52, 30), sand('yellow', 170, 170, 52, 30), sand('red', 18, 300, 52, 30)],
    'jars': [
      jar('blue', 125, 110, 80, 40),
      jar('yellow', 35, 230, 80, 40),
      jar('red', 125, 360, 80, 40),
    ],
  }, [tilt(30, 40), tilt(150, 0), tilt(180, -40), tilt(300, 0)]),

  // 14 — tight budget: steer a valve's stream into the jar with ~10% to spare
  Lv('Tight Budget', 'Spill matters: barely more sand than the jar needs', hint: 'Not much to spare', {
    'walls': [...shelf(135, 222, 110, rightWall: 70), ...funnel(20, 130, 150, 85, 5, 215)],
    'sand': [sand('red', 176, 74, 46, 36)],
    'jars': [jar('red', 60, 235, 50, 50, fill: 0.6)],
  }, [tilt(30, -42), tilt(130, 0)]),

  // 15 — splitter
  Lv('Splitter', 'A wedge splits one stream into two', {
    'walls': [...hopper(90, 30, 60, 80), ...wedge(120, 170, 30, 25)],
    'valves': [valveAt(110, 110, 20)],
    'sand': [sand('blue', 90, 50, 60, 60)],
    'jars': [jar('blue', 55, 260, 60, 45, fill: 0.4), jar('blue', 125, 260, 60, 45, fill: 0.4)],
  }, [valve(30, 0)]),

  // 16 — mixer: open both valves so blue and yellow meet in the mixer
  Lv('Mixer', 'No green sand anywhere, but a green jar', hint: 'Mix two colors to make a third', {
    'walls': [...hopper(60, 30, 50, 70), ...hopper(130, 30, 50, 70), ...funnel(55, 185, 120, 120, 10, 170)],
    'valves': [valveAt(75, 100, 20), valveAt(145, 100, 20)],
    'mixers': [
      {'rect': [95, 175, 50, 60]},
    ],
    'sand': [sand('blue', 60, 60, 50, 40), sand('yellow', 130, 60, 50, 40)],
    'jars': [jar('green', 90, 270, 60, 50, fill: 0.45)],
  }, [valve(30, 0), valve(30, 1)]),

  // 17 — mixer then filter: green from the mixer stays on the blue filter,
  // spare blue drops through to its own jar; tilt the green into its jar.
  Lv('Green and Blue', 'Combine tools: the mixer makes green, spare blue drops through a sloped filter', {
    'walls': [rect(77, 0, 3, 31), rect(160, 0, 3, 31), ...funnel(80, 160, 30, 120, 2, 90)],
    'valves': [valveAt(118, 89, 5)],
    'mixers': [
      {'rect': [108, 100, 24, 50]},
    ],
    // Sloped so sand keeps moving across it: green rolls off the end, blue drops through.
    'filters': [
      {'color': 'blue', 'line': [60, 160, 170, 270], 't': 1},
    ],
    // Fine stripes, two blue to one yellow, so both drain together.
    'sand': [for (var i = 0; i < 80; i++) sand(i % 3 == 2 ? 'yellow' : 'blue', 80 + i, 0, 1, 30)],
    'jars': [jar('blue', 60, 310, 95, 20, fill: 0.15), jar('green', 165, 290, 66, 50, fill: 0.35, purity: 0.65)],
    'stars': {'purity': 0.85, 'spill': 0.25},
  }, [valve(30, 0)]),
  // 18 — fan blows the stream across the gap
  Lv('Breeze', 'Fans push sand sideways: active control', hint: 'Tap the fan', {
    'walls': hopper(90, 20, 60, 60),
    'valves': [valveAt(110, 80, 20)],
    'fans': [
      {'rect': [0, 100, 240, 80], 'dir': 1, 'strength': 2},
    ],
    'sand': [sand('orange', 90, 40, 60, 40)],
    'jars': [jar('orange', 165, 280, 65, 50, fill: 0.35)],
  }, [fan(20, 0), valve(30, 0)]),

  // 19 — pleasure: a cascading machine
  Lv('Sand Machine', 'A breather: a big generous cascade', hint: 'Open the valve and enjoy', {
    'walls': [
      ...hopper(20, 15, 70, 55),
      line(30, 90, 140, 200),
      line(210, 195, 120, 285),
      ...wedge(112, 310, 30, 25),
    ],
    'valves': [valveAt(45, 70, 20)],
    'sand': [sand('green', 20, 30, 70, 40)],
    'jars': [jar('green', 60, 355, 56, 40, fill: 0.35), jar('green', 124, 355, 56, 40, fill: 0.35)],
  }, [valve(30, 0)]),

  // 20 — boss: Desert Sunset. Four color hoppers over pairs of painting slots;
  // there's more sand than the slots need, so close each valve once its pair is
  // done or the overflow spoils the neighbours.
  Lv('Desert Sunset', 'Boss: hoppers in reverse order; aim each color at its slots and close in time',
      hint: 'One color at a time: aim, fill, close', {
    'walls': [
      ...hopper(65, 20, 24, 60), ...hopper(93, 20, 24, 60),
      ...hopper(121, 20, 24, 60), ...hopper(149, 20, 24, 60),
      // Bay dividers: a finished pair's overflow can't spill into the next pair.
      rect(90, 278, 2, 22), rect(118, 278, 2, 22), rect(146, 278, 2, 22),
    ],
    'valves': [valveAt(75, 80, 4), valveAt(103, 80, 4), valveAt(131, 80, 4), valveAt(159, 80, 4)],
    'sand': [
      sand('yellow', 65, 40, 24, 40), sand('orange', 93, 40, 24, 40),
      sand('red', 121, 40, 24, 40), sand('purple', 149, 40, 24, 40),
    ],
    'frames': [
      {
        'x': 64, 'y': 300, 'slot': [12, 30], 'fill': 0.5, 'purity': 0.8,
        'colors': ['purple', 'purple', 'red', 'red', 'orange', 'orange', 'yellow', 'yellow'],
      },
    ],
  }, [
    tilt(25, -21), valve(30, 3), valve(92, 3),
    tilt(190, -7.3), valve(195, 2), valve(257, 2),
    tilt(355, 7.3), valve(360, 1), valve(422, 1),
    tilt(520, 19.5), valve(525, 0), valve(587, 0), tilt(700, 0),
  ]),

];

// ---------------------------------------------------------------- build

void main(List<String> args) {
  final only = args.map(int.parse).toSet();
  final index = <String>[];
  var failed = 0;
  for (final (i, lv) in levels.indexed) {
    final n = (i + 1).toString().padLeft(3, '0');
    final path = 'w1/$n';
    index.add(path);
    if (only.isNotEmpty && !only.contains(i + 1)) continue;
    final m = <String, Object?>{
      'id': 'w1_$n',
      'name': lv.name,
      'seed': lv.seed ?? i + 1,
      if (lv.hint != null) 'hint': lv.hint,
      'concept': lv.concept,
      ...lv.data,
    };
    File('assets/levels/$path.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(m)}\n');
    final level = Level.fromJson(jsonEncode(m));
    final problems = level.problems();
    final events = [...lv.solution]..sort((a, b) => a[0].compareTo(b[0]));
    final run = LevelRun.play(level, Replay(level.id, events, events.isEmpty ? 0 : events.last[0]), extraTicks: 1500);
    File('assets/levels/$path.replay.json')
        .writeAsStringSync('${Replay(level.id, events, run.tick, stars: run.stars).toJson()}\n');
    final ok = problems.isEmpty && run.status == RunStatus.won;
    if (!ok) failed++;
    stdout.writeln('${ok ? 'OK  ' : 'FAIL'} $n ${lv.name.padRight(20)} ${run.summary()}');
    for (final p in problems) {
      stdout.writeln('       - $p');
    }
  }
  File('assets/levels/levels.json').writeAsStringSync('${jsonEncode(index)}\n');
  stdout.writeln(failed == 0 ? 'all built levels OK' : '$failed level(s) need work');
}
