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

/// Merges level fragments: list values are concatenated.
J merge(List<J> parts) {
  final out = <String, Object?>{};
  for (final p in parts) {
    p.forEach((k, v) => out[k] = v is List ? [...((out[k] as List?) ?? const []), ...v] : v);
  }
  return out;
}

/// Compact shelf + jar (about 118 rows tall from [y]). The shelf holds below ~35°
/// and pours toward the jar above it; [right] = pours right (mirrored otherwise).
/// Pour with tilt(±44) for ~2 s.
J tier(int y, String color, {bool right = true, double fill = 0.3, double purity = 0.8, int sandW = 40}) {
  int mx(int x, int w) => right ? x : levelW - x - w;
  return {
    'walls': [rect(mx(20, 3), y, 3, 45), rect(mx(20, 80), y + 42, 80, 3)],
    'sand': [sand(color, mx(23, sandW), y + 18, sandW, 24)],
    'jars': [jar(color, mx(120, 70), y + 70, 70, 32, fill: fill, purity: purity)],
  };
}

/// Compact hopper + valve + jar below (about 126 rows tall from [y]).
/// Valve index = position in the level's valve list.
J drop(int x, int y, String color, {double fill = 0.4, double purity = 0.8, int sandH = 30}) => {
      'walls': hopper(x, y, 40, 40),
      'valves': [valveAt(x + 10, y + 40, 20)],
      'sand': [sand(color, x, y + 40 - sandH, 40, sandH)],
      'jars': [jar(color, x - 5, y + 75, 50, 35, fill: fill, purity: purity)],
    };

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
  }, [tilt(30, -42), tilt(90, 0), tilt(120, 42), tilt(180, 0)]),

  // 4 — two colors (from Phase 3)
  Lv('Two Colors', 'Purity: each jar wants its own color', hint: 'Each jar wants its own color', {
    'walls': [rect(20, 40, 3, 73), rect(20, 110, 110, 3), rect(217, 230, 3, 73), rect(110, 300, 110, 3)],
    'sand': [sand('blue', 23, 72, 58, 38), sand('yellow', 160, 262, 57, 38)],
    'jars': [jar('blue', 155, 145, 80, 50), jar('yellow', 5, 335, 80, 50)],
  }, [tilt(30, 42), tilt(90, -44), tilt(150, 0)]),

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
    'stars': {'purity': 0.9},
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
    'jars': [jar('blue', 60, 260, 88, 50, fill: 0.3), jar('yellow', 166, 235, 68, 55, fill: 0.28, purity: 0.7)],
    'stars': {'purity': 0.9, 'spill': 0.25},
  }, [valve(40, 0), tilt(250, 39), tilt(400, 0)]),
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
  }, [tilt(30, 40), tilt(90, 0), tilt(120, -40), tilt(180, 0)]),

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
    'walls': [...hopper(60, 30, 50, 70), ...hopper(130, 30, 50, 70), ...funnel(55, 185, 120, 120, 4, 170)],
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
  Lv('Desert Sunset', 'Boss: paint the sunset with valves, then pour both shelves. Tilting early throws the streams onto the wrong colors',
      hint: 'Paint first, then pour', merge([
    {
      'walls': [
        ...hopper(60, 10, 24, 60), ...hopper(92, 10, 24, 60),
        ...hopper(124, 10, 24, 60), ...hopper(156, 10, 24, 60),
        // A small splitter over each pair so one stream fills both slots.
        for (final cx in [72, 104, 136, 168]) ...wedge(cx, 141, 9, 7),
      ],
      'valves': [valveAt(70, 70, 5), valveAt(102, 70, 5), valveAt(134, 70, 5), valveAt(166, 70, 5)],
      'sand': [
        sand('purple', 60, 48, 24, 22), sand('red', 92, 48, 24, 22),
        sand('orange', 124, 48, 24, 22), sand('yellow', 156, 48, 24, 22),
      ],
      'frames': [
        {
          'x': 57, 'y': 150, 'slot': [14, 30], 'fill': 0.45, 'purity': 0.8,
          'colors': ['purple', 'purple', 'red', 'red', 'orange', 'orange', 'yellow', 'yellow'],
        },
      ],
    },
    tier(195, 'blue'),
    tier(300, 'green', right: false),
  ]), [
    valve(30, 0), valve(30, 1), valve(30, 2), valve(30, 3),
    tilt(250, 44), tilt(310, 0), tilt(340, -44), tilt(400, 0),
  ]),
];

// ---------------------------------------------------------------- remixes

/// Mirrors geometry left↔right (tilts in the solution flip too).
Object? _mirror(Object? v, String key) {
  if (v is List) return [for (final e in v) _mirror(e, key)];
  if (v is! Map) return v;
  final m = Map<String, Object?>.from(v);
  if (m['rect'] case final List r) m['rect'] = [levelW - (r[0] as int) - (r[2] as int), r[1], r[2], r[3]];
  if (m['line'] case final List l) m['line'] = [levelW - (l[0] as int), l[1], levelW - (l[2] as int), l[3]];
  if (m['circle'] case final List c) m['circle'] = [levelW - (c[0] as int), c[1], c[2]];
  if (key == 'fans') m['dir'] = -((m['dir'] as int?) ?? 1);
  if (key == 'frames') {
    final colors = (m['colors'] as List).cast<String>();
    final w = (m['slot'] as List)[0] as int;
    m['x'] = levelW - ((m['x'] as int) + colors.length * w + (colors.length - 1) * jarWall);
    m['colors'] = colors.reversed.toList();
  }
  return m;
}

/// Recolors everything that names a color.
Object? _recolor(Object? v, Map<String, String> map) {
  if (v is List) return [for (final e in v) _recolor(e, map)];
  if (v is String) return map[v] ?? v;
  if (v is! Map) return v;
  return <String, Object?>{for (final e in v.entries) e.key as String: _recolor(e.value, map)};
}

/// A remix of an earlier level: new name, colors, mirror, and tighter numbers.
Lv remix(
  int n,
  String name,
  String concept, {
  Map<String, String> colors = const {},
  bool mirror = false,
  double fillScale = 1,
  double? purity,
  String? hint,
}) {
  final base = levels[n - 1];
  var data = <String, Object?>{for (final e in base.data.entries) e.key: e.value};
  if (mirror) data = {for (final e in data.entries) e.key: _mirror(e.value, e.key)};
  data = _recolor(data, colors) as Map<String, Object?>;
  data['jars'] = [
    for (final j in (data['jars'] as List?) ?? const [])
      {
        ...Map<String, Object?>.from(j as Map),
        'fill': (((j['fill'] as num?) ?? 0.6) * fillScale).clamp(0.11, 0.85),
        'purity': ?purity,
      },
  ];
  final solution = [
    for (final e in base.solution) e[1] == 0 && mirror ? [e[0], 0, -e[2]] : e,
  ];
  return Lv(name, concept, data, solution, hint: hint);
}

// ---------------------------------------------------------------- World 1, 21–60

List<Lv> moreLevels() => [
      // 21–29 ramp, 29 = breather, 30 = boss
      Lv('Double Shelf', 'Two shelves pour the same way at once',
          merge([tier(20, 'blue'), tier(220, 'yellow')]), [tilt(30, 44), tilt(90, 0)]),
      Lv('Opposites', 'Tilt one way for two jars, the other way for the third',
          merge([tier(10, 'blue'), tier(140, 'yellow', right: false), tier(270, 'red')]),
          [tilt(30, 44), tilt(90, 0), tilt(120, -44), tilt(180, 0)]),
      Lv('Valve Row', 'Three valves, then a pour',
          merge([drop(25, 20, 'blue'), drop(100, 20, 'yellow'), drop(175, 20, 'red'), tier(200, 'green')]),
          [valve(30, 0), valve(30, 1), valve(30, 2), tilt(250, 44), tilt(310, 0)]),
      Lv('Wait For It', 'Let the valve finish before you tilt',
          merge([drop(100, 20, 'orange'), tier(190, 'purple', right: false)]),
          [valve(30, 0), tilt(220, -44), tilt(280, 0)]),
      remix(11, 'Sieve', 'Filters again, new colors',
          colors: {'blue': 'purple', 'yellow': 'green'}),
      remix(15, 'Even Split', 'A splitter with a stricter purity', colors: {'blue': 'red'}, purity: 0.9),
      remix(16, 'Sunrise Mix', 'Red and yellow make orange',
          colors: {'blue': 'red', 'green': 'orange'}),
      remix(18, 'Headwind', 'The fan blows the other way', colors: {'orange': 'purple'}, mirror: true),
      remix(19, 'Cascade', 'A breather: the machine runs itself', colors: {'green': 'orange'}, mirror: true,
          hint: 'Open the valve and enjoy'),
      remix(20, 'Twilight', 'Boss: paint the evening sky',
          colors: {'purple': 'blue', 'red': 'purple', 'orange': 'red', 'yellow': 'orange'}),

      // 31–39
      Lv('Three Ways', 'Alternate tilts, stricter purity',
          merge([
            tier(10, 'blue', purity: 0.9),
            tier(140, 'yellow', right: false, purity: 0.9),
            tier(270, 'green', purity: 0.9),
          ]),
          [tilt(30, 44), tilt(90, 0), tilt(120, -44), tilt(180, 0)]),
      Lv('Drop and Pour', 'Valves first, then the shelf',
          merge([drop(30, 20, 'red'), drop(170, 20, 'blue'), tier(190, 'green', right: false)]),
          [valve(30, 0), valve(30, 1), tilt(230, -44), tilt(290, 0)]),
      remix(14, 'Narrow Margin', 'Tight budget from the other side', mirror: true, colors: {'red': 'yellow'}),
      remix(12, 'Red Chute', 'One chute, two colors, a red filter',
          colors: {'blue': 'red', 'yellow': 'orange'}),
      remix(16, 'Royal Mix', 'Red and blue make purple',
          colors: {'yellow': 'red', 'green': 'purple'}, purity: 0.85),
      remix(6, 'Lip Service', 'Order: the gentle pour first', colors: {'blue': 'red', 'yellow': 'green'}),
      remix(10, 'Hourglass II', 'The hourglass, in fire colors',
          colors: {'yellow': 'orange', 'blue': 'red'}),
      Lv('Valve Trio', 'Three valves, two shelves',
          merge([
            drop(25, 10, 'purple'),
            drop(100, 10, 'green'),
            drop(175, 10, 'orange'),
            tier(150, 'red'),
            tier(280, 'blue', right: false),
          ]),
          [valve(30, 0), valve(30, 1), valve(30, 2), tilt(230, 44), tilt(290, 0), tilt(320, -44), tilt(380, 0)]),
      remix(9, 'Zigzag II', 'A breather', colors: {'orange': 'green'}, mirror: true,
          hint: 'Open the valve and enjoy'),
      remix(20, 'Ember', 'Boss: a sky on fire',
          colors: {'purple': 'red', 'red': 'orange', 'orange': 'yellow', 'yellow': 'white'}),

      // 41–49
      remix(8, 'Stacked', 'Two valves in a stack, new colors', colors: {'blue': 'purple', 'yellow': 'orange'}),
      Lv('Crossing', 'Shelves both ways around a valve',
          merge([tier(10, 'red'), drop(100, 140, 'yellow'), tier(280, 'blue', right: false)]),
          [tilt(30, 44), tilt(90, 0), valve(110, 0), tilt(270, -44), tilt(330, 0)]),
      Lv('Tight Tiers', 'Three shelves, little to spare',
          merge([
            tier(10, 'blue', fill: 0.36),
            tier(140, 'blue', right: false, fill: 0.36),
            tier(270, 'blue', fill: 0.36),
          ]),
          [tilt(30, 44), tilt(90, 0), tilt(120, -44), tilt(180, 0)]),
      remix(12, 'Chute Again', 'Shared chute, stricter jars', mirror: true, fillScale: 1.05),
      remix(17, 'Sunset Mix', 'Mixer then filter: orange and red from one source',
          colors: {'blue': 'red', 'yellow': 'yellow', 'green': 'orange'}),
      remix(15, 'Fair Shares', 'Split evenly, fill higher', colors: {'blue': 'green'}, fillScale: 1.2),
      remix(14, 'Precise', 'Even tighter budget', colors: {'red': 'blue'}, fillScale: 1.02),
      Lv('Busy Valves', 'Six valves, six colors',
          merge([
            drop(25, 10, 'blue'), drop(100, 10, 'yellow'), drop(175, 10, 'red'),
            drop(25, 150, 'green'), drop(100, 150, 'purple'), drop(175, 150, 'orange'),
          ]),
          [for (var i = 0; i < 6; i++) valve(30, i)]),
      remix(19, 'Machine II', 'A breather', colors: {'green': 'purple'}, hint: 'Open the valve and enjoy'),
      remix(20, 'Rainbow', 'Boss: four colors, four aims',
          colors: {'purple': 'blue', 'red': 'green', 'orange': 'yellow', 'yellow': 'red'}),

      // 51–59, 60 boss
      Lv('Five Jars', 'Valves, then both directions',
          merge([
            drop(25, 10, 'blue'),
            drop(100, 10, 'yellow'),
            drop(175, 10, 'red'),
            tier(150, 'green'),
            tier(280, 'purple', right: false),
          ]),
          [valve(30, 0), valve(30, 1), valve(30, 2), tilt(230, 44), tilt(290, 0), tilt(320, -44), tilt(380, 0)]),
      remix(6, 'Order II', 'Mirrored order puzzle', mirror: true, colors: {'blue': 'purple', 'yellow': 'orange'}),
      remix(10, 'Hourglass III', 'Hourglass with a pure middle', colors: {'yellow': 'green', 'blue': 'purple'},
          purity: 0.8),
      remix(11, 'Strict Filter', 'Filter, stricter purity', colors: {'blue': 'red', 'yellow': 'blue'},
          purity: 0.8),
      remix(18, 'Gale', 'Fan, new colors', colors: {'orange': 'green'}, fillScale: 1.15),
      Lv('Triple Tight', 'Alternate tilts, strict purity, little spare',
          merge([
            tier(10, 'red', fill: 0.36, purity: 0.9),
            tier(140, 'orange', right: false, fill: 0.36, purity: 0.9),
            tier(270, 'yellow', fill: 0.36, purity: 0.9),
          ]),
          [tilt(30, 44), tilt(90, 0), tilt(120, -44), tilt(180, 0)]),
      remix(15, 'Twin Split', 'Strict split', colors: {'blue': 'purple'}, purity: 0.9, fillScale: 1.2),
      remix(16, 'Deep Green', 'Mixer, higher fill', fillScale: 1.3),
      remix(9, 'Grand Zigzag', 'A breather before the last boss', colors: {'orange': 'blue'},
          hint: 'Open the valve and enjoy'),
      remix(20, 'Desert Night', 'Final boss: night falls over the desert',
          colors: {'purple': 'blue', 'red': 'purple', 'orange': 'white', 'yellow': 'yellow'}),
    ];

// ---------------------------------------------------------------- build

void main(List<String> args) {
  final only = args.map(int.parse).toSet();
  final index = <String>[];
  var failed = 0;
  final all = [...levels, ...moreLevels()];
  for (final (i, lv) in all.indexed) {
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
