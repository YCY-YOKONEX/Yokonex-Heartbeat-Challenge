import 'dart:math' as math;

import 'package:yokonex_ems_game/core/model/models.dart';

abstract final class WaveformCatalog {
  static const int _sampleDurationMs = 100;
  static const EmsWaveform smoothRamp = EmsWaveform(
    id: smoothRampWaveformId,
    name: '平缓渐强（0.5秒）',
    steps: <WaveformStep>[
      WaveformStep(durationMs: 100, frequency: 14, pulseWidth: 20),
      WaveformStep(durationMs: 100, frequency: 15, pulseWidth: 28),
      WaveformStep(durationMs: 100, frequency: 16, pulseWidth: 38),
      WaveformStep(durationMs: 100, frequency: 18, pulseWidth: 50),
      WaveformStep(durationMs: 100, frequency: 20, pulseWidth: 64),
    ],
  );
  static final List<int> _frequencyPeriodsMs = <int>[
    for (var value = 10; value <= 50; value++) value,
    for (var value = 52; value <= 80; value += 2) value,
    85,
    90,
    95,
    100,
    for (var value = 110; value <= 200; value += 10) value,
    233,
    266,
    300,
    333,
    366,
    400,
    450,
    500,
    550,
    600,
    700,
    800,
    900,
    1000,
  ];

  // 数据和解码规则复用 Yokonex-DeviceController 的 EMS 经典波形。
  // 通道强度标记不会进入本项目模型，强度始终由游戏规则单独计算。
  static final List<EmsWaveform> presets = <EmsWaveform>[
    ...<_ClassicPulse>[
      const _ClassicPulse(
        111,
        '呼吸',
        '35,1,8=0,20,0,1,1/0-1,20-0,40-0,60-0,80-0,100-1,100-1,100-1',
        restMs: 4000,
      ),
      const _ClassicPulse(
        112,
        '潮汐',
        '0,32,19,2,1/0-1,16.65-0,33.3-0,50-0,66.65-0,83.3-0,100-1,92-0,84-0,76-0,68-1',
      ),
      const _ClassicPulse(
        113,
        '连击',
        '0,34,19,1,1/100-1,0-1,100-1,66.65-0,33.3-0,0-1,0-0,0-1',
      ),
      const _ClassicPulse(114, '快速按捏', '0,29,43,1,1/0-1,100-1'),
      const _ClassicPulse(
        115,
        '按捏渐强',
        '0,20,19,1,1/0-1,28.55-1,0-1,52.5-1,0-1,73.4-1,0-1,87.25-1,0-1,100-1,0-1',
      ),
      const _ClassicPulse(
        116,
        '心跳节奏',
        '65,20,5,1,1/100-1,100-1+section+0,20,19,1,1/0-1,0-0,0-0,0-0,0-1,75-1,83.3-0,91.65-0,100-1,0-1,0-0,0-0,0-0,0-1',
      ),
      const _ClassicPulse(
        117,
        '压缩',
        '52,16,0,2,1/100-1,100-0,100-0,100-0,100-0,100-0,100-0,100-0,100-0,100-0,100-1+section+0,20,0,1,1/100-1,100-0,100-0,100-0,100-0,100-0,100-0,100-0,100-0,100-1',
      ),
      const _ClassicPulse(
        118,
        '节奏步伐',
        '0,20,19,1,1/0-1,20-0,40-0,60-0,80-0,100-1,0-1,25-0,50-0,75-0,100-1,0-1,33.3-0,66.65-0,100-1,0-1,50-0,100-1,0-1,100-1,0-1,100-1,0-1,100-1,0-1,100-1',
      ),
      const _ClassicPulse(119, '颗粒摩擦', '0,38,24,2,1/100-1,100-0,100-1,0-1'),
      const _ClassicPulse(120, '渐变弹跳', '0,30,44,2,1/0-1,33.3-0,66.65-0,100-1'),
      const _ClassicPulse(121, '波浪涟漪', '0,60,51,4,1/0-1,50-0,100-1,73.35-1'),
      const _ClassicPulse(
        122,
        '雨水冲刷',
        '4,0,38,1,1/33.5-1,66.75-0,100-1+section+44,54,34,1,1/100-1,100-1',
      ),
      const _ClassicPulse(
        123,
        '变速敲击',
        '14,20,40,1,1/100-1,100-0,100-1,0-1,0-0,0-0,0-1+section+65,20,39,1,1/100-1,100-0,100-0,100-1',
      ),
      const _ClassicPulse(
        124,
        '信号灯',
        '78,64,19,1,1/100-1,100-0,100-0,100-1+section+0,20,19,3,1/0-1,33.3-0,66.65-0,100-1',
      ),
      const _ClassicPulse(
        125,
        '挑逗1',
        '0,20,35,3,1/0-1,25-0,50-0,75-0,100-1,100-1,100-1,0-1,0-0,0-1+section+0,20,21,1,1/0-1,100-1',
      ),
      const _ClassicPulse(
        126,
        '挑逗2',
        '27,7,32,3,1/0-1,11.1-0,22.2-0,33.3-0,44.4-0,55.5-0,66.6-0,77.7-0,88.8-0,100-1+section+0,20,39,2,1/0-1,100-1',
      ),
    ].map(_toWaveform),
    smoothRamp,
  ];

  static WaveformStep sample(EmsWaveform waveform, int elapsedMs) {
    final duration = waveform.durationMs;
    if (duration <= 0) {
      return const WaveformStep(durationMs: 100, frequency: 0, pulseWidth: 0);
    }
    var cursor = elapsedMs % duration;
    for (final step in waveform.steps) {
      if (cursor < step.durationMs) return step;
      cursor -= step.durationMs;
    }
    return waveform.steps.last;
  }

  static EmsWaveform _toWaveform(_ClassicPulse pulse) {
    final separator = pulse.data.indexOf('=');
    final body = separator < 0
        ? pulse.data
        : pulse.data.substring(separator + 1);
    final steps = body
        .split('+section+')
        .expand(_decodeSection)
        .toList(growable: true);
    if (pulse.restMs > 0) {
      steps.add(
        WaveformStep(durationMs: pulse.restMs, frequency: 0, pulseWidth: 0),
      );
    }
    return EmsWaveform(
      id: 'coyote-pulse-${pulse.id}',
      name: pulse.name,
      steps: steps,
    );
  }

  static List<WaveformStep> _decodeSection(String value) {
    final section = value.split('/');
    if (section.length != 2) throw const FormatException('经典波形小节格式错误');
    final header = section.first.split(',').map(int.parse).toList();
    if (header.length != 5) throw const FormatException('经典波形小节参数错误');
    if (header[4] == 0) return const <WaveformStep>[];
    final shape = section.last
        .split(',')
        .map((point) => double.parse(point.split('-').first))
        .toList();
    if (shape.length < 2) throw const FormatException('经典波形采样点不足');
    final repeatCount = math.max(1, ((header[2] + 1) / shape.length).ceil());
    final totalSamples = repeatCount * shape.length;
    final steps = <WaveformStep>[];
    for (var repeatIndex = 0; repeatIndex < repeatCount; repeatIndex++) {
      for (var shapeIndex = 0; shapeIndex < shape.length; shapeIndex++) {
        final sampleIndex = repeatIndex * shape.length + shapeIndex;
        final frequencyIndex = switch (header[3]) {
          1 => header[0],
          2 => _interpolate(header[0], header[1], sampleIndex, totalSamples),
          3 => _interpolate(header[0], header[1], shapeIndex, shape.length),
          4 => _interpolate(header[0], header[1], repeatIndex, repeatCount),
          _ => throw FormatException('不支持的经典波形频率模式 ${header[3]}'),
        };
        steps.add(
          WaveformStep(
            durationMs: _sampleDurationMs,
            frequency: _frequencyHz(frequencyIndex),
            pulseWidth: shape[shapeIndex].round().clamp(0, 100),
          ),
        );
      }
    }
    return steps;
  }

  static int _interpolate(int start, int end, int index, int count) {
    if (count <= 1) return start;
    return (start + (end - start) * index / (count - 1)).round();
  }

  static int _frequencyHz(int index) {
    final bounded = index.clamp(0, _frequencyPeriodsMs.length - 1);
    return (1000 / _frequencyPeriodsMs[bounded]).round().clamp(1, 100);
  }
}

class _ClassicPulse {
  const _ClassicPulse(this.id, this.name, this.data, {this.restMs = 0});

  final int id;
  final String name;
  final String data;
  final int restMs;
}
