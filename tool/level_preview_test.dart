// Renders a level's solution replay as a contact sheet of frames, for designing levels.
//   flutter test tool/level_preview_test.dart --dart-define=LEVEL=w1/001
// Writes build/level_previews/<path>.png (no LEVEL = every level). Without a
// replay file the level just runs with no input.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pour_sand_game/game/palette.dart';
import 'package:pour_sand_game/level/level.dart';
import 'package:pour_sand_game/level/level_check.dart';
import 'package:pour_sand_game/level/level_run.dart';
import 'package:pour_sand_game/ui/tokens.dart';

const frames = 8;

Future<ui.Image> _image(LevelRun run) {
  final px = Uint32List(levelW * levelH);
  renderPixels(run.sim, px);
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(px.buffer.asUint8List(), levelW, levelH, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

Future<void> preview(String path) async {
  final level = Level.fromJson(File('assets/levels/$path.json').readAsStringSync());
  final rf = File('assets/levels/$path.replay.json');
  final replay = rf.existsSync() ? Replay.fromJson(rf.readAsStringSync()) : Replay(level.id, [], 600);
  final end = replay.ticks + 60;
  final shots = <(ui.Image, LevelRun, int)>[];
  final every = (end / (frames - 1)).ceil();
  Future<void> snap(LevelRun r) async => shots.add((await _image(r), r, r.tick));
  // Replays are deterministic, so re-play up to each snapshot tick.
  for (var f = 0; f < frames; f++) {
    final r = LevelRun.play(level, Replay(replay.levelId, replay.events, f * every, stars: 0), extraTicks: 0);
    await snap(r);
  }
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  const gap = 8.0, labelH = 22.0;
  final size = Size(frames * (levelW + gap), levelH + labelH);
  canvas.drawRect(Offset.zero & size, Paint()..color = PourColors.bg);
  for (final (i, (img, run, tick)) in shots.indexed) {
    final ox = i * (levelW + gap);
    canvas.drawRect(Rect.fromLTWH(ox, labelH, levelW.toDouble(), levelH.toDouble()), Paint()..color = PourColors.surface);
    canvas.drawImage(img, Offset(ox, labelH), Paint()..filterQuality = FilterQuality.none);
    for (final j in run.jars) {
      final y = labelH + j.def.fillLineY;
      canvas.drawLine(Offset(ox + j.def.r.x, y), Offset(ox + j.def.r.x + j.def.r.w, y),
          Paint()..color = Colors.white.withValues(alpha: 0.7));
    }
    final label = TextPainter(
      text: TextSpan(
        text: 't$tick ${run.gravityDeg.toStringAsFixed(0)}° ${run.status == RunStatus.playing ? '' : run.status.name}',
        style: const TextStyle(fontFamily: 'Nunito', fontSize: 13, color: PourColors.text),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(ox + 2, 3));
  }
  final out = await rec.endRecording().toImage(size.width.ceil(), size.height.ceil());
  final png = await out.toByteData(format: ui.ImageByteFormat.png);
  File('build/level_previews/$path.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  testWidgets('level previews', (tester) async {
    await tester.runAsync(() async {
      await (FontLoader('Nunito')..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
      const only = String.fromEnvironment('LEVEL');
      final paths = only.isNotEmpty ? [only] : parseLevelIndex(File('assets/levels/levels.json').readAsStringSync());
      for (final p in paths) {
        await preview(p);
      }
    });
  });
}
