import 'package:flutter_test/flutter_test.dart';
import 'package:yokonex_ems_game/core/model/models.dart';
import 'package:yokonex_ems_game/features/game/game_engine.dart';
import 'package:yokonex_ems_game/features/waveforms/waveform_catalog.dart';

void main() {
  const channelA = ChannelGameConfig(
    startStrength: 10,
    maxStrength: 25,
    increaseEverySeconds: 2,
    increaseBy: 6,
    waveformId: 'steady',
  );
  const channelB = ChannelGameConfig(
    startStrength: 20,
    maxStrength: 50,
    increaseEverySeconds: 1,
    increaseBy: 10,
    waveformId: 'pulse',
  );
  final waveforms = <String, EmsWaveform>{
    for (final waveform in WaveformCatalog.presets) waveform.id: waveform,
  };

  test('按绝对时间加强度并限制最高强度', () {
    expect(GameEngine.strengthAt(channelA, -1), 10);
    expect(GameEngine.strengthAt(channelA, 1999), 10);
    expect(GameEngine.strengthAt(channelA, 2000), 16);
    expect(GameEngine.strengthAt(channelA, 4000), 22);
    expect(GameEngine.strengthAt(channelA, 6000), 25);
    expect(GameEngine.strengthAt(channelA, 60000), 25);
  });

  test('专用渐强波形的强度增长仍使用外部配置', () {
    const config = ChannelGameConfig(
      startStrength: 10,
      maxStrength: 25,
      increaseEverySeconds: 2,
      increaseBy: 6,
      waveformId: smoothRampWaveformId,
    );
    expect(GameEngine.strengthAt(config, 1999), 10);
    expect(GameEngine.strengthAt(config, 2000), 16);
    expect(GameEngine.strengthAt(config, 4000), 22);
    expect(GameEngine.strengthAt(config, 6000), 25);
  });

  test('未选择的通道始终输出零强度', () {
    final output = GameEngine.outputAt(
      config: _config(
        protocol: DeviceProtocol.emsV2,
        channels: ChannelSelection.a,
      ),
      elapsedMs: 3000,
      waveforms: waveforms,
    );
    expect(output.strengthA, 16);
    expect(output.strengthB, 0);
  });

  test('一代 AB 强制联动 A/B 强度和波形', () {
    final output = GameEngine.outputAt(
      config: _config(
        protocol: DeviceProtocol.emsV1,
        channels: ChannelSelection.ab,
      ),
      elapsedMs: 3000,
      waveforms: waveforms,
    );
    expect(output.strengthA, 16);
    expect(output.strengthB, 16);
    expect(output.waveformB.frequency, output.waveformA.frequency);
    expect(output.waveformB.pulseWidth, output.waveformA.pulseWidth);
  });

  test('一代单独选择 B 时使用 B 的强度和波形配置', () {
    final output = GameEngine.outputAt(
      config: _config(
        protocol: DeviceProtocol.emsV1,
        channels: ChannelSelection.b,
      ),
      elapsedMs: 3000,
      waveforms: waveforms,
    );
    expect(output.strengthA, 0);
    expect(output.strengthB, 50);
  });

  test('二代 AB 关闭联动后分别计算', () {
    final output = GameEngine.outputAt(
      config: _config(
        protocol: DeviceProtocol.emsV2,
        channels: ChannelSelection.ab,
      ),
      elapsedMs: 3000,
      waveforms: waveforms,
    );
    expect(output.strengthA, 16);
    expect(output.strengthB, 50);
  });

  test('配置校验协议上限和名称', () {
    expect(
      () => _config(
        protocol: DeviceProtocol.emsV2,
        channels: ChannelSelection.ab,
      ).validate(),
      returnsNormally,
    );
    expect(
      () => EmsGameConfig(
        challengerName: '挑战者',
        deviceId: 'device',
        protocol: DeviceProtocol.emsV2,
        channels: ChannelSelection.a,
        durationSeconds: 30,
        channelA: const ChannelGameConfig(
          startStrength: 1,
          maxStrength: 181,
          increaseEverySeconds: 1,
          increaseBy: 1,
          waveformId: 'steady',
        ),
        channelB: channelB,
        channelsLinked: false,
      ).validate(),
      throwsArgumentError,
    );
    expect(
      () => EmsGameConfig(
        challengerName: ' ',
        deviceId: 'device',
        protocol: DeviceProtocol.emsV2,
        channels: ChannelSelection.a,
        durationSeconds: 30,
        channelA: channelA,
        channelB: channelB,
        channelsLinked: false,
      ).validate(),
      throwsArgumentError,
    );
  });
}

EmsGameConfig _config({
  required DeviceProtocol protocol,
  required ChannelSelection channels,
}) => EmsGameConfig(
  challengerName: '挑战者',
  deviceId: 'device',
  protocol: protocol,
  channels: channels,
  durationSeconds: 30,
  channelA: const ChannelGameConfig(
    startStrength: 10,
    maxStrength: 25,
    increaseEverySeconds: 2,
    increaseBy: 6,
    waveformId: 'steady',
  ),
  channelB: const ChannelGameConfig(
    startStrength: 20,
    maxStrength: 50,
    increaseEverySeconds: 1,
    increaseBy: 10,
    waveformId: 'pulse',
  ),
  channelsLinked: false,
);
