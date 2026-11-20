// Level definition, loaded from JSON. Pure Dart (used by the app and tool/level_check.dart).
//
// Levels are shape lists rather than PNGs: easy to generate, diff and validate.
// ponytail: add a PNG importer if a human designer wants to paint levels.
//
// {
//   "id": "w1_001", "name": "First Pour", "seed": 1, "hint": "Tilt your phone",
//   "walls":   [{"rect": [x, y, w, h]}, {"line": [x0, y0, x1, y1], "t": 3}],
//   "sand":    [{"color": "blue", "rect": [x, y, w, h]}, {"color": "yellow", "circle": [cx, cy, r]}],
//   "jars":    [{"color": "blue", "rect": [x, y, w, h], "fill": 0.5, "purity": 0.8}],   // rect = inside
//   "valves":  [{"rect": [x, y, w, h], "open": false}],
//   "filters": [{"color": "blue", "rect": [x, y, w, 2]}],
//   "mixers":  [{"rect": [x, y, w, h]}],                  // red+yellow→orange, blue+yellow→green, red+blue→purple
//   "fans":    [{"rect": [x, y, w, h], "dir": 1, "on": false, "strength": 2}],   // tap to toggle
//   "frames":  [{"x": 60, "y": 300, "slot": [8, 12], "fill": 0.6, "purity": 0.8,
//                "colors": ["red", "orange", "yellow"]}],  // a row of painting slots (boss levels)
//   "stars":   {"purity": 0.95, "spill": 0.10},
//   "concept": "what this level teaches"                    // for notes, not shown in game
// }
import 'dart:convert';
import 'dart:math' as math;

import '../game/palette.dart';
import '../sim/sand_sim.dart';

const int levelW = 240, levelH = 420;

/// Jar glass thickness, drawn around the left, right and bottom of the jar's inside.
const int jarWall = 2;

/// Rows under a jar reserved for its color glyph.
const int jarLabelRows = 14;

typedef IRect = ({int x, int y, int w, int h});

IRect _rect(Object? v) {
  final l = (v as List).cast<num>();
  return (x: l[0].toInt(), y: l[1].toInt(), w: l[2].toInt(), h: l[3].toInt());
}

/// A wall, sand or filter shape.
sealed class Shape {
  static Shape parse(Map<String, dynamic> m) {
    if (m['rect'] != null) return RectShape(_rect(m['rect']));
    if (m['line'] != null) {
      final l = (m['line'] as List).cast<num>().map((n) => n.toInt()).toList();
      return LineShape(l[0], l[1], l[2], l[3], (m['t'] as num?)?.toInt() ?? 3);
    }
    if (m['circle'] != null) {
      final l = (m['circle'] as List).cast<num>().map((n) => n.toInt()).toList();
      return CircleShape(l[0], l[1], l[2]);
    }
    throw FormatException('unknown shape $m');
  }

  /// Draws the shape. With [onlyEmpty], existing walls etc. are kept (used for sand).
  void paint(SandSim sim, int type, {bool onlyEmpty = false});

  /// Bounding box, for validation.
  IRect get bounds;
}

class RectShape extends Shape {
  RectShape(this.r);
  final IRect r;

  @override
  void paint(SandSim sim, int type, {bool onlyEmpty = false}) {
    for (var y = r.y; y < r.y + r.h; y++) {
      for (var x = r.x; x < r.x + r.w; x++) {
        if (x < 0 || y < 0 || x >= sim.width || y >= sim.height) continue;
        if (!onlyEmpty || sim.get(x, y) == Cell.empty) sim.set(x, y, type);
      }
    }
  }

  @override
  IRect get bounds => r;
}

class LineShape extends Shape {
  LineShape(this.x0, this.y0, this.x1, this.y1, this.t);
  final int x0, y0, x1, y1, t;

  @override
  void paint(SandSim sim, int type, {bool onlyEmpty = false}) => sim.line(x0, y0, x1, y1, type, thickness: t);

  @override
  IRect get bounds => (
        x: math.min(x0, x1) - t ~/ 2,
        y: math.min(y0, y1) - t ~/ 2,
        w: (x1 - x0).abs() + t,
        h: (y1 - y0).abs() + t,
      );
}

class CircleShape extends Shape {
  CircleShape(this.cx, this.cy, this.r);
  final int cx, cy, r;

  @override
  void paint(SandSim sim, int type, {bool onlyEmpty = false}) {
    for (var y = cy - r; y <= cy + r; y++) {
      for (var x = cx - r; x <= cx + r; x++) {
        if (x < 0 || y < 0 || x >= sim.width || y >= sim.height) continue;
        if ((x - cx) * (x - cx) + (y - cy) * (y - cy) > r * r) continue;
        if (!onlyEmpty || sim.get(x, y) == Cell.empty) sim.set(x, y, type);
      }
    }
  }

  @override
  IRect get bounds => (x: cx - r, y: cy - r, w: 2 * r + 1, h: 2 * r + 1);
}

class ColoredShape {
  ColoredShape(this.color, this.shape);
  final SandColor color;
  final Shape shape;
}

class JarDef {
  JarDef(this.color, this.r, this.fill, this.purity, {this.slot = false});
  final SandColor color;
  final IRect r; // inside of the jar
  final double fill; // fraction of the inside that must be filled
  final double purity; // min share of [color] needed to cork

  /// A painting-frame slot: no label row under it; its target color is shown inside.
  final bool slot;

  /// Grains needed to reach the fill line.
  int get target => (r.w * r.h * fill).round();

  /// Grains of [color] needed at minimum (fill × purity).
  int get needed => (target * purity).ceil();

  /// Row of the fill line (grid y).
  double get fillLineY => r.y + r.h * (1 - fill);
}

class ValveDef {
  ValveDef(this.r, this.open);
  final IRect r;
  final bool open;
}

/// Turns touching pairs of different primaries inside its rect into the secondary.
class MixerDef {
  MixerDef(this.r);
  final IRect r;
}

/// Pushes grains in its rect sideways while on (tap to toggle).
class FanDef {
  FanDef(this.r, this.dir, this.on, this.strength);
  final IRect r;
  final int dir; // +1 right, -1 left
  final bool on;
  final int strength; // cells pushed per tick
}

const _primaries = {SandColor.red, SandColor.yellow, SandColor.blue};

/// Result of mixing two different primaries, or null.
SandColor? mixOf(SandColor a, SandColor b) {
  if (a == b || !_primaries.contains(a) || !_primaries.contains(b)) return null;
  final pair = {a, b};
  if (!pair.contains(SandColor.red)) return SandColor.green;
  if (!pair.contains(SandColor.blue)) return SandColor.orange;
  return SandColor.purple;
}

/// The two primaries that make [c], or null if [c] isn't a secondary.
(SandColor, SandColor)? ingredientsOf(SandColor c) => switch (c) {
      SandColor.green => (SandColor.blue, SandColor.yellow),
      SandColor.orange => (SandColor.red, SandColor.yellow),
      SandColor.purple => (SandColor.red, SandColor.blue),
      _ => null,
    };

class Level {
  Level({
    required this.id,
    required this.name,
    required this.seed,
    this.hint,
    required this.walls,
    required this.sand,
    required this.jars,
    required this.valves,
    required this.filters,
    this.mixers = const [],
    this.fans = const [],
    this.starPurity = 0.95,
    this.starSpill = 0.10,
    this.concept,
  });

  factory Level.fromJson(String src) {
    final m = jsonDecode(src) as Map<String, dynamic>;
    List<Map<String, dynamic>> list(String k) => ((m[k] as List?) ?? const []).cast<Map<String, dynamic>>();
    SandColor color(Map<String, dynamic> e) => SandColor.values.byName(e['color'] as String);
    final stars = (m['stars'] as Map<String, dynamic>?) ?? const {};
    return Level(
      id: m['id'] as String,
      name: m['name'] as String,
      seed: (m['seed'] as num?)?.toInt() ?? 1,
      hint: m['hint'] as String?,
      walls: list('walls').map(Shape.parse).toList(),
      sand: list('sand').map((e) => ColoredShape(color(e), Shape.parse(e))).toList(),
      jars: [
        for (final e in list('jars'))
          JarDef(
            color(e),
            _rect(e['rect']),
            (e['fill'] as num?)?.toDouble() ?? 0.6,
            (e['purity'] as num?)?.toDouble() ?? 0.9,
            slot: e['slot'] as bool? ?? false,
          ),
        // A frame is a row of slots sharing walls.
        for (final f in list('frames'))
          for (final (i, c) in (f['colors'] as List).cast<String>().indexed)
            JarDef(
              SandColor.values.byName(c),
              (
                x: (f['x'] as num).toInt() + i * ((f['slot'] as List)[0] as int) + i * jarWall,
                y: (f['y'] as num).toInt(),
                w: (f['slot'] as List)[0] as int,
                h: (f['slot'] as List)[1] as int,
              ),
              (f['fill'] as num?)?.toDouble() ?? 0.6,
              (f['purity'] as num?)?.toDouble() ?? 0.8,
              slot: true,
            ),
      ],
      valves: list('valves').map((e) => ValveDef(_rect(e['rect']), e['open'] as bool? ?? false)).toList(),
      filters: list('filters').map((e) => ColoredShape(color(e), Shape.parse(e))).toList(),
      mixers: [for (final e in list('mixers')) MixerDef(_rect(e['rect']))],
      fans: [
        for (final e in list('fans'))
          FanDef(
            _rect(e['rect']),
            (e['dir'] as num?)?.toInt() ?? 1,
            e['on'] as bool? ?? false,
            (e['strength'] as num?)?.toInt() ?? 2,
          ),
      ],
      concept: m['concept'] as String?,
      starPurity: (stars['purity'] as num?)?.toDouble() ?? 0.95,
      starSpill: (stars['spill'] as num?)?.toDouble() ?? 0.10,
    );
  }

  final String id, name;
  final int seed;
  final String? hint;
  final List<Shape> walls;
  final List<ColoredShape> sand, filters;
  final List<JarDef> jars;
  final List<ValveDef> valves;
  final List<MixerDef> mixers;
  final List<FanDef> fans;
  final double starPurity, starSpill;
  final String? concept;

  /// Builds the playfield. Order matters: walls, filters, valves, jar glass, then
  /// sand into whatever is still empty.
  SandSim build() {
    final sim = SandSim(levelW, levelH, seed: seed);
    for (final w in walls) {
      w.paint(sim, Cell.wall);
    }
    for (final f in filters) {
      f.shape.paint(sim, Cell.filterFor(f.color.cellType));
    }
    for (final v in valves) {
      if (!v.open) RectShape(v.r).paint(sim, Cell.gate);
    }
    for (final j in jars) {
      final r = j.r;
      sim.fillRect(r.x - jarWall, r.y, jarWall, r.h + jarWall, Cell.wall);
      sim.fillRect(r.x + r.w, r.y, jarWall, r.h + jarWall, Cell.wall);
      sim.fillRect(r.x, r.y + r.h, r.w, jarWall, Cell.wall);
    }
    for (final s in sand) {
      s.shape.paint(sim, s.color.cellType, onlyEmpty: true);
    }
    return sim;
  }

  /// Static checks. Returns problems; empty = valid.
  List<String> problems() {
    final out = <String>[];
    bool inside(IRect r) => r.x >= 0 && r.y >= 0 && r.x + r.w <= levelW && r.y + r.h <= levelH;
    if (jars.isEmpty) out.add('no jars');
    for (final (i, j) in jars.indexed) {
      final r = j.r;
      final outer = (x: r.x - jarWall, y: r.y, w: r.w + 2 * jarWall, h: r.h + jarWall + (j.slot ? 0 : jarLabelRows));
      if (!inside(outer)) out.add('jar $i (+ glass and label room) is outside the field');
      if (r.w < 6 || r.h < 8) out.add('jar $i is smaller than 6x8');
      if (j.fill <= 0.1 || j.fill > 0.85) out.add('jar $i fill ${j.fill} not in (0.1, 0.85] (cork row needs room)');
      if (j.purity < 0.5 || j.purity > 1) out.add('jar $i purity ${j.purity} not in [0.5, 1]');
    }
    for (final (i, f) in filters.indexed) {
      final b = f.shape.bounds;
      if (f.shape is! RectShape || math.min(b.w, b.h) > 2) out.add('filter $i must be a rect ≤ 2 cells thick');
    }
    for (final (i, v) in valves.indexed) {
      if (!inside(v.r)) out.add('valve $i is outside the field');
    }
    for (final (i, m) in mixers.indexed) {
      if (!inside(m.r)) out.add('mixer $i is outside the field');
    }
    for (final (i, f) in fans.indexed) {
      if (!inside(f.r)) out.add('fan $i is outside the field');
      if (f.dir.abs() != 1 || f.strength < 1 || f.strength > 3) out.add('fan $i needs dir ±1 and strength 1..3');
    }
    // Sand budget: each color needs at least what its jars need (secondaries
    // can also come from their primaries when there's a mixer).
    final sim = build();
    for (final c in SandColor.values) {
      final need = jars.where((j) => j.color == c).fold(0, (a, j) => a + j.needed);
      var have = sim.count[c.cellType];
      final ing = ingredientsOf(c);
      if (mixers.isNotEmpty && ing != null) have += sim.count[ing.$1.cellType] + sim.count[ing.$2.cellType];
      if (need > have) out.add('${c.name}: jars need $need grains, level has $have');
    }
    return out;
  }
}
