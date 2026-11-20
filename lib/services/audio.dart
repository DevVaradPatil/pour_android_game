// Sound effects, the pouring-sand loop and the music loop. The game talks to
// [audio] in game terms (sfx, flow, music on/off); [AudioBackend] does the
// playing, so tests use a fake. Silent until init() — tests never touch the plugin.
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

import '../meta/progress.dart';

enum Sfx { cork, valve, fan, tap, star1, star2, star3, win, fail, reveal }

abstract class AudioBackend {
  void play(String file, double volume);
  void startLoop(String id, String file, double volume);
  void setLoop(String id, double volume, double rate);
  void stopLoop(String id);
  void pauseLoops();
  void resumeLoops();
}

class Audio {
  AudioBackend? _backend;
  AppLifecycleListener? _lifecycle;
  bool _musicOn = false;
  int _sandUsers = 0; // level screens alive (Next overlaps two for a moment)
  double _level = 0; // smoothed sand flow, 0..1
  double _sentVol = 0, _sentRate = 1;

  static const musicVolume = 0.35, sandVolume = 0.7;

  void init(AudioBackend backend) {
    _backend = backend;
    _lifecycle ??= AppLifecycleListener(onHide: () => _backend?.pauseLoops(), onShow: () => _backend?.resumeLoops());
    syncMusic();
  }

  void sfx(Sfx s, {double volume = 1}) {
    if (progress.settings.sound) _backend?.play('${s.name}.wav', volume);
  }

  /// Starts or stops the music loop to match the setting.
  void syncMusic() {
    final want = progress.settings.music;
    if (want == _musicOn) return;
    _musicOn = want;
    want ? _backend?.startLoop('music', 'music_loop.wav', musicVolume) : _backend?.stopLoop('music');
  }

  /// While a level is on screen the sand loop runs (silent when nothing moves).
  void sandStart() {
    if (_sandUsers++ > 0) return;
    _level = _sentVol = 0;
    _sentRate = 1;
    _backend?.startLoop('sand', 'sand_loop.wav', 0);
  }

  void sandStop() {
    if (_sandUsers == 0 || --_sandUsers > 0) return;
    _backend?.stopLoop('sand');
  }

  /// Once a frame: [flow] 0..1 (grains moving), [fill] 0..1 (how full the
  /// jars are; pitch rises like a filling bottle). Fast attack, slow release;
  /// the backend only hears about audible changes.
  void flow(double flow, double fill) {
    if (_sandUsers == 0) return;
    flow = flow.clamp(0, 1);
    _level += (flow - _level) * (flow > _level ? 0.5 : 0.12);
    final vol = progress.settings.sound ? math.sqrt(_level) * sandVolume : 0.0;
    final rate = 0.9 + 0.3 * fill.clamp(0, 1);
    final silentNow = vol < 0.03;
    if ((vol - _sentVol).abs() < 0.03 && (rate - _sentRate).abs() < 0.02 && !(silentNow && _sentVol > 0)) return;
    _sentVol = silentNow ? 0 : vol;
    _sentRate = rate;
    _backend?.setLoop('sand', _sentVol, rate);
  }
}

Audio audio = Audio();

/// audioplayers: low-latency pools for one-shots, media players for loops.
/// Mixes with other apps' audio; iOS uses the ambient category, so the silent
/// switch mutes it. Android plays on the media stream (the volume buttons).
class PluginAudio implements AudioBackend {
  PluginAudio() {
    AudioCache.instance = AudioCache(prefix: 'assets/audio/');
  }

  // Given to every player: players copy the global default when created, and
  // setting that default is async, so relying on it races the first player.
  static final _ctx = AudioContext(
    android: const AudioContextAndroid(
      usageType: AndroidUsageType.game,
      contentType: AndroidContentType.sonification,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  final _pools = <String, Future<AudioPool>>{};
  final _loops = <String, AudioPlayer>{};

  @override
  void play(String file, double volume) {
    final pool = _pools[file] ??= AudioPool.create(
      source: AssetSource(file),
      maxPlayers: 3,
      playerMode: PlayerMode.lowLatency,
      audioContext: _ctx,
    );
    pool.then((p) => p.start(volume: volume)).ignore();
  }

  @override
  void startLoop(String id, String file, double volume) {
    final p = _loops[id] ??= AudioPlayer(playerId: id)..setAudioContext(_ctx).ignore();
    p
      ..setReleaseMode(ReleaseMode.loop)
      ..setVolume(volume)
      ..play(AssetSource(file), volume: volume).ignore();
  }

  @override
  void setLoop(String id, double volume, double rate) {
    final p = _loops[id];
    if (p == null) return;
    p.setVolume(volume).ignore();
    p.setPlaybackRate(rate).ignore();
  }

  @override
  void stopLoop(String id) => _loops[id]?.stop().ignore();

  @override
  void pauseLoops() {
    for (final p in _loops.values) {
      if (p.state == PlayerState.playing) p.pause().ignore();
    }
  }

  @override
  void resumeLoops() {
    for (final p in _loops.values) {
      if (p.state == PlayerState.paused) p.resume().ignore();
    }
  }
}
