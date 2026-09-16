import 'dart:typed_data';

import 'package:yokonex_ems_game/core/model/models.dart';

abstract final class EmsPacketEncoder {
  static const int maximumStrength = emsMaximumStrength;

  static Uint8List v1Control({
    required ChannelSelection channels,
    required bool enabled,
    required int strength,
    required int mode,
    required int frequency,
    required int pulseWidth,
  }) {
    _range(strength, 0, maximumStrength, '强度');
    _range(mode, 0x01, 0x11, '模式');
    _range(frequency, 0, 100, '频率');
    _range(pulseWidth, 0, 100, '脉冲时间');
    return _packet(<int>[
      0x35,
      0x11,
      channels.protocolValue,
      enabled ? 0x01 : 0x00,
      _high(enabled ? strength : 0),
      _low(enabled ? strength : 0),
      mode,
      mode == 0x11 ? frequency : 0,
      mode == 0x11 ? pulseWidth : 0,
    ]);
  }

  static Uint8List v2Fixed({
    required int strengthA,
    required int modeA,
    required int strengthB,
    required int modeB,
  }) {
    _range(strengthA, 0, maximumStrength, 'A 通道强度');
    _range(strengthB, 0, maximumStrength, 'B 通道强度');
    _range(modeA, 0x01, 0x10, 'A 通道模式');
    _range(modeB, 0x01, 0x10, 'B 通道模式');
    return _packet(<int>[
      0x35,
      0x11,
      0x01,
      _high(strengthA),
      _low(strengthA),
      modeA,
      _high(strengthB),
      _low(strengthB),
      modeB,
    ]);
  }

  static Uint8List v2Realtime({
    required int strengthA,
    required int frequencyA,
    required int pulseWidthA,
    required int strengthB,
    required int frequencyB,
    required int pulseWidthB,
  }) {
    _range(strengthA, 0, maximumStrength, 'A 通道强度');
    _range(strengthB, 0, maximumStrength, 'B 通道强度');
    _range(frequencyA, 0, 100, 'A 通道频率');
    _range(frequencyB, 0, 100, 'B 通道频率');
    _range(pulseWidthA, 0, 100, 'A 通道脉冲时间');
    _range(pulseWidthB, 0, 100, 'B 通道脉冲时间');
    return _packet(<int>[
      0x35,
      0x11,
      0x02,
      _high(strengthA),
      _low(strengthA),
      frequencyA,
      pulseWidthA,
      _high(strengthB),
      _low(strengthB),
      frequencyB,
      pulseWidthB,
    ]);
  }

  static Uint8List v2Frequency({
    required ChannelSelection channel,
    required int strength,
    required List<({int frequency, int pulseWidth})> points,
  }) {
    if (channel == ChannelSelection.ab) {
      throw ArgumentError('二代频率模式需要分别配置 A、B 通道');
    }
    _range(strength, 0, maximumStrength, '强度');
    if (points.isEmpty || points.length > 100) {
      throw ArgumentError('频率模式需要 1 到 100 组数据');
    }
    final body = <int>[
      0x35,
      0x11,
      0x03,
      channel.protocolValue,
      _high(strength),
      _low(strength),
    ];
    for (final point in points) {
      _range(point.frequency, 1, 100, '频率');
      _range(point.pulseWidth, 0, 100, '脉冲时间');
      body
        ..add(point.frequency)
        ..add(point.pulseWidth);
    }
    return _packet(body);
  }

  static Uint8List stop(DeviceProtocol protocol) =>
      protocol == DeviceProtocol.emsV1
      ? v1Control(
          channels: ChannelSelection.ab,
          enabled: false,
          strength: 0,
          mode: 0x01,
          frequency: 0,
          pulseWidth: 0,
        )
      : v2Realtime(
          strengthA: 0,
          frequencyA: 0,
          pulseWidthA: 0,
          strengthB: 0,
          frequencyB: 0,
          pulseWidthB: 0,
        );

  static Uint8List batteryQuery() => _packet(<int>[0x35, 0x71, 0x04]);

  static Uint8List channelQuery(ChannelSelection channel) {
    if (channel == ChannelSelection.ab) throw ArgumentError('状态查询需要指定单个通道');
    return _packet(<int>[0x35, 0x71, channel.protocolValue]);
  }

  static Uint8List _packet(List<int> body) => Uint8List.fromList(<int>[
    ...body,
    body.fold(0, (sum, byte) => (sum + byte) & 0xff),
  ]);

  static int _high(int value) => (value >> 8) & 0xff;
  static int _low(int value) => value & 0xff;

  static void _range(int value, int minimum, int maximum, String label) {
    if (value < minimum || value > maximum) {
      throw RangeError('$label 需要在 $minimum 到 $maximum 之间');
    }
  }
}

sealed class EmsNotification {
  const EmsNotification();
}

class BatteryNotification extends EmsNotification {
  const BatteryNotification(this.percent);
  final int percent;
}

class ChannelStatusNotification extends EmsNotification {
  const ChannelStatusNotification({
    required this.channel,
    required this.electrode,
    required this.enabled,
    required this.strength,
    required this.mode,
  });

  final ChannelSelection channel;
  final ElectrodeState electrode;
  final bool enabled;
  final int strength;
  final int mode;
}

class DeviceErrorNotification extends EmsNotification {
  const DeviceErrorNotification(this.code, this.message);
  final int code;
  final String message;
}

class UnknownNotification extends EmsNotification {
  const UnknownNotification(this.value);
  final Uint8List value;
}

abstract final class EmsPacketDecoder {
  static EmsNotification decode(Uint8List value) {
    if (value.length < 4) throw const FormatException('通知数据长度不足');
    if (value[0] != 0x35 || value[1] != 0x71) {
      throw const FormatException('通知包头或命令错误');
    }
    final expected = value
        .sublist(0, value.length - 1)
        .fold(0, (sum, byte) => (sum + byte) & 0xff);
    if (expected != value.last) throw const FormatException('通知校验和错误');

    return switch (value[2]) {
      0x01 || 0x02 => _channel(value),
      0x04 => _battery(value),
      0x55 => _error(value),
      _ => UnknownNotification(value),
    };
  }

  static BatteryNotification _battery(Uint8List value) {
    if (value.length != 5) throw const FormatException('电量通知长度错误');
    if (value[3] > 100) throw const FormatException('电量通知数值超出范围');
    return BatteryNotification(value[3]);
  }

  static ChannelStatusNotification _channel(Uint8List value) {
    if (value.length != 9) throw const FormatException('通道状态通知长度错误');
    final electrode = switch (value[3]) {
      0x00 => ElectrodeState.detached,
      0x01 => ElectrodeState.discharging,
      0x02 => ElectrodeState.attachedIdle,
      _ => ElectrodeState.unknown,
    };
    final strength = (value[5] << 8) | value[6];
    if (strength > EmsPacketEncoder.maximumStrength) {
      throw const FormatException('通道强度超出范围');
    }
    return ChannelStatusNotification(
      channel: value[2] == 0x01 ? ChannelSelection.a : ChannelSelection.b,
      electrode: electrode,
      enabled: value[4] == 0x01,
      strength: strength,
      mode: value[7],
    );
  }

  static DeviceErrorNotification _error(Uint8List value) {
    if (value.length != 5) throw const FormatException('异常通知长度错误');
    final message = switch (value[3]) {
      0x01 => '校验码错误',
      0x02 => '包头错误',
      0x03 => '命令错误',
      0x04 => '数据错误',
      0x05 => '功能暂未实现',
      _ => '未知设备异常',
    };
    return DeviceErrorNotification(value[3], message);
  }
}
