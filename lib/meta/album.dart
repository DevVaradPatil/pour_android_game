// The Sand Album: one picture per 10 levels, one tile per level; the boss
// level at the end of each block completes the picture. Pictures are pixel art
// drawn in code from the sand palette, so they look like sand art.
// Pure Dart.
import 'dart:math' as math;
import 'dart:typed_data';

import '../game/palette.dart';

const int albumW = 40, albumH = 24;
const int tileCols = 5, tileRows = 2;
const int tilesPerPicture = tileCols * tileRows;
const int tileW = albumW ~/ tileCols, tileH = albumH ~/ tileRows;

class AlbumPicture {
  AlbumPicture(this.name, int Function(int x, int y) paint) : pixels = Uint8List(albumW * albumH) {
    for (var y = 0; y < albumH; y++) {
      for (var x = 0; x < albumW; x++) {
        pixels[y * albumW + x] = paint(x, y);
      }
    }
  }

  final String name;

  /// [SandColor] index per pixel, row-major.
  final Uint8List pixels;

  SandColor at(int x, int y) => SandColor.values[pixels[y * albumW + x]];
}

/// Level (0-based, in play order) → (picture, tile).
(int, int) tileOf(int levelIndex) => (levelIndex ~/ tilesPerPicture, levelIndex % tilesPerPicture);

String tileKey(int picture, int tile) => '$picture:$tile';

/// Pixel rect of a tile: tiles fill left→right, top row first.
({int x, int y}) tileOrigin(int tile) => (x: (tile % tileCols) * tileW, y: (tile ~/ tileCols) * tileH);

final _b = SandColor.blue.index, _y = SandColor.yellow.index, _r = SandColor.red.index, _g = SandColor.green.index;
final _p = SandColor.purple.index, _o = SandColor.orange.index, _w = SandColor.white.index;

bool _inCircle(int x, int y, double cx, double cy, double r) => (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r;
double _dune(int x, double base, double amp, double freq, double phase) => base + amp * math.sin(x * freq + phase);

final List<AlbumPicture> world1Album = [
  AlbumPicture('Hourglass', (x, y) {
    final cx = 19.5, dx = (x - cx).abs();
    final glassHalf = 2 + (y - 12).abs() * 0.8; // narrow waist at y = 12
    if (y == 2 || y == 21) return x >= 9 && x <= 30 ? _w : _p; // caps
    if (y > 2 && y < 21 && (dx - glassHalf).abs() < 0.9) return _w; // glass outline
    if (y > 2 && y < 21 && dx < glassHalf) {
      if (y < 12 && y > 7) return _y; // sand left in the top
      if (y > 15) return _y; // sand pile at the bottom
      if (y >= 12 && dx < 1) return _y; // the falling thread
      return _b;
    }
    return _p;
  }),
  AlbumPicture('Desert Sunset', (x, y) {
    if (y > _dune(x, 18, 1.5, 0.25, 0)) return _r;
    if (y > _dune(x, 15, 2, 0.18, 1.5)) return _o;
    if (_inCircle(x, y, 20, 14, 5)) return _y;
    return y < 4 ? _p : (y < 8 ? _r : (y < 12 ? _o : _y));
  }),
  AlbumPicture('Twilight', (x, y) {
    if (y > _dune(x, 17, 2, 0.2, 0.7)) return _p;
    if (_inCircle(x, y, 30, 6, 3.5) && !_inCircle(x, y, 31.5, 5, 3.2)) return _w; // crescent
    if ((x * 7 + y * 13) % 29 == 0 && y < 13) return _w; // stars
    return y < 9 ? _b : _p;
  }),
  AlbumPicture('Ember', (x, y) {
    final slope = 23 - (13 - (x - 20).abs()) * 1.4; // volcano flank
    if (y > slope && (x - 20).abs() < 14) {
      if ((x - 20).abs() < 2 + (y - 6) * 0.15 && y > 6) return y.isEven ? _o : _y; // lava channel
      return _p;
    }
    if (y < 6 && (x - 20).abs() < 3 + y) return (x + y).isEven ? _y : _o; // eruption plume
    return y < 10 ? _r : _o;
  }),
  AlbumPicture('Rainbow', (x, y) {
    if (y > 19) return _g;
    final d = math.sqrt((x - 20) * (x - 20) + (y - 24) * (y - 24).toDouble());
    const bands = [21.0, 19.5, 18.0, 16.5, 15.0, 13.5];
    final colors = [_r, _o, _y, _g, _b, _p];
    for (var i = 0; i < bands.length; i++) {
      if (d <= bands[i] && d > bands[i] - 1.5) return colors[i];
    }
    return _inCircle(x, y, 6, 5, 2.5) || _inCircle(x, y, 9, 5, 3) ? _w : _b; // a cloud
  }),
  AlbumPicture('Desert Night', (x, y) {
    if ((x == 9 || x == 10) && y > 11 && y < 20) return _g; // cactus trunk
    if ((x == 7 && y > 13 && y < 17) || (x == 12 && y > 12 && y < 16) || (y == 16 && x == 8) || (y == 15 && x == 11)) {
      return _g; // cactus arms
    }
    if (y > _dune(x, 19, 1.5, 0.22, 2)) return _p;
    if (_inCircle(x, y, 31, 6, 3.5)) return _w; // moon
    if ((x * 11 + y * 5) % 23 == 0 && y < 14) return _y; // stars
    return _b;
  }),
];
