import 'dart:math' as math;

import 'package:yokonex_ems_game/core/model/models.dart';
import 'package:yokonex_ems_game/features/waveforms/waveform_catalog.dart';

class GameOutput {
  const GameOutput({
    required this.strengthA,
    required this.strengthB,
    required this.waveformA,
    required this.waveformB,
  });

  final int strengthA;
  final int strengthB;
  final WaveformStep waveformA;
  final WaveformStep waveformB;
}

abstract final class GameEngine {
  // 按绝对已过时间计算强度，页面卡顿不会多加或少加强度。
  static int strengthAt(ChannelGameConfig config, int elapsedMs) {
    final intervalMs = config.increaseEverySeconds * 1000;
    final increases = elapsedMs < 0 ? 0 : elapsedMs ~/ intervalMs;
    return math.min(
      config.maxStrength,
      config.startStrength + increases * config.increaseBy,
    );
  }

  static GameOutput outputAt({
    required EmsGameConfig config,
    required int elapsedMs,
    required Map<String, EmsWaveform> waveforms,
  }) {
    final waveformA =
        waveforms[config.channelA.waveformId] ?? WaveformCatalog.presets.first;
    // 一代只有 AB 共用一套输出参数，单独选择 B 时仍读取 B 通道配置。
    final linkedB =
        (config.protocol == DeviceProtocol.emsV1 &&
            config.channels == ChannelSelection.ab) ||
        config.channelsLinked;
    final channelBConfig = linkedB ? config.channelA : config.channelB;
    final waveformB = waveforms[channelBConfig.waveformId] ?? waveformA;

    final strengthA = config.channels.includesA
        ? strengthAt(config.channelA, elapsedMs)
        : 0;
    final strengthB = config.channels.includesB
        ? (linkedB ? strengthA : strengthAt(channelBConfig, elapsedMs))
        : 0;
    return GameOutput(
      strengthA: strengthA,
      strengthB: strengthB,
      waveformA: WaveformCatalog.sample(waveformA, elapsedMs),
      waveformB: WaveformCatalog.sample(waveformB, elapsedMs),
    );
  }
}
