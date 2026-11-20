import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pour_sand_game/meta/progress.dart';
import 'package:pour_sand_game/services/audio.dart';

class FakeBackend implements AudioBackend {
  final calls = <String>[];
  final loops = <String, (double, double)>{};

  @override
  void play(String file, double volume) => calls.add('play $file');
  @override
  void startLoop(String id, String file, double volume) {
    calls.add('start $id');
    loops[id] = (volume, 1);
  }

  @override
  void setLoop(String id, double volume, double rate) {
    calls.add('set $id');
    loops[id] = (volume, rate);
  }

  @override
  void stopLoop(String id) {
    calls.add('stop $id');
    loops.remove(id);
  }

  @override
  void pauseLoops() => calls.add('pause');
  @override
  void resumeLoops() => calls.add('resume');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeBackend fake;
  late Audio a;

  setUp(() {
    progress = Progress();
    fake = FakeBackend();
    a = Audio()..init(fake);
  });

  test('music follows the setting', () {
    expect(fake.calls, ['start music']);
    progress.updateSettings((s) => s.music = false);
    a.syncMusic();
    a.syncMusic();
    expect(fake.calls, ['start music', 'stop music']);
  });

  test('effects play only with sound on, from assets/audio', () {
    a.sfx(Sfx.cork);
    progress.updateSettings((s) => s.sound = false);
    a.sfx(Sfx.tap);
    expect(fake.calls.where((c) => c.startsWith('play')), ['play cork.wav']);
    for (final s in Sfx.values) {
      expect(File('assets/audio/${s.name}.wav').existsSync(), isTrue, reason: s.name);
    }
  });

  test('sand loop: volume follows flow, pitch follows fill, quiet frames send nothing', () {
    a.sandStart();
    for (var i = 0; i < 20; i++) {
      a.flow(1, 0.5);
    }
    final (vol, rate) = fake.loops['sand']!;
    expect(vol, closeTo(Audio.sandVolume, 0.05));
    expect(rate, closeTo(1.05, 0.01));
    for (var i = 0; i < 60; i++) {
      a.flow(0, 0.5);
    }
    expect(fake.loops['sand']!.$1, 0); // released to true silence
    final before = fake.calls.length;
    for (var i = 0; i < 60; i++) {
      a.flow(0, 0.5);
    }
    expect(fake.calls.length, before); // nothing to say while silent
  });

  test('sand loop survives a level → next level handover', () {
    a.sandStart(); // level 1
    a.sandStart(); // level 2 starts before level 1 is disposed
    a.sandStop(); // level 1 disposed
    expect(fake.loops.containsKey('sand'), isTrue);
    a.sandStop();
    expect(fake.loops.containsKey('sand'), isFalse);
  });

  test('sound off silences the sand loop', () {
    a.sandStart();
    progress.updateSettings((s) => s.sound = false);
    for (var i = 0; i < 10; i++) {
      a.flow(1, 0);
    }
    expect(fake.loops['sand']!.$1, 0);
  });

  testWidgets('loops pause while the app is in the background', (tester) async {
    final b = tester.binding;
    b.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final f = FakeBackend();
    Audio().init(f);
    b
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(f.calls, ['start music', 'pause', 'resume']);
  });
}
