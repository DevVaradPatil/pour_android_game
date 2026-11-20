// Pure-Dart falling-sand cellular automaton. No Flutter imports (see CLAUDE.md).
//
// Determinism: randomness is a stateless hash of (x, y, tick, seed), so the
// result depends only on the seed and the gravity/edit sequence, and sleeping
// chunks give exactly the same result as processing every cell.
import 'dart:math' as math;
import 'dart:typed_data';

abstract final class Cell {
  static const int empty = 0;
  static const int wall = 1;
  static const int cork = 2; // seals a finished jar
  static const int gate = 3; // closed valve
  static const int firstFilter = 4; // 4..11: lets only the matching sand color through
  static const int firstSand = 12;
  static const int sandColors = 8; // types 12..19
  static const int typeCount = firstSand + sandColors;
  static bool isSand(int t) => t >= firstSand;
  static bool isFilter(int t) => t >= firstFilter && t < firstSand;
  static int filterFor(int sandType) => sandType - firstSand + firstFilter;
}

class SandSim {
  SandSim(this.width, this.height, {this.seed = 1, this.reposeDeg = 35})
      : cells = Uint8List(width * height),
        shade = Uint8List(width * height),
        lost = Int32List(Cell.typeCount),
        count = Int32List(Cell.typeCount),
        _stamp = Uint32List(width * height),
        _cw = (width + _cs - 1) >> _cb,
        _ch = (height + _cs - 1) >> _cb {
    _cur = Uint8List(_cw * _ch);
    _next = Uint8List(_cw * _ch);
    _reposeSin = math.sin(reposeDeg * math.pi / 180);
    _applyGravity(0);
  }

  static const double maxTiltDeg = 70;
  static const int _cb = 4; // chunk = 16x16 cells
  static const int _cs = 1 << _cb;
  // 8 directions, index k = angle k*45° from straight down, clockwise toward +x.
  static const List<int> _dx = [0, 1, 1, 1, 0, -1, -1, -1];
  static const List<int> _dy = [1, 1, 0, -1, -1, -1, 0, 1];

  final int width, height, seed;

  /// Grains can't rest on a surface steeper than this, relative to gravity.
  final double reposeDeg;

  /// Cell type per cell (see [Cell]).
  final Uint8List cells;

  /// Per-grain color variation 0..3; moves with the grain.
  final Uint8List shade;

  /// Grains that left the field, per sand type.
  final Int32List lost;

  /// Grains currently on the field, per sand type.
  final Int32List count;

  /// When true every chunk is processed every step (tests compare against sleeping).
  bool alwaysAwake = false;

  final Uint32List _stamp;
  final int _cw, _ch;
  late Uint8List _cur, _next;
  late double _reposeSin;
  int _tick = 0;
  int _grains = 0;
  double _gravityDeg = double.nan;
  int _k1 = 0, _k2 = 0, _p2 = 0, _allowed = 0, _ledge = 0, _sweep = 0;

  int get tick => _tick;
  int get grains => _grains;
  double get gravityDeg => _gravityDeg;
  int get chunkCount => _cw * _ch;

  /// Chunks processed in the last step (performance overlay).
  int activeChunks = 0;

  /// Grains moved in the last step (drives audio/haptics later).
  int moved = 0;

  /// Sets gravity as an angle from straight down (positive = toward +x),
  /// clamped to ±[maxTiltDeg] and quantized to 0.5° so sensor noise doesn't
  /// keep waking the whole grid.
  void setGravityDegrees(double deg) {
    final q = (deg.clamp(-maxTiltDeg, maxTiltDeg) * 2).roundToDouble() / 2;
    if (q != _gravityDeg) _applyGravity(q);
  }

  void _applyGravity(double q) {
    _gravityDeg = q;
    final s = q / 45;
    final fl = s.floor();
    _k1 = fl & 7;
    _k2 = (fl + 1) & 7;
    _p2 = ((s - fl) * 65536).round(); // probability of picking _k2, out of 65536
    final rad = q * math.pi / 180;
    final gx = math.sin(rad), gy = math.cos(rad);
    _allowed = 0;
    _ledge = 0;
    for (var k = 0; k < 8; k++) {
      final len = (_dx[k] != 0 && _dy[k] != 0) ? math.sqrt2 : 1.0;
      final dot = (_dx[k] * gx + _dy[k] * gy) / len;
      if (dot > _reposeSin) {
        _allowed |= 1 << k; // steep enough to slide
      } else if (dot > 0) {
        // Shallow but downhill: only off a ledge (see _try). Past 45° of tilt this
        // includes up-screen diagonals, which is how sand pours over lips and out of jars.
        _ledge |= 1 << k;
      }
    }
    _sweep = gx > 0.01 ? -1 : (gx < -0.01 ? 1 : 0);
    wakeAll();
  }

  void wakeAll() => _cur.fillRange(0, _cur.length, 1);

  int get(int x, int y) => cells[y * width + x];

  /// Sets one cell (walls, spawning, clearing). Keeps the grain count and wakes neighbours.
  void set(int x, int y, int type) {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    final i = y * width + x;
    final old = cells[i];
    if (old == type) return;
    if (Cell.isSand(old)) {
      _grains--;
      count[old]--;
    }
    if (Cell.isSand(type)) {
      _grains++;
      count[type]++;
    }
    cells[i] = type;
    shade[i] = _hash(x, y, 0x5EED) & 3;
    _wake(x, y);
  }

  void fillRect(int x0, int y0, int w, int h, int type) {
    for (var y = y0; y < y0 + h; y++) {
      for (var x = x0; x < x0 + w; x++) {
        set(x, y, type);
      }
    }
  }

  /// Thick line; thickness ≥ 2 keeps it 4-connected so diagonal moves can't leak through.
  void line(int x0, int y0, int x1, int y1, int type, {int thickness = 3}) {
    final steps = math.max((x1 - x0).abs(), (y1 - y0).abs());
    for (var s = 0; s <= steps; s++) {
      final t = steps == 0 ? 0.0 : s / steps;
      final cx = (x0 + (x1 - x0) * t).round(), cy = (y0 + (y1 - y0) * t).round();
      fillRect(cx - thickness ~/ 2, cy - thickness ~/ 2, thickness, thickness, type);
    }
  }

  /// Fills empty cells inside a circle (debug sand spawning).
  void spawnCircle(int cx, int cy, int r, int type) {
    for (var y = cy - r; y <= cy + r; y++) {
      for (var x = cx - r; x <= cx + r; x++) {
        if (x < 0 || y < 0 || x >= width || y >= height) continue;
        if ((x - cx) * (x - cx) + (y - cy) * (y - cy) > r * r) continue;
        if (cells[y * width + x] == Cell.empty) set(x, y, type);
      }
    }
  }

  /// One CA step: every awake grain tries to move one cell.
  void step() {
    if (alwaysAwake) wakeAll();
    final t = ++_tick;
    final w = width;
    final dir = _sweep != 0 ? _sweep : ((t & 1) == 0 ? 1 : -1);
    var active = 0;
    moved = 0;
    for (var y = height - 1; y >= 0; y--) {
      final crow = (y >> _cb) * _cw;
      for (var ci = 0; ci < _cw; ci++) {
        final cx = dir > 0 ? ci : _cw - 1 - ci;
        if (_cur[crow + cx] == 0) continue;
        if ((y & (_cs - 1)) == _cs - 1 || y == height - 1) active++;
        final x0 = cx << _cb;
        final x1 = math.min(x0 + _cs, w);
        if (dir > 0) {
          for (var x = x0; x < x1; x++) {
            _update(x, y, t);
          }
        } else {
          for (var x = x1 - 1; x >= x0; x--) {
            _update(x, y, t);
          }
        }
      }
    }
    activeChunks = active;
    // Chunks woken during this step run next step; everything else sleeps.
    final tmp = _cur;
    _cur = _next;
    _next = tmp..fillRange(0, tmp.length, 0);
  }

  void _update(int x, int y, int t) {
    final i = y * width + x;
    if (cells[i] < Cell.firstSand || _stamp[i] == t) return;
    final r = _hash(x, y, t);
    final p = (r & 0xFFFF) < _p2 ? _k2 : _k1;
    final a = (r & 0x10000) == 0 ? 1 : -1;
    final b = (r & 0x20000) == 0 ? 2 : -2;
    // Real falls/slides first; a ledge move only when no falling move exists,
    // otherwise grains pick shallow (even up-screen) moves over free falls.
    for (final ledge in const [false, true]) {
      if (_try(i, x, y, p, t, ledge) ||
          _try(i, x, y, (p + a) & 7, t, ledge) ||
          _try(i, x, y, (p - a) & 7, t, ledge) ||
          _try(i, x, y, (p + b) & 7, t, ledge) ||
          _try(i, x, y, (p - b) & 7, t, ledge)) {
        return;
      }
    }
  }

  bool _try(int i, int x, int y, int k, int t, bool ledge) {
    final bit = 1 << k;
    if (((ledge ? _ledge : _allowed) & bit) == 0) return false;
    final nx = x + _dx[k], ny = y + _dy[k];
    if (ledge && !_unsupported(nx, ny)) return false;
    if (nx < 0 || ny < 0 || nx >= width || ny >= height) {
      // Off the field = the void: the grain is lost.
      lost[cells[i]]++;
      count[cells[i]]--;
      cells[i] = Cell.empty;
      _grains--;
      moved++;
      _wake(x, y);
      return true;
    }
    var j = ny * width + nx;
    var tx = nx, ty = ny;
    final target = cells[j];
    if (target != Cell.empty) {
      // A matching filter is see-through: hop over it (≤ 2 cells thick) into the space beyond.
      final f = Cell.filterFor(cells[i]);
      if (target != f) return false;
      var hops = 0;
      do {
        tx += _dx[k];
        ty += _dy[k];
        if (tx < 0 || ty < 0 || tx >= width || ty >= height) return false;
        j = ty * width + tx;
      } while (cells[j] == f && ++hops < 2);
      if (cells[j] != Cell.empty) return false;
    }
    cells[j] = cells[i];
    shade[j] = shade[i];
    cells[i] = Cell.empty;
    _stamp[j] = t;
    moved++;
    _wake(x, y);
    _wake(tx, ty);
    return true;
  }

  /// A ledge: the cell is free and a grain there could keep falling along either
  /// of the two directions bracketing gravity. This lets cliffs that are steeper
  /// than the angle of repose relative to a tilted gravity collapse, which pure
  /// 8-direction moves can't express. A grain's rest decision therefore reads
  /// cells up to 2 away (3 with a filter hop), hence the radius-3 wake below.
  bool _unsupported(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return true;
    if (cells[y * width + x] != Cell.empty) return false;
    return _free(x + _dx[_k1], y + _dy[_k1]) || _free(x + _dx[_k2], y + _dy[_k2]);
  }

  bool _free(int x, int y) =>
      x < 0 || y < 0 || x >= width || y >= height || cells[y * width + x] == Cell.empty;

  /// Wakes every chunk touching the 7x7 neighbourhood of (x, y), for this step and the next.
  void _wake(int x, int y) {
    var cx0 = (x - 3) >> _cb, cx1 = (x + 3) >> _cb;
    var cy0 = (y - 3) >> _cb, cy1 = (y + 3) >> _cb;
    if (cx0 < 0) cx0 = 0;
    if (cy0 < 0) cy0 = 0;
    if (cx1 >= _cw) cx1 = _cw - 1;
    if (cy1 >= _ch) cy1 = _ch - 1;
    for (var cy = cy0; cy <= cy1; cy++) {
      for (var cx = cx0; cx <= cx1; cx++) {
        final c = cy * _cw + cx;
        _cur[c] = 1;
        _next[c] = 1;
      }
    }
  }

  /// Per-type cell counts inside a rect (jar contents). [out] is zeroed first.
  void countRect(int x0, int y0, int w, int h, Int32List out) {
    out.fillRange(0, out.length, 0);
    for (var y = math.max(0, y0); y < math.min(height, y0 + h); y++) {
      final row = y * width;
      for (var x = math.max(0, x0); x < math.min(width, x0 + w); x++) {
        out[cells[row + x]]++;
      }
    }
  }

  /// Shuffles the grains along each row of the rect (deterministic: hash of
  /// seed, tick and row). Mixers stir with this so colors meet, instead of
  /// falling through side by side.
  void stirRect(int x0, int y0, int w, int h) {
    final xs = <int>[];
    for (var y = math.max(0, y0); y < math.min(height, y0 + h); y++) {
      xs.clear();
      for (var x = math.max(0, x0); x < math.min(width, x0 + w); x++) {
        if (Cell.isSand(cells[y * width + x])) xs.add(x);
      }
      for (var k = xs.length - 1; k > 0; k--) {
        final m = _hash(k, y, _tick) % (k + 1);
        final i = y * width + xs[k], j = y * width + xs[m];
        if (cells[i] == cells[j]) continue;
        final c = cells[i], sh = shade[i];
        cells[i] = cells[j];
        shade[i] = shade[j];
        cells[j] = c;
        shade[j] = sh;
        _wake(xs[k], y);
        _wake(xs[m], y);
      }
    }
  }

  /// Moves every grain in the rect one cell sideways ([dx] = ±1) where the
  /// target is empty, downwind side first so a packed row moves as one (fans).
  /// Grains pushed off the field are lost. Returns grains moved.
  int shiftGrains(int x0, int y0, int w, int h, int dx) {
    var n = 0;
    for (var y = math.max(0, y0); y < math.min(height, y0 + h); y++) {
      for (var k = 0; k < w; k++) {
        final x = dx > 0 ? x0 + w - 1 - k : x0 + k;
        if (x < 0 || x >= width) continue;
        final i = y * width + x;
        final c = cells[i];
        if (!Cell.isSand(c)) continue;
        final nx = x + dx;
        if (nx < 0 || nx >= width) {
          lost[c]++;
          count[c]--;
          _grains--;
          cells[i] = Cell.empty;
        } else {
          final j = i + dx;
          if (cells[j] != Cell.empty) continue;
          cells[j] = c;
          shade[j] = shade[i];
          cells[i] = Cell.empty;
          _wake(nx, y);
        }
        _wake(x, y);
        n++;
      }
    }
    return n;
  }

  /// Sets cells of [from] type inside a rect to [to] (open/close valves).
  void replaceInRect(int x0, int y0, int w, int h, int from, int to) {
    for (var y = y0; y < y0 + h; y++) {
      for (var x = x0; x < x0 + w; x++) {
        if (x >= 0 && y >= 0 && x < width && y < height && cells[y * width + x] == from) set(x, y, to);
      }
    }
  }

  int _hash(int x, int y, int t) {
    var h = ((x * 0x9E3779B1) ^ (y * 0x85EBCA77) ^ (t * 0xC2B2AE3D) ^ seed) & 0xFFFFFFFF;
    h ^= h >> 15;
    h = (h * 0x2C1B3C6D) & 0xFFFFFFFF;
    h ^= h >> 12;
    h = (h * 0x297A2D39) & 0xFFFFFFFF;
    h ^= h >> 15;
    return h;
  }

  /// FNV-1a over the cell grid; equal hashes ⇒ identical sand layout.
  int stateHash() {
    var h = 0x811C9DC5;
    for (final c in cells) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }
}
