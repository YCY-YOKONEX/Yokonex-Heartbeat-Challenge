import 'package:audioplayers/audioplayers.dart';

enum CountdownVoiceCue {
  three('audio/countdown/three.wav'),
  two('audio/countdown/two.wav'),
  one('audio/countdown/one.wav'),
  go('audio/countdown/go.wav');

  const CountdownVoiceCue(this.assetPath);

  final String assetPath;
}

abstract interface class CountdownVoicePlayer {
  Future<void> play(String sessionId, CountdownVoiceCue cue);

  Future<void> stop(String sessionId);

  Future<void> stopAll();

  Future<void> dispose();
}

class AssetCountdownVoicePlayer implements CountdownVoicePlayer {
  final Map<String, AudioPlayer> _players = <String, AudioPlayer>{};
  final Map<CountdownVoiceCue, DateTime> _lastCueAt =
      <CountdownVoiceCue, DateTime>{};

  @override
  Future<void> play(String sessionId, CountdownVoiceCue cue) async {
    final now = DateTime.now();
    final lastCueAt = _lastCueAt[cue];
    // A/B 同时接入时只播报一次相同数字，避免完全重叠导致音量突增。
    if (lastCueAt != null && now.difference(lastCueAt).inMilliseconds < 250) {
      return;
    }
    _lastCueAt[cue] = now;
    final player = _players.putIfAbsent(sessionId, AudioPlayer.new);
    await player.stop();
    await player.play(AssetSource(cue.assetPath));
  }

  @override
  Future<void> stop(String sessionId) async {
    await _players[sessionId]?.stop();
  }

  @override
  Future<void> stopAll() async {
    await Future.wait(_players.values.map((player) => player.stop()));
  }

  @override
  Future<void> dispose() async {
    await Future.wait(_players.values.map((player) => player.dispose()));
    _players.clear();
    _lastCueAt.clear();
  }
}
