import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../meta/album.dart';
import '../meta/progress.dart';
import 'components.dart';
import 'tokens.dart';

/// Revealed tiles of a picture, given the level paths in play order.
Set<int> revealedTiles(int picture, List<String> paths) => {
      for (var t = 0; t < tilesPerPicture; t++)
        if (picture * tilesPerPicture + t < paths.length && progress.starsFor(paths[picture * tilesPerPicture + t]) > 0) t,
    };

/// Draws a picture: revealed tiles in sand pixels, hidden ones as plain sand
/// with a faint grid. [pouring] (tile, 0..1) fills a tile from the bottom up.
class AlbumPicturePainter extends CustomPainter {
  AlbumPicturePainter(this.picture, this.revealed, {this.pouring, super.repaint});
  final AlbumPicture picture;
  final Set<int> revealed;
  final (int tile, double t)? pouring;

  @override
  void paint(Canvas canvas, Size size) {
    final px = size.width / albumW, py = size.height / albumH;
    final paint = Paint();
    for (var tile = 0; tile < tilesPerPicture; tile++) {
      final o = tileOrigin(tile);
      final pour = pouring;
      final visibleRows = revealed.contains(tile)
          ? tileH
          : (pour != null && pour.$1 == tile ? (pour.$2 * tileH).floor() : 0);
      for (var dy = 0; dy < tileH; dy++) {
        final y = o.y + dy;
        final shown = dy >= tileH - visibleRows; // reveal from the bottom up, like sand settling
        for (var dx = 0; dx < tileW; dx++) {
          final x = o.x + dx;
          final grain = ((x * 73856093) ^ (y * 19349663)) & 3;
          paint.color = shown
              ? _shade(Color(0xFF000000 | picture.at(x, y).rgb), grain)
              : (grain.isEven ? PourColors.surfaceHigh : PourColors.surface);
          canvas.drawRect(Rect.fromLTWH(x * px, y * py, px + 0.6, py + 0.6), paint);
        }
      }
    }
    // Faint tile grid over hidden tiles.
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = PourColors.outline.withValues(alpha: 0.6);
    for (var tile = 0; tile < tilesPerPicture; tile++) {
      if (revealed.contains(tile)) continue;
      final o = tileOrigin(tile);
      canvas.drawRect(Rect.fromLTWH(o.x * px, o.y * py, tileW * px, tileH * py), grid);
    }
  }

  static Color _shade(Color c, int grain) {
    final k = const [0.92, 0.97, 1.0, 1.05][grain];
    return Color.from(alpha: 1, red: (c.r * k).clamp(0, 1), green: (c.g * k).clamp(0, 1), blue: (c.b * k).clamp(0, 1));
  }

  @override
  bool shouldRepaint(AlbumPicturePainter old) =>
      old.picture != picture || old.revealed.length != revealed.length || old.pouring != pouring;
}

class AlbumScreen extends StatelessWidget {
  const AlbumScreen({super.key, required this.paths});
  final List<String> paths;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Sand Album', style: PourText.heading)),
        body: ListenableBuilder(
          listenable: progress,
          builder: (context, _) => GridView.count(
            padding: const EdgeInsets.all(Space.l),
            crossAxisCount: 2,
            mainAxisSpacing: Space.l,
            crossAxisSpacing: Space.l,
            childAspectRatio: 0.95,
            children: [
              for (final (i, pic) in world1Album.indexed)
                Builder(builder: (context) {
                  final shown = revealedTiles(i, paths);
                  return Squish(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => AlbumPictureScreen(index: i, paths: paths)),
                    ),
                    child: PourCard(
                      padding: const EdgeInsets.all(Space.m),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AspectRatio(
                            aspectRatio: albumW / albumH,
                            child: CustomPaint(painter: AlbumPicturePainter(pic, shown)),
                          ),
                          const SizedBox(height: Space.s),
                          Text(shown.length == tilesPerPicture ? pic.name : '???',
                              style: PourText.heading.copyWith(fontSize: 16)),
                          Text('${shown.length}/$tilesPerPicture tiles',
                              style: PourText.caption.copyWith(color: PourColors.textMuted)),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      );
}

/// One picture, large. Tiles revealed since the last visit pour in one by one.
class AlbumPictureScreen extends StatefulWidget {
  const AlbumPictureScreen({super.key, required this.index, required this.paths});
  final int index;
  final List<String> paths;

  @override
  State<AlbumPictureScreen> createState() => _AlbumPictureScreenState();
}

class _AlbumPictureScreenState extends State<AlbumPictureScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pour = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final Set<int> _shown;
  late final List<int> _queue;

  @override
  void initState() {
    super.initState();
    final revealed = revealedTiles(widget.index, widget.paths);
    _queue = [for (final t in revealed) if (!progress.data.seenTiles.contains(tileKey(widget.index, t))) t]..sort();
    _shown = revealed.difference(_queue.toSet());
    _next();
  }

  Future<void> _next() async {
    if (_queue.isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    await _pour.forward(from: 0);
    if (!mounted) return;
    final t = _queue.removeAt(0);
    setState(() => _shown.add(t));
    progress.markTileSeen(tileKey(widget.index, t));
    _next();
  }

  @override
  void dispose() {
    _pour.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pic = world1Album[widget.index];
    final done = _shown.length == tilesPerPicture && _queue.isEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(done ? pic.name : 'Picture ${widget.index + 1}', style: PourText.heading)),
      body: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(
          children: [
            PourCard(
              padding: const EdgeInsets.all(Space.s),
              child: AspectRatio(
                aspectRatio: albumW / albumH,
                child: AnimatedBuilder(
                  animation: _pour,
                  builder: (_, _) => CustomPaint(
                    painter: AlbumPicturePainter(
                      pic,
                      {..._shown},
                      pouring: _queue.isEmpty ? null : (_queue.first, Curves.easeOut.transform(_pour.value)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.l),
            Text(
              done
                  ? 'Picture complete!'
                  : 'Finish levels ${widget.index * tilesPerPicture + 1}–${math.min((widget.index + 1) * tilesPerPicture, widget.paths.length)} to reveal it',
              style: PourText.body.copyWith(color: PourColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
