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
//   "stars":   {"purity": 0.95, "spill": 0.10}
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
  JarDef(this.color, this.r, this.fill, this.purity);
  final SandColor color;
  final IRect r; // inside of the jar
  final double fill; // fraction of the inside that must be filled
  final double purity; // min share of [color] needed to cork

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
    this.starPurity = 0.95,
    this.starSpill = 0.10,
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
      jars: list('jars')
          .map((e) => JarDef(
                color(e),
                _rect(e['rect']),
                (e['fill'] as num?)?.toDouble() ?? 0.6,
                (e['purity'] as num?)?.toDouble() ?? 0.9,
              ))
          .toList(),
      valves: list('valves').map((e) => ValveDef(_rect(e['rect']), e['open'] as bool? ?? false)).toList(),
      filters: list('filters').map((e) => ColoredShape(color(e), Shape.parse(e))).toList(),
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
  final double starPurity, starSpill;

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
      final outer = (x: r.x - jarWall, y: r.y, w: r.w + 2 * jarWall, h: r.h + jarWall + jarLabelRows);
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
    // Sand budget: each color needs at least what its jars need.
    final sim = build();
    for (final c in SandColor.values) {
      final need = jars.where((j) => j.color == c).fold(0, (a, j) => a + j.needed);
      final have = sim.count[c.cellType];
      if (need > have) out.add('${c.name}: jars need $need grains, level has $have');
    }
    return out;
  }
}
