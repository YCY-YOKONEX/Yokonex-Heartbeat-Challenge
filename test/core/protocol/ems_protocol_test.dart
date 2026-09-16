import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yokonex_ems_game/core/model/models.dart';
import 'package:yokonex_ems_game/core/protocol/ems_protocol.dart';

void main() {
  group('EMS 控制包', () {
    test('一代 A/B/AB 和停止包使用大端强度与累加和', () {
      expect(
        EmsPacketEncoder.v1Control(
          channels: ChannelSelection.a,
          enabled: true,
          strength: 180,
          mode: 0x11,
          frequency: 50,
          pulseWidth: 60,
        ),
        orderedEquals(<int>[
          0x35,
          0x11,
          0x01,
          0x01,
          0x00,
          0xb4,
          0x11,
          0x32,
          0x3c,
          0x7b,
        ]),
      );
      expect(
        EmsPacketEncoder.v1Control(
          channels: ChannelSelection.b,
          enabled: true,
          strength: 1,
          mode: 0x03,
          frequency: 99,
          pulseWidth: 99,
        ),
        orderedEquals(<int>[
          0x35,
          0x11,
          0x02,
          0x01,
          0x00,
          0x01,
          0x03,
          0x00,
          0x00,
          0x4d,
        ]),
      );
      expect(
        EmsPacketEncoder.stop(DeviceProtocol.emsV1),
        orderedEquals(<int>[
          0x35,
          0x11,
          0x03,
          0x00,
          0x00,
          0x00,
          0x01,
          0x00,
          0x00,
          0x4a,
        ]),
      );
    });

    test('二代固定、实时和频率模式使用协议固定向量', () {
      expect(
        EmsPacketEncoder.v2Fixed(
          strengthA: 180,
          modeA: 2,
          strengthB: 1,
          modeB: 3,
        ),
        orderedEquals(<int>[
          0x35,
          0x11,
          0x01,
          0x00,
          0xb4,
          0x02,
          0x00,
          0x01,
          0x03,
          0x01,
        ]),
      );
      expect(
        EmsPacketEncoder.v2Realtime(
          strengthA: 180,
          frequencyA: 100,
          pulseWidthA: 0,
          strengthB: 180,
          frequencyB: 1,
          pulseWidthB: 100,
        ),
        orderedEquals(<int>[
          0x35,
          0x11,
          0x02,
          0x00,
          0xb4,
          0x64,
          0x00,
          0x00,
          0xb4,
          0x01,
          0x64,
          0x79,
        ]),
      );
      expect(
        EmsPacketEncoder.v2Frequency(
          channel: ChannelSelection.a,
          strength: 180,
          points: <({int frequency, int pulseWidth})>[
            (frequency: 1, pulseWidth: 0),
            (frequency: 100, pulseWidth: 100),
          ],
        ),
        orderedEquals(<int>[
          0x35,
          0x11,
          0x03,
          0x01,
          0x00,
          0xb4,
          0x01,
          0x00,
          0x64,
          0x64,
          0xc7,
        ]),
      );
    });

    test('查询包与协议固定向量一致', () {
      expect(
        EmsPacketEncoder.batteryQuery(),
        orderedEquals(<int>[0x35, 0x71, 0x04, 0xaa]),
      );
      expect(
        EmsPacketEncoder.channelQuery(ChannelSelection.a),
        orderedEquals(<int>[0x35, 0x71, 0x01, 0xa7]),
      );
      expect(
        EmsPacketEncoder.channelQuery(ChannelSelection.b),
        orderedEquals(<int>[0x35, 0x71, 0x02, 0xa8]),
      );
    });

    test('拒绝越界强度和频率模式 AB 通道', () {
      expect(
        () => EmsPacketEncoder.v2Fixed(
          strengthA: 181,
          modeA: 1,
          strengthB: 0,
          modeB: 1,
        ),
        throwsRangeError,
      );
      expect(
        () => EmsPacketEncoder.v2Frequency(
          channel: ChannelSelection.ab,
          strength: 10,
          points: <({int frequency, int pulseWidth})>[
            (frequency: 20, pulseWidth: 20),
          ],
        ),
        throwsArgumentError,
      );
    });
  });

  group('EMS 通知解析', () {
    test('解析电量和 A 通道状态', () {
      final battery = EmsPacketDecoder.decode(
        Uint8List.fromList(<int>[0x35, 0x71, 0x04, 80, 0xfa]),
      );
      expect(battery, isA<BatteryNotification>());
      expect((battery as BatteryNotification).percent, 80);

      final channel = EmsPacketDecoder.decode(
        Uint8List.fromList(<int>[
          0x35,
          0x71,
          0x01,
          0x01,
          0x01,
          0x00,
          0xb4,
          0x11,
          0x6e,
        ]),
      );
      expect(channel, isA<ChannelStatusNotification>());
      final status = channel as ChannelStatusNotification;
      expect(status.channel, ChannelSelection.a);
      expect(status.electrode, ElectrodeState.discharging);
      expect(status.enabled, isTrue);
      expect(status.strength, 180);
      expect(status.mode, 0x11);
    });

    test('解析设备异常和未知通知', () {
      final error = EmsPacketDecoder.decode(
        Uint8List.fromList(<int>[0x35, 0x71, 0x55, 0x01, 0xfc]),
      );
      expect(error, isA<DeviceErrorNotification>());
      expect((error as DeviceErrorNotification).message, '校验码错误');

      final unknown = EmsPacketDecoder.decode(
        Uint8List.fromList(<int>[0x35, 0x71, 0x99, 0x3f]),
      );
      expect(unknown, isA<UnknownNotification>());
    });

    test('拒绝截断包、错误校验和和越界通知', () {
      expect(
        () => EmsPacketDecoder.decode(
          Uint8List.fromList(<int>[0x35, 0x71, 0x04]),
        ),
        throwsFormatException,
      );
      expect(
        () => EmsPacketDecoder.decode(
          Uint8List.fromList(<int>[0x35, 0x71, 0x04, 80, 0x00]),
        ),
        throwsFormatException,
      );
      expect(
        () => EmsPacketDecoder.decode(
          Uint8List.fromList(<int>[0x35, 0x71, 0x04, 101, 0x0f]),
        ),
        throwsFormatException,
      );
      expect(
        () => EmsPacketDecoder.decode(
          Uint8List.fromList(<int>[
            0x35,
            0x71,
            0x02,
            0x02,
            0x01,
            0x00,
            0xb5,
            0x01,
            0x61,
          ]),
        ),
        throwsFormatException,
      );
    });
  });
}
