// One play of a level: the rules on top of the sim (jars, corks, valves, win/lose,
// stars) plus input recording. Pure Dart; same code runs in the app and headless.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../game/palette.dart';
import '../sim/sand_sim.dart';
import 'level.dart';

enum RunStatus { playing, won, outOfSand }

class JarState {
  JarState(this.def);
  final JarDef def;
  bool corked = false;
  int total = 0, match = 0;
  double get purity => total == 0 ? 0 : match / total;
  double get fillProgress => (total / def.target).clamp(0, 1);
  bool get purityOk => total == 0 || purity >= def.purity;
}

/// Recorded input: `[tick, kind, value]`. kind 0 = gravity (half-degrees),
/// 1 = valve toggle (index), 2 = slow-mo (0/1), 3 = fan toggle (index),
/// 4 = +Sand booster (color index). Applied before that tick's step.
/// An Undo isn't recorded: it cuts the events back to the rewind point.
class Replay {
  Replay(this.levelId, this.events, this.ticks, {this.stars = 0});

  factory Replay.fromJson(String src) {
    final m = jsonDecode(src) as Map<String, dynamic>;
    return Replay(
      m['level'] as String,
      [for (final e in m['events'] as List) (e as List).cast<int>()],
      m['ticks'] as int,
      stars: m['stars'] as int? ?? 0,
    );
  }

  final String levelId;
  final List<List<int>> events;
  final int ticks; // tick at which the recorded run ended
  final int stars; // stars the recorded run earned

  String toJson() =>
      const JsonEncoder.withIndent(null).convert({'level': levelId, 'ticks': ticks, 'stars': stars, 'events': events});
}

class LevelRun {
  LevelRun(this.level) : sim = level.build() {
    jars = [for (final j in level.jars) JarState(j)];
    valveOpen = [for (final v in level.valves) v.open];
    fanOn = [for (final f in level.fans) f.on];
    initialGrains = sim.grains;
    _evaluate();
  }

  static const int substeps = 3, slowSubsteps = 1;

  final Level level;
  final SandSim sim;
  late final List<JarState> jars;
  late final List<bool> valveOpen;
  late final List<bool> fanOn;
  late final int initialGrains;
  final List<List<int>> events = [];

  RunStatus status = RunStatus.playing;
  int tick = 0;

  /// Grains moved during the last tick (render/audio cue).
  int moved = 0;
  int _gravityHalf = 0;
  bool _slow = false;
  final _counts = Int32List(Cell.typeCount);
  final _corkedGrains = Int32List(Cell.typeCount);

  bool get slowMo => _slow;
  double get gravityDeg => _gravityHalf / 2;
  int get lostGrains => sim.lost.fold(0, (a, b) => a + b);

  /// Live until the level is won, then frozen: sand keeps settling (and maybe
  /// spilling) after the win, but the result must not change under the player.
  double get spill => _wonSpill ?? (initialGrains == 0 ? 0 : lostGrains / initialGrains);
  double? _wonSpill;
  double get avgPurity => jars.isEmpty ? 0 : jars.fold(0.0, (a, j) => a + j.purity) / jars.length;

  int get stars {
    if (status != RunStatus.won) return 0;
    final pure = avgPurity >= level.starPurity;
    return 1 + (pure ? 1 : 0) + (pure && spill <= level.starSpill ? 1 : 0);
  }

  /// Colors the level can no longer supply (non-empty ⇒ out of sand).
  final Set<SandColor> shortColors = {};

  void setGravityDegrees(double deg) {
    if (status != RunStatus.playing) return;
    final h = (deg.clamp(-SandSim.maxTiltDeg, SandSim.maxTiltDeg) * 2).round();
    if (h == _gravityHalf) return;
    _gravityHalf = h;
    events.add([tick, 0, h]);
  }

  void toggleValve(int i) {
    if (status != RunStatus.playing) return;
    valveOpen[i] = !valveOpen[i];
    final r = level.valves[i].r;
    if (valveOpen[i]) {
      sim.replaceInRect(r.x, r.y, r.w, r.h, Cell.gate, Cell.empty);
    } else {
      // Seal completely: grains caught in the valve are removed (≤ w×3), otherwise
      // they'd leave holes and the hopper would keep leaking after closing.
      for (var y = r.y; y < r.y + r.h; y++) {
        for (var x = r.x; x < r.x + r.w; x++) {
          final c = sim.get(x, y);
          if (c == Cell.empty || Cell.isSand(c)) sim.set(x, y, Cell.gate);
        }
      }
    }
    events.add([tick, 1, i]);
  }

  void toggleFan(int i) {
    if (status != RunStatus.playing) return;
    fanOn[i] = !fanOn[i];
    events.add([tick, 3, i]);
  }

  /// Applies one recorded event (see [Replay]).
  void apply(List<int> e) {
    final [_, kind, value] = e;
    switch (kind) {
      case 0:
        setGravityDegrees(value / 2);
      case 1:
        toggleValve(value);
      case 2:
        setSlowMo(value == 1);
      case 3:
        toggleFan(value);
      case 4:
        addSand(SandColor.values[value]);
    }
  }

  // ---- Boosters ----

  static const int snapshotEvery = 60, undoTicks = 180;
  final List<_Snapshot> _snapshots = [];

  /// Undo is possible once there is something to rewind (not after a win).
  bool get canUndo => status != RunStatus.won && tick > 0;

  /// Rewinds ~3 s: to the newest snapshot at least [undoTicks] old (or the
  /// start). Recorded events after it are dropped, so the replay stays exact.
  void undo() {
    if (!canUndo || _snapshots.isEmpty) return;
    while (_snapshots.length > 1 && _snapshots.last.tick > tick - undoTicks) {
      _snapshots.removeLast();
    }
    final s = _snapshots.last;
    sim.restore(s.sim);
    tick = s.tick;
    status = RunStatus.playing;
    shortColors.clear();
    _gravityHalf = s.gravityHalf;
    _slow = s.slow;
    valveOpen.setAll(0, s.valves);
    fanOn.setAll(0, s.fans);
    _corkedGrains.setAll(0, s.corkedGrains);
    for (final (i, j) in jars.indexed) {
      final (corked, total, match) = s.jars[i];
      j
        ..corked = corked
        ..total = total
        ..match = match;
    }
    events.length = s.events;
  }

  void _takeSnapshot() {
    if (_snapshots.isNotEmpty && _snapshots.last.tick == tick) _snapshots.removeLast();
    _snapshots.add(
      _Snapshot(
        tick: tick,
        sim: sim.snapshot(),
        gravityHalf: _gravityHalf,
        slow: _slow,
        valves: List.of(valveOpen),
        fans: List.of(fanOn),
        corkedGrains: Int32List.fromList(_corkedGrains),
        jars: [for (final j in jars) (j.corked, j.total, j.match)],
        events: events.length,
      ),
    );
    // Enough to reach back undoTicks from anywhere between two snapshots.
    if (_snapshots.length > undoTicks ~/ snapshotEvery + 2) _snapshots.removeAt(0);
  }

  /// +Sand: when out of sand, drops more of [c] where that color started
  /// (or where its ingredients / any sand started), enough for its open jars
  /// plus a margin. Deterministic, so it's recorded like any other input.
  void addSand(SandColor c) {
    if (status != RunStatus.outOfSand) return;
    var want = 0;
    for (final j in jars) {
      if (!j.corked && j.def.color == c) want += math.max(0, j.def.target - j.match);
    }
    var add = math.max(30, (want * 1.3).ceil() + 30 - _available(c));
    final ing = ingredientsOf(c);
    final from = [
      ...level.sand.where((s) => s.color == c),
      if (ing != null) ...level.sand.where((s) => s.color == ing.$1 || s.color == ing.$2),
      ...level.sand,
    ];
    for (final s in from) {
      final b = s.shape.bounds;
      for (var y = b.y + b.h - 1; y >= b.y && add > 0; y--) {
        for (var x = b.x; x < b.x + b.w && add > 0; x++) {
          if (x < 0 || y < 0 || x >= sim.width || y >= sim.height || sim.get(x, y) != Cell.empty) continue;
          sim.set(x, y, c.cellType);
          add--;
        }
      }
      if (add == 0) break;
    }
    events.add([tick, 4, c.index]);
    status = RunStatus.playing;
    shortColors.clear();
  }

  void setSlowMo(bool on) {
    if (status != RunStatus.playing || on == _slow) return;
    _slow = on;
    events.add([tick, 2, on ? 1 : 0]);
  }

  /// One 60 Hz tick. Keeps simulating after the end so sand settles visibly.
  void step() {
    if (status == RunStatus.playing && tick % snapshotEvery == 0) _takeSnapshot();
    sim.setGravityDegrees(gravityDeg);
    moved = 0;
    for (var s = 0; s < (_slow ? slowSubsteps : substeps); s++) {
      sim.step();
      moved += sim.moved;
    }
    for (final (i, f) in level.fans.indexed) {
      if (!fanOn[i]) continue;
      for (var k = 0; k < (_slow ? 1 : f.strength); k++) {
        moved += sim.shiftGrains(f.r.x, f.r.y, f.r.w, f.r.h, f.dir);
      }
    }
    for (final m in level.mixers) {
      sim.stirRect(m.r.x, m.r.y, m.r.w, m.r.h);
      moved += _mix(m.r);
    }
    tick++;
    if (status == RunStatus.playing) _evaluate();
  }

  /// Converts touching pairs of different primaries (right/down neighbours,
  /// row-major, so it's deterministic). Returns grains converted.
  int _mix(IRect r) {
    var n = 0;
    final w = sim.width;
    for (var y = r.y; y < r.y + r.h; y++) {
      for (var x = r.x; x < r.x + r.w; x++) {
        final t = sim.cells[y * w + x];
        if (!Cell.isSand(t)) continue;
        for (final (nx, ny) in [(x + 1, y), (x, y + 1)]) {
          if (nx >= r.x + r.w || ny >= r.y + r.h) continue;
          final u = sim.cells[ny * w + nx];
          if (!Cell.isSand(u)) continue;
          final mix = mixOf(SandColor.ofCell(t), SandColor.ofCell(u));
          if (mix == null) continue;
          sim.set(x, y, mix.cellType);
          sim.set(nx, ny, mix.cellType);
          n += 2;
          break;
        }
      }
    }
    return n;
  }

  /// Grains of [c] still obtainable: loose ones, plus (with a mixer) the
  /// primaries it can be made from. An upper bound, so it never reports
  /// out-of-sand falsely.
  int _available(SandColor c) {
    int free(SandColor k) => sim.count[k.cellType] - _corkedGrains[k.cellType];
    var n = free(c);
    final ing = ingredientsOf(c);
    if (level.mixers.isNotEmpty && ing != null) n += free(ing.$1) + free(ing.$2);
    return n;
  }

  void _evaluate() {
    for (final j in jars) {
      if (j.corked) continue;
      final r = j.def.r;
      sim.countRect(r.x, r.y, r.w, r.h, _counts);
      var total = 0;
      for (var t = Cell.firstSand; t < Cell.typeCount; t++) {
        total += _counts[t];
      }
      j.total = total;
      j.match = _counts[j.def.color.cellType];
      if (total >= j.def.target && j.purity >= j.def.purity) _cork(j);
    }
    if (jars.every((j) => j.corked)) {
      _wonSpill = spill;
      status = RunStatus.won;
      return;
    }
    // Out of sand: some color's open jars need more of it than is left outside
    // corked jars, or the open jars together need more grains than are left at all.
    shortColors.clear();
    var needAll = 0, freeAll = 0;
    for (final c in SandColor.values) {
      var need = 0;
      for (final j in jars) {
        if (j.corked || j.def.color != c) continue;
        need += j.def.needed;
        needAll += j.def.target;
      }
      freeAll += sim.count[c.cellType] - _corkedGrains[c.cellType];
      if (need > 0 && need > _available(c)) shortColors.add(c);
    }
    if (needAll > freeAll) {
      shortColors.addAll([
        for (final j in jars)
          if (!j.corked) j.def.color,
      ]);
    }
    if (shortColors.isNotEmpty) status = RunStatus.outOfSand;
  }

  /// Seals the jar's top row; whatever is inside is safe from then on.
  void _cork(JarState j) {
    final r = j.def.r;
    sim.fillRect(r.x, r.y, r.w, 1, Cell.cork);
    sim.countRect(r.x, r.y + 1, r.w, r.h - 1, _counts);
    for (var t = Cell.firstSand; t < Cell.typeCount; t++) {
      _corkedGrains[t] += _counts[t];
    }
    j.corked = true;
  }

  Replay toReplay() => Replay(level.id, [for (final e in events) List.of(e)], tick, stars: stars);

  /// Plays [replay] headlessly. Runs until the level ends, or [extraTicks] past
  /// the recorded end, whichever is first.
  static LevelRun play(Level level, Replay replay, {int extraTicks = 600, void Function(LevelRun)? onTick}) {
    final run = LevelRun(level);
    var e = 0;
    while (run.tick < replay.ticks + extraTicks) {
      while (e < replay.events.length && replay.events[e][0] <= run.tick) {
        run.apply(replay.events[e++]);
      }
      // After a loss the app keeps settling sand; a later +Sand resumes play.
      if (run.status != RunStatus.playing && e >= replay.events.length) break;
      run.step();
      onTick?.call(run);
    }
    return run;
  }

  /// One-line summary for tools and logs.
  String summary() =>
      '${status.name} t=$tick stars=$stars purity=${(avgPurity * 100).toStringAsFixed(1)}% '
      'spill=${(spill * 100).toStringAsFixed(1)}% jars=[${jars.map((j) => '${j.def.color.name}:${j.corked ? 'corked' : '${(j.fillProgress * 100).round()}%'}').join(' ')}]';
}

class _Snapshot {
  _Snapshot({
    required this.tick,
    required this.sim,
    required this.gravityHalf,
    required this.slow,
    required this.valves,
    required this.fans,
    required this.corkedGrains,
    required this.jars,
    required this.events,
  });
  final int tick, gravityHalf, events;
  final SimSnapshot sim;
  final bool slow;
  final List<bool> valves, fans;
  final Int32List corkedGrains;
  final List<(bool, int, int)> jars;
}
