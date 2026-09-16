import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yokonex_ems_game/app/app_controller.dart';
import 'package:yokonex_ems_game/core/model/models.dart';
import 'package:yokonex_ems_game/core/platform/ble_adapter.dart';
import 'package:yokonex_ems_game/core/platform/countdown_voice.dart';
import 'package:yokonex_ems_game/core/platform/universal_ble_adapter.dart';
import 'package:yokonex_ems_game/core/storage/app_database.dart';
import 'package:yokonex_ems_game/features/game/game_preset.dart';
import 'package:yokonex_ems_game/features/waveforms/waveform_catalog.dart';

void main() {
  test('A 检测到回路后倒计时期间继续测试，结束时只停止 A', () async {
    final ble = _FakeBleAdapter();
    final container = ProviderContainer(
      overrides: [
        bleAdapterProvider.overrideWithValue(ble),
        databaseProvider.overrideWithValue(_FakeDatabase()),
        countdownVoicePlayerProvider.overrideWithValue(
          _FakeCountdownVoicePlayer(),
        ),
      ],
    );
    final controller = container.read(appControllerProvider.notifier);
    await _waitUntil(() => container.read(appControllerProvider).initialized);

    const device = DiscoveredDevice(
      id: 'device-1',
      name: 'YYC-DJ-V2-001',
      rssi: -45,
      advertisedServices: <String>{UniversalBleAdapter.serviceUuid},
      protocol: DeviceProtocol.emsV2,
    );
    await controller.connect(device, DeviceProtocol.emsV2);
    ble.writes.clear();
    await controller.startRelay(<EmsGameConfig>[
      _relayConfig(ChannelSelection.a, 'A 玩家'),
      _relayConfig(ChannelSelection.b, 'B 玩家'),
    ]);
    await _waitUntil(
      () =>
          ble.writes.any(
            (value) => _isRelayTest(value, ChannelSelection.a, enabled: true),
          ) &&
          ble.writes.any(
            (value) => _isRelayTest(value, ChannelSelection.b, enabled: true),
          ),
    );

    ble.sendNotification('device-1', _channelPacket(ChannelSelection.a, 2));
    await _waitUntil(
      () =>
          container
              .read(appControllerProvider)
              .sessions['device-1:a']
              ?.status ==
          GameStatus.countdown,
    );
    final aTestCount = ble.writes
        .where(
          (value) => _isRelayTest(value, ChannelSelection.a, enabled: true),
        )
        .length;
    final bTestCount = ble.writes
        .where(
          (value) => _isRelayTest(value, ChannelSelection.b, enabled: true),
        )
        .length;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(
      ble.writes
          .where(
            (value) => _isRelayTest(value, ChannelSelection.a, enabled: true),
          )
          .length,
      greaterThan(aTestCount),
    );
    expect(
      ble.writes
          .where(
            (value) => _isRelayTest(value, ChannelSelection.b, enabled: true),
          )
          .length,
      greaterThan(bTestCount),
    );
    expect(
      ble.writes.any(
        (value) => _isRelayTest(value, ChannelSelection.a, enabled: false),
      ),
      isFalse,
    );

    await _waitUntil(
      () =>
          container
              .read(appControllerProvider)
              .sessions['device-1:a']
              ?.status ==
          GameStatus.running,
      timeout: const Duration(seconds: 3),
    );
    expect(
      ble.writes.any(
        (value) => _isRelayTest(value, ChannelSelection.a, enabled: false),
      ),
      isTrue,
    );

    await controller.stopAll(reason: '测试结束');
    container.dispose();
  });

  test('手动开始可以绕过电极状态上报并启动指定通道', () async {
    final ble = _FakeBleAdapter();
    final container = ProviderContainer(
      overrides: [
        bleAdapterProvider.overrideWithValue(ble),
        databaseProvider.overrideWithValue(_FakeDatabase()),
        countdownVoicePlayerProvider.overrideWithValue(
          _FakeCountdownVoicePlayer(),
        ),
      ],
    );
    final controller = container.read(appControllerProvider.notifier);
    await _waitUntil(() => container.read(appControllerProvider).initialized);

    const device = DiscoveredDevice(
      id: 'device-1',
      name: 'YYC-DJ-V2-001',
      rssi: -45,
      advertisedServices: <String>{UniversalBleAdapter.serviceUuid},
      protocol: DeviceProtocol.emsV2,
    );
    await controller.connect(device, DeviceProtocol.emsV2);
    await controller.startRelay(<EmsGameConfig>[
      _relayConfig(ChannelSelection.a, 'A 玩家'),
      _relayConfig(ChannelSelection.b, 'B 玩家'),
    ]);

    controller.startRelaySessionManually('device-1:a');

    expect(
      container.read(appControllerProvider).sessions['device-1:a']?.status,
      GameStatus.countdown,
    );
    expect(
      container.read(appControllerProvider).sessions['device-1:b']?.status,
      GameStatus.ready,
    );
    await _waitUntil(
      () =>
          container
              .read(appControllerProvider)
              .sessions['device-1:a']
              ?.status ==
          GameStatus.running,
      timeout: const Duration(seconds: 4),
    );

    await controller.stopAll(reason: '测试结束');
    container.dispose();
  });

  test('心动体验模式跳过倒计时并从强度 1 开始递增', () async {
    final ble = _FakeBleAdapter();
    final voice = _FakeCountdownVoicePlayer();
    final container = ProviderContainer(
      overrides: [
        bleAdapterProvider.overrideWithValue(ble),
        databaseProvider.overrideWithValue(_FakeDatabase()),
        countdownVoicePlayerProvider.overrideWithValue(voice),
      ],
    );
    final controller = container.read(appControllerProvider.notifier);
    await _waitUntil(() => container.read(appControllerProvider).initialized);

    const device = DiscoveredDevice(
      id: 'device-1',
      name: 'YYC-DJ-V2-001',
      rssi: -45,
      advertisedServices: <String>{UniversalBleAdapter.serviceUuid},
      protocol: DeviceProtocol.emsV2,
    );
    await controller.connect(device, DeviceProtocol.emsV2);
    controller.setDeviceGameRole('device-1', DeviceGameRole.couple);
    await controller.startRelay(<EmsGameConfig>[
      _experienceRelayConfig(
        ChannelSelection.a,
        'A 体验位',
        durationSeconds: 5,
        maxStrength: 3,
        increaseBy: 2,
      ),
      _experienceRelayConfig(
        ChannelSelection.b,
        'B 体验位',
        durationSeconds: 5,
        maxStrength: 3,
        increaseBy: 2,
      ),
    ], experienceMode: true);

    ble.sendNotification('device-1', _channelPacket(ChannelSelection.a, 2));
    await _waitUntil(
      () =>
          container
              .read(appControllerProvider)
              .sessions['device-1:a']
              ?.status ==
          GameStatus.running,
    );
    expect(voice.cuesFor('device-1:a'), isEmpty);
    await _waitUntil(
      () =>
          container
              .read(appControllerProvider)
              .sessions['device-1:a']
              ?.targetStrengthA ==
          1,
    );
    await _waitUntil(
      () =>
          container
              .read(appControllerProvider)
              .sessions['device-1:a']
              ?.targetStrengthA ==
          3,
      timeout: const Duration(seconds: 2),
    );
    await Future<void>.delayed(const Duration(milliseconds: 4300));

    final running = container
        .read(appControllerProvider)
        .sessions['device-1:a']!;
    expect(running.status, GameStatus.running);
    expect(running.elapsedMs, greaterThan(5000));
    expect(running.targetStrengthA, 3);

    // 已超过配置时长时，体验模式仍允许不结束游戏直接更新配置。
    await controller.updateRelayConfigs(<EmsGameConfig>[
      _experienceRelayConfig(
        ChannelSelection.a,
        'A 体验位',
        durationSeconds: 5,
        maxStrength: 3,
        increaseBy: 2,
      ),
      _experienceRelayConfig(
        ChannelSelection.b,
        'B 体验位',
        durationSeconds: 5,
        maxStrength: 3,
        increaseBy: 2,
      ),
    ]);
    // 页面只提交参数；下一次刷新仍需保留不限时模式。
    await _waitUntil(
      () =>
          (container
                  .read(appControllerProvider)
                  .sessions['device-1:a']
                  ?.elapsedMs ??
              0) >
          running.elapsedMs,
    );
    expect(
      container.read(appControllerProvider).sessions['device-1:a']?.status,
      GameStatus.running,
    );

    await controller.stopAll(reason: '测试结束');
    container.dispose();
  });
  test('运行中更新配置保留当前会话并立即使用新强度规则', () async {
    final ble = _FakeBleAdapter();
    final container = ProviderContainer(
      overrides: [
        bleAdapterProvider.overrideWithValue(ble),
        databaseProvider.overrideWithValue(_FakeDatabase()),
        countdownVoicePlayerProvider.overrideWithValue(
          _FakeCountdownVoicePlayer(),
        ),
      ],
    );
    final controller = container.read(appControllerProvider.notifier);
    await _waitUntil(() => container.read(appControllerProvider).initialized);

    const device = DiscoveredDevice(
      id: 'device-1',
      name: 'YYC-DJ-V2-001',
      rssi: -45,
      advertisedServices: <String>{UniversalBleAdapter.serviceUuid},
      protocol: DeviceProtocol.emsV2,
    );
    await controller.connect(device, DeviceProtocol.emsV2);
    controller.setDeviceGameRole('device-1', DeviceGameRole.couple);
    await controller.startRelay(<EmsGameConfig>[
      _dynamicRelayConfig(ChannelSelection.a, 'A 等待位'),
      _dynamicRelayConfig(ChannelSelection.b, 'B 等待位'),
    ], experienceMode: true);

    ble.sendNotification('device-1', _channelPacket(ChannelSelection.a, 2));
    await _waitUntil(
      () =>
          container
              .read(appControllerProvider)
              .sessions['device-1:a']
              ?.status ==
          GameStatus.running,
    );
    await _waitUntil(
      () =>
          (container
                  .read(appControllerProvider)
                  .sessions['device-1:a']
                  ?.targetStrengthA ??
              0) >=
          1,
    );
    final before = container
        .read(appControllerProvider)
        .sessions['device-1:a']!;
    await Future<void>.delayed(const Duration(milliseconds: 150));

    await controller.updateRelayConfigs(<EmsGameConfig>[
      _dynamicRelayConfig(
        ChannelSelection.a,
        'A 等待位',
        startStrength: 8,
        increaseBy: 2,
      ),
      _dynamicRelayConfig(
        ChannelSelection.b,
        'B 等待位',
        startStrength: 8,
        increaseBy: 2,
      ),
    ], experienceMode: true);

    final updated = container
        .read(appControllerProvider)
        .sessions['device-1:a']!;
    expect(updated.status, GameStatus.running);
    expect(updated.config.challengerName, before.config.challengerName);
    expect(updated.elapsedMs, greaterThanOrEqualTo(before.elapsedMs));
    expect(
      updated.maximumStrengthA,
      greaterThanOrEqualTo(before.maximumStrengthA),
    );
    expect(updated.config.channelA.startStrength, 8);
    expect(updated.config.channelA.increaseBy, 2);
    await _waitUntil(
      () =>
          (container
                  .read(appControllerProvider)
                  .sessions['device-1:a']
                  ?.targetStrengthA ??
              0) >=
          8,
    );

    await controller.stopAll(reason: '测试结束');
    container.dispose();
  });

  test('竞技设备选中体验预设仍保留倒计时', () async {
    final ble = _FakeBleAdapter();
    final container = ProviderContainer(
      overrides: [
        bleAdapterProvider.overrideWithValue(ble),
        databaseProvider.overrideWithValue(_FakeDatabase()),
        countdownVoicePlayerProvider.overrideWithValue(
          _FakeCountdownVoicePlayer(),
        ),
      ],
    );
    final controller = container.read(appControllerProvider.notifier);
    await _waitUntil(() => container.read(appControllerProvider).initialized);

    const device = DiscoveredDevice(
      id: 'device-1',
      name: 'YYC-DJ-V2-001',
      rssi: -45,
      advertisedServices: <String>{UniversalBleAdapter.serviceUuid},
      protocol: DeviceProtocol.emsV2,
    );
    await controller.connect(device, DeviceProtocol.emsV2);
    await controller.startRelay(<EmsGameConfig>[
      _experienceRelayConfig(ChannelSelection.a, 'A 体验位'),
      _experienceRelayConfig(ChannelSelection.b, 'B 体验位'),
    ], experienceMode: true);

    ble.sendNotification('device-1', _channelPacket(ChannelSelection.a, 2));
    await _waitUntil(
      () =>
          container
              .read(appControllerProvider)
              .sessions['device-1:a']
              ?.status ==
          GameStatus.countdown,
    );

    await controller.stopAll(reason: '测试结束');
    container.dispose();
  });

  test('双通道擂台按电极接入分别开始，A 失败不影响 B', () async {
    final ble = _FakeBleAdapter();
    final database = _FakeDatabase();
    final voice = _FakeCountdownVoicePlayer();
    final container = ProviderContainer(
      overrides: [
        bleAdapterProvider.overrideWithValue(ble),
        databaseProvider.overrideWithValue(database),
        countdownVoicePlayerProvider.overrideWithValue(voice),
      ],
    );
    final controller = container.read(appControllerProvider.notifier);
    await _waitUntil(() => container.read(appControllerProvider).initialized);

    const device = DiscoveredDevice(
      id: 'device-1',
      name: 'YYC-DJ-V2-001',
      rssi: -45,
      advertisedServices: <String>{UniversalBleAdapter.serviceUuid},
      protocol: DeviceProtocol.emsV2,
    );
    await controller.connect(device, DeviceProtocol.emsV2);
    await controller.startRelay(<EmsGameConfig>[
      _relayConfig(ChannelSelection.a, 'A 玩家'),
      _relayConfig(ChannelSelection.b, 'B 玩家'),
    ]);

    ble.sendNotification('device-1', _channelPacket(ChannelSelection.a, 2));
    ble.sendNotification('device-1', _channelPacket(ChannelSelection.b, 2));
    await _waitUntil(
      () =>
          container
                  .read(appControllerProvider)
                  .sessions['device-1:a']
                  ?.status ==
              GameStatus.countdown &&
          container
                  .read(appControllerProvider)
                  .sessions['device-1:b']
                  ?.status ==
              GameStatus.countdown,
    );
    expect(
      container
          .read(appControllerProvider)
          .sessions['device-1:a']
          ?.countdownSeconds,
      3,
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(
      container.read(appControllerProvider).sessions['device-1:a']?.status,
      GameStatus.countdown,
    );
    expect(
      container
          .read(appControllerProvider)
          .sessions['device-1:a']
          ?.targetStrengthA,
      0,
    );
    await _waitUntil(
      () =>
          container
                  .read(appControllerProvider)
                  .sessions['device-1:a']
                  ?.status ==
              GameStatus.running &&
          container
                  .read(appControllerProvider)
                  .sessions['device-1:b']
                  ?.status ==
              GameStatus.running,
      timeout: const Duration(seconds: 2),
    );
    expect(voice.cuesFor('device-1:a'), <CountdownVoiceCue>[
      CountdownVoiceCue.three,
      CountdownVoiceCue.two,
      CountdownVoiceCue.one,
      CountdownVoiceCue.go,
    ]);

    ble.sendNotification('device-1', _channelPacket(ChannelSelection.a, 0));
    await _waitUntil(
      () =>
          container
              .read(appControllerProvider)
              .sessions['device-1:a']
              ?.status ==
          GameStatus.failed,
      timeout: const Duration(seconds: 2),
    );

    final state = container.read(appControllerProvider);
    expect(state.sessions['device-1:b']?.status, GameStatus.running);
    expect(state.sessions['device-1:a']?.config.challengerName, '玩家1');
    expect(state.sessions['device-1:b']?.config.challengerName, '玩家2');
    expect(database.records.single.challengerName, '玩家1');

    await controller.stopAll(reason: '测试结束');
    container.dispose();
  });

  test('结果展示十秒后进入排行榜，断开再接入后开启下一轮', () async {
    final ble = _FakeBleAdapter();
    final database = _FakeDatabase();
    final container = ProviderContainer(
      overrides: [
        bleAdapterProvider.overrideWithValue(ble),
        databaseProvider.overrideWithValue(database),
        countdownVoicePlayerProvider.overrideWithValue(
          _FakeCountdownVoicePlayer(),
        ),
      ],
    );
    final controller = container.read(appControllerProvider.notifier);
    await _waitUntil(() => container.read(appControllerProvider).initialized);

    const device = DiscoveredDevice(
      id: 'device-1',
      name: 'YYC-DJ-V2-001',
      rssi: -45,
      advertisedServices: <String>{UniversalBleAdapter.serviceUuid},
      protocol: DeviceProtocol.emsV2,
    );
    await controller.connect(device, DeviceProtocol.emsV2);
    await controller.startRelay(<EmsGameConfig>[
      _relayConfig(ChannelSelection.a, 'A 玩家'),
      _relayConfig(ChannelSelection.b, 'B 玩家'),
    ]);

    ble.sendNotification('device-1', _channelPacket(ChannelSelection.a, 2));
    await _waitUntil(
      () =>
          container
              .read(appControllerProvider)
              .sessions['device-1:a']
              ?.status ==
          GameStatus.countdown,
    );
    await _waitUntil(
      () =>
          container
              .read(appControllerProvider)
              .sessions['device-1:a']
              ?.status ==
          GameStatus.running,
      timeout: const Duration(seconds: 4),
    );
    ble.sendNotification('device-1', _channelPacket(ChannelSelection.a, 0));
    await _waitUntil(
      () =>
          container
              .read(appControllerProvider)
              .sessions['device-1:a']
              ?.status ==
          GameStatus.failed,
      timeout: const Duration(seconds: 2),
    );

    final revision = container.read(appControllerProvider).leaderboardRevision;
    await Future<void>.delayed(const Duration(seconds: 9));
    expect(
      container.read(appControllerProvider).sessions['device-1:a']?.status,
      GameStatus.failed,
    );
    expect(container.read(appControllerProvider).leaderboardRevision, revision);
    await _waitUntil(
      () =>
          container.read(appControllerProvider).leaderboardRevision > revision,
      timeout: const Duration(seconds: 3),
    );
    expect(
      container.read(appControllerProvider).sessions['device-1:a']?.status,
      GameStatus.ready,
    );

    final liveRevision = container
        .read(appControllerProvider)
        .liveDisplayRevision;
    ble.sendNotification('device-1', _channelPacket(ChannelSelection.a, 2));
    await _waitUntil(
      () =>
          container
              .read(appControllerProvider)
              .sessions['device-1:a']
              ?.status ==
          GameStatus.countdown,
    );
    await _waitUntil(
      () =>
          container
              .read(appControllerProvider)
              .sessions['device-1:a']
              ?.status ==
          GameStatus.running,
      timeout: const Duration(seconds: 4),
    );
    expect(
      container.read(appControllerProvider).liveDisplayRevision,
      greaterThan(liveRevision),
    );
    expect(
      container
          .read(appControllerProvider)
          .sessions['device-1:a']
          ?.config
          .challengerName,
      '玩家2',
    );
    expect(database.records, hasLength(1));

    await controller.stopAll(reason: '测试结束');
    container.dispose();
  });

  test('心动挑战完成后同一通道断开再接通可开启下一轮', () async {
    final ble = _FakeBleAdapter();
    final container = ProviderContainer(
      overrides: [
        bleAdapterProvider.overrideWithValue(ble),
        databaseProvider.overrideWithValue(_FakeDatabase()),
        countdownVoicePlayerProvider.overrideWithValue(
          _FakeCountdownVoicePlayer(),
        ),
      ],
    );
    final controller = container.read(appControllerProvider.notifier);
    await _waitUntil(() => container.read(appControllerProvider).initialized);

    const device = DiscoveredDevice(
      id: 'device-1',
      name: 'YYC-DJ-V2-001',
      rssi: -45,
      advertisedServices: <String>{UniversalBleAdapter.serviceUuid},
      protocol: DeviceProtocol.emsV2,
    );
    await controller.connect(
      device,
      DeviceProtocol.emsV2,
      gameRole: DeviceGameRole.couple,
    );
    await controller.startRelay(<EmsGameConfig>[
      _relayConfig(ChannelSelection.a, '心动 A'),
      _relayConfig(ChannelSelection.b, '心动 B'),
    ]);

    ble.sendNotification('device-1', _channelPacket(ChannelSelection.a, 2));
    await _waitUntil(
      () =>
          container
              .read(appControllerProvider)
              .sessions['device-1:a']
              ?.status ==
          GameStatus.running,
      timeout: const Duration(seconds: 4),
    );
    await controller.stopSession(
      'device-1:a',
      ChallengeResult.success,
      reason: '挑战完成',
    );

    // 结算期间完成一次真实的断开再接通，结果页结束后应自动开始下一局。
    ble.sendNotification('device-1', _channelPacket(ChannelSelection.a, 0));
    ble.sendNotification('device-1', _channelPacket(ChannelSelection.a, 2));
    await _waitUntil(
      () =>
          container
              .read(appControllerProvider)
              .sessions['device-1:a']
              ?.status ==
          GameStatus.countdown,
      timeout: const Duration(seconds: 12),
    );
    expect(
      container
          .read(appControllerProvider)
          .sessions['device-1:a']
          ?.config
          .challengerName,
      '玩家2',
    );
    await _waitUntil(
      () =>
          container
              .read(appControllerProvider)
              .sessions['device-1:a']
              ?.status ==
          GameStatus.running,
      timeout: const Duration(seconds: 4),
    );
    expect(
      container.read(appControllerProvider).sessions['device-1:b']?.status,
      GameStatus.ready,
    );

    await controller.stopAll(reason: '测试结束');
    container.dispose();
  });
  test('通道结束后提高电极断开状态查询频率', () async {
    final ble = _FakeBleAdapter();
    final database = _FakeDatabase();
    final container = ProviderContainer(
      overrides: [
        bleAdapterProvider.overrideWithValue(ble),
        databaseProvider.overrideWithValue(database),
        countdownVoicePlayerProvider.overrideWithValue(
          _FakeCountdownVoicePlayer(),
        ),
      ],
    );
    final controller = container.read(appControllerProvider.notifier);
    await _waitUntil(() => container.read(appControllerProvider).initialized);

    const device = DiscoveredDevice(
      id: 'device-1',
      name: 'YYC-DJ-V2-001',
      rssi: -45,
      advertisedServices: <String>{UniversalBleAdapter.serviceUuid},
      protocol: DeviceProtocol.emsV2,
    );
    await controller.connect(device, DeviceProtocol.emsV2);
    await controller.startRelay(<EmsGameConfig>[
      _relayConfig(ChannelSelection.a, 'A 玩家'),
      _relayConfig(ChannelSelection.b, 'B 玩家'),
    ]);

    ble.sendNotification('device-1', _channelPacket(ChannelSelection.a, 2));
    ble.sendNotification('device-1', _channelPacket(ChannelSelection.b, 2));
    await _waitUntil(
      () =>
          container
                  .read(appControllerProvider)
                  .sessions['device-1:a']
                  ?.status ==
              GameStatus.running &&
          container
                  .read(appControllerProvider)
                  .sessions['device-1:b']
                  ?.status ==
              GameStatus.running,
      timeout: const Duration(seconds: 4),
    );
    await controller.stopSession(
      'device-1:a',
      ChallengeResult.aborted,
      reason: '用户终止 A 通道',
    );

    final queryCount = ble.writes
        .where((value) => _isChannelQuery(value, ChannelSelection.a))
        .length;
    await Future<void>.delayed(const Duration(milliseconds: 750));
    final increasedQueryCount = ble.writes
        .where((value) => _isChannelQuery(value, ChannelSelection.a))
        .length;
    expect(increasedQueryCount - queryCount, greaterThanOrEqualTo(2));
    expect(
      container.read(appControllerProvider).sessions['device-1:b']?.status,
      GameStatus.running,
    );

    await controller.stopAll(reason: '测试结束');
    container.dispose();
  });

  test('支持同时连接多台电击器', () async {
    final container = ProviderContainer(
      overrides: [
        bleAdapterProvider.overrideWithValue(_FakeBleAdapter()),
        databaseProvider.overrideWithValue(_FakeDatabase()),
        countdownVoicePlayerProvider.overrideWithValue(
          _FakeCountdownVoicePlayer(),
        ),
      ],
    );
    final controller = container.read(appControllerProvider.notifier);
    await _waitUntil(() => container.read(appControllerProvider).initialized);

    const first = DiscoveredDevice(
      id: 'device-1',
      name: 'YYC-DJ-V2-001',
      rssi: -45,
      advertisedServices: <String>{UniversalBleAdapter.serviceUuid},
      protocol: DeviceProtocol.emsV2,
    );
    const second = DiscoveredDevice(
      id: 'device-2',
      name: 'YYC-DJ-V2-002',
      rssi: -50,
      advertisedServices: <String>{UniversalBleAdapter.serviceUuid},
      protocol: DeviceProtocol.emsV2,
    );
    await controller.connect(first, DeviceProtocol.emsV2);
    await controller.connect(second, DeviceProtocol.emsV2);

    expect(
      container.read(appControllerProvider).devices.keys,
      unorderedEquals(<String>['device-1', 'device-2']),
    );
    container.dispose();
  });

  test('已经连接一台设备后仍可继续扫描其他设备', () async {
    final ble = _FakeBleAdapter();
    final container = ProviderContainer(
      overrides: [
        bleAdapterProvider.overrideWithValue(ble),
        databaseProvider.overrideWithValue(_FakeDatabase()),
        countdownVoicePlayerProvider.overrideWithValue(
          _FakeCountdownVoicePlayer(),
        ),
      ],
    );
    final controller = container.read(appControllerProvider.notifier);
    await _waitUntil(() => container.read(appControllerProvider).initialized);

    const device = DiscoveredDevice(
      id: 'device-1',
      name: 'YYC-DJ-V2-001',
      rssi: -45,
      advertisedServices: <String>{UniversalBleAdapter.serviceUuid},
      protocol: DeviceProtocol.emsV2,
    );
    await controller.connect(device, DeviceProtocol.emsV2);
    await controller.startScan();

    expect(ble.startScanCalls, 1);
    expect(container.read(appControllerProvider).isScanning, isTrue);

    await controller.stopScan();
    container.dispose();
  });

  test('不同设备互斥触发，同一设备 A/B 可以同时开始', () async {
    final ble = _FakeBleAdapter();
    final container = ProviderContainer(
      overrides: [
        bleAdapterProvider.overrideWithValue(ble),
        databaseProvider.overrideWithValue(_FakeDatabase()),
        countdownVoicePlayerProvider.overrideWithValue(
          _FakeCountdownVoicePlayer(),
        ),
      ],
    );
    final controller = container.read(appControllerProvider.notifier);
    await _waitUntil(() => container.read(appControllerProvider).initialized);

    const first = DiscoveredDevice(
      id: 'device-1',
      name: 'YYC-DJ-V2-001',
      rssi: -45,
      advertisedServices: <String>{UniversalBleAdapter.serviceUuid},
      protocol: DeviceProtocol.emsV2,
    );
    const second = DiscoveredDevice(
      id: 'device-2',
      name: 'YYC-DJ-V2-002',
      rssi: -50,
      advertisedServices: <String>{UniversalBleAdapter.serviceUuid},
      protocol: DeviceProtocol.emsV2,
    );
    await controller.connect(first, DeviceProtocol.emsV2);
    await controller.connect(second, DeviceProtocol.emsV2);
    await controller.startRelay(<EmsGameConfig>[
      _relayConfig(ChannelSelection.a, '设备1 A'),
      _relayConfig(ChannelSelection.b, '设备1 B'),
      _relayConfig(ChannelSelection.a, '设备2 A', deviceId: 'device-2'),
      _relayConfig(ChannelSelection.b, '设备2 B', deviceId: 'device-2'),
    ]);

    ble.sendNotification('device-1', _channelPacket(ChannelSelection.a, 2));
    ble.sendNotification('device-2', _channelPacket(ChannelSelection.a, 2));
    ble.sendNotification('device-1', _channelPacket(ChannelSelection.b, 2));
    await _waitUntil(() {
      final sessions = container.read(appControllerProvider).sessions;
      return sessions['device-1:a']?.status == GameStatus.countdown &&
          sessions['device-1:b']?.status == GameStatus.countdown;
    });
    expect(
      container.read(appControllerProvider).sessions['device-2:a']?.status,
      GameStatus.ready,
    );

    ble.sendNotification('device-1', _channelPacket(ChannelSelection.a, 0));
    ble.sendNotification('device-1', _channelPacket(ChannelSelection.b, 0));
    await _waitUntil(
      () =>
          container
              .read(appControllerProvider)
              .sessions['device-2:a']
              ?.status ==
          GameStatus.countdown,
    );

    await controller.stopAll(reason: '测试结束');
    container.dispose();
  });

  test('情侣设备 A/B 同时接入时只启动先形成回路的通道', () async {
    final ble = _FakeBleAdapter();
    final container = ProviderContainer(
      overrides: [
        bleAdapterProvider.overrideWithValue(ble),
        databaseProvider.overrideWithValue(_FakeDatabase()),
        countdownVoicePlayerProvider.overrideWithValue(
          _FakeCountdownVoicePlayer(),
        ),
      ],
    );
    final controller = container.read(appControllerProvider.notifier);
    await _waitUntil(() => container.read(appControllerProvider).initialized);

    const device = DiscoveredDevice(
      id: 'device-1',
      name: 'YYC-DJ-V2-001',
      rssi: -45,
      advertisedServices: <String>{UniversalBleAdapter.serviceUuid},
      protocol: DeviceProtocol.emsV2,
    );
    await controller.connect(device, DeviceProtocol.emsV2);
    controller.setDeviceGameRole('device-1', DeviceGameRole.couple);
    await controller.startRelay(<EmsGameConfig>[
      _relayConfig(ChannelSelection.a, '设备1 A'),
      _relayConfig(ChannelSelection.b, '设备1 B'),
    ]);

    // 情侣模式由先接入的通道取得本局执行权，另一通道继续等待。
    ble.sendNotification('device-1', _channelPacket(ChannelSelection.a, 2));
    ble.sendNotification('device-1', _channelPacket(ChannelSelection.b, 2));
    await _waitUntil(
      () =>
          container
              .read(appControllerProvider)
              .sessions['device-1:a']
              ?.status ==
          GameStatus.countdown,
    );

    final state = container.read(appControllerProvider);
    expect(state.sessions['device-1:a']?.status, GameStatus.countdown);
    expect(state.sessions['device-1:b']?.status, GameStatus.ready);
    expect(state.activeRelayDeviceId, 'device-1');

    await controller.stopAll(reason: '测试结束');
    container.dispose();
  });

  test('倒计时期间电极断开会取消开始且不保存记录', () async {
    final ble = _FakeBleAdapter();
    final database = _FakeDatabase();
    final voice = _FakeCountdownVoicePlayer();
    final container = ProviderContainer(
      overrides: [
        bleAdapterProvider.overrideWithValue(ble),
        databaseProvider.overrideWithValue(database),
        countdownVoicePlayerProvider.overrideWithValue(voice),
      ],
    );
    final controller = container.read(appControllerProvider.notifier);
    await _waitUntil(() => container.read(appControllerProvider).initialized);

    const device = DiscoveredDevice(
      id: 'device-1',
      name: 'YYC-DJ-V2-001',
      rssi: -45,
      advertisedServices: <String>{UniversalBleAdapter.serviceUuid},
      protocol: DeviceProtocol.emsV2,
    );
    await controller.connect(device, DeviceProtocol.emsV2);
    await controller.startRelay(<EmsGameConfig>[
      _relayConfig(ChannelSelection.a, 'A 玩家'),
      _relayConfig(ChannelSelection.b, 'B 玩家'),
    ]);

    ble.sendNotification('device-1', _channelPacket(ChannelSelection.a, 2));
    await _waitUntil(
      () =>
          container
              .read(appControllerProvider)
              .sessions['device-1:a']
              ?.status ==
          GameStatus.countdown,
    );
    ble.sendNotification('device-1', _channelPacket(ChannelSelection.a, 0));
    await _waitUntil(
      () =>
          container
              .read(appControllerProvider)
              .sessions['device-1:a']
              ?.status ==
          GameStatus.ready,
    );
    expect(database.records, isEmpty);
    expect(voice.stoppedSessions, contains('device-1:a'));

    await controller.stopAll(reason: '测试结束');
    container.dispose();
  });

  test('A/B 参数不一致时禁止启动', () async {
    final container = ProviderContainer(
      overrides: [
        bleAdapterProvider.overrideWithValue(_FakeBleAdapter()),
        databaseProvider.overrideWithValue(_FakeDatabase()),
        countdownVoicePlayerProvider.overrideWithValue(
          _FakeCountdownVoicePlayer(),
        ),
      ],
    );
    final controller = container.read(appControllerProvider.notifier);
    await _waitUntil(() => container.read(appControllerProvider).initialized);

    const device = DiscoveredDevice(
      id: 'device-1',
      name: 'YYC-DJ-V2-001',
      rssi: -45,
      advertisedServices: <String>{UniversalBleAdapter.serviceUuid},
      protocol: DeviceProtocol.emsV2,
    );
    await controller.connect(device, DeviceProtocol.emsV2);

    await expectLater(
      controller.startRelay(<EmsGameConfig>[
        _relayConfig(ChannelSelection.a, 'A 玩家'),
        _relayConfig(ChannelSelection.b, 'B 玩家', maximumStrength: 70),
      ]),
      throwsA(isA<ArgumentError>()),
    );
    container.dispose();
  });

  test('不同游戏职责允许使用不同配置', () async {
    final container = ProviderContainer(
      overrides: [
        bleAdapterProvider.overrideWithValue(_FakeBleAdapter()),
        databaseProvider.overrideWithValue(_FakeDatabase()),
        countdownVoicePlayerProvider.overrideWithValue(
          _FakeCountdownVoicePlayer(),
        ),
      ],
    );
    final controller = container.read(appControllerProvider.notifier);
    await _waitUntil(() => container.read(appControllerProvider).initialized);

    const arenaDevice = DiscoveredDevice(
      id: 'device-1',
      name: '竞技设备',
      rssi: -45,
      advertisedServices: <String>{UniversalBleAdapter.serviceUuid},
      protocol: DeviceProtocol.emsV2,
    );
    const heartDevice = DiscoveredDevice(
      id: 'device-2',
      name: '心动设备',
      rssi: -50,
      advertisedServices: <String>{UniversalBleAdapter.serviceUuid},
      protocol: DeviceProtocol.emsV2,
    );
    await controller.connect(arenaDevice, DeviceProtocol.emsV2);
    await controller.connect(
      heartDevice,
      DeviceProtocol.emsV2,
      gameRole: DeviceGameRole.couple,
    );

    await controller.startRelay(<EmsGameConfig>[
      _relayConfig(ChannelSelection.a, '竞技 A'),
      _relayConfig(ChannelSelection.b, '竞技 B'),
      _relayConfig(
        ChannelSelection.a,
        '心动 A',
        deviceId: 'device-2',
        maximumStrength: 20,
      ),
      _relayConfig(
        ChannelSelection.b,
        '心动 B',
        deviceId: 'device-2',
        maximumStrength: 20,
      ),
    ], experienceMode: true);

    final sessions = container.read(appControllerProvider).sessions;
    expect(sessions['device-1:a']?.config.channelA.maxStrength, 60);
    expect(sessions['device-2:a']?.config.channelA.maxStrength, 20);

    await controller.stopAll(reason: '测试结束');
    container.dispose();
  });
  test('连接后定时查询电量，设备上报后立即更新', () async {
    final ble = _FakeBleAdapter();
    final container = ProviderContainer(
      overrides: [
        bleAdapterProvider.overrideWithValue(ble),
        databaseProvider.overrideWithValue(_FakeDatabase()),
        countdownVoicePlayerProvider.overrideWithValue(
          _FakeCountdownVoicePlayer(),
        ),
      ],
    );
    final controller = container.read(appControllerProvider.notifier);
    await _waitUntil(() => container.read(appControllerProvider).initialized);

    const device = DiscoveredDevice(
      id: 'device-1',
      name: 'YYC-DJ-V2-001',
      rssi: -45,
      advertisedServices: <String>{UniversalBleAdapter.serviceUuid},
      protocol: DeviceProtocol.emsV2,
    );
    await controller.connect(device, DeviceProtocol.emsV2);
    final initialQueries = ble.writes.where(_isBatteryQuery).length;

    ble.sendNotification(
      'device-1',
      Uint8List.fromList(<int>[0x35, 0x71, 0x04, 80, 0xfa]),
    );
    await _waitUntil(
      () =>
          container
              .read(appControllerProvider)
              .devices['device-1']
              ?.telemetry
              .batteryPercent ==
          80,
    );
    expect(
      container
          .read(appControllerProvider)
          .devices['device-1']
          ?.telemetry
          .batteryStale,
      isFalse,
    );
    await _waitUntil(
      () => ble.writes.where(_isBatteryQuery).length > initialQueries,
      timeout: const Duration(seconds: 3),
    );

    container.dispose();
  });

  test('首页开始游戏为所有设备使用同一套默认预设', () async {
    final ble = _FakeBleAdapter();
    final container = ProviderContainer(
      overrides: [
        bleAdapterProvider.overrideWithValue(ble),
        databaseProvider.overrideWithValue(_FakeDatabase()),
        countdownVoicePlayerProvider.overrideWithValue(
          _FakeCountdownVoicePlayer(),
        ),
      ],
    );
    final controller = container.read(appControllerProvider.notifier);
    await _waitUntil(() => container.read(appControllerProvider).initialized);

    const device = DiscoveredDevice(
      id: 'device-1',
      name: 'YYC-DJ-V2-001',
      rssi: -45,
      advertisedServices: <String>{UniversalBleAdapter.serviceUuid},
      protocol: DeviceProtocol.emsV2,
    );
    const secondDevice = DiscoveredDevice(
      id: 'device-2',
      name: 'YYC-DJ-V2-002',
      rssi: -50,
      advertisedServices: <String>{UniversalBleAdapter.serviceUuid},
      protocol: DeviceProtocol.emsV2,
    );
    await controller.connect(device, DeviceProtocol.emsV2);
    await controller.connect(secondDevice, DeviceProtocol.emsV2);
    await controller.startDefaultRelay();

    final state = container.read(appControllerProvider);
    final preset = GamePresetStore.builtIns.firstWhere(
      (item) => item.id == GamePresetStore.defaultPresetId,
    );
    expect(state.relayModeActive, isTrue);
    expect(state.sessions.length, 4);
    expect(
      state.sessions.values.map((session) => session.config.deviceId).toSet(),
      <String>{'device-1', 'device-2'},
    );
    await _waitUntil(
      () => ble.writes.any(_isAnyChannelQuery),
      timeout: const Duration(seconds: 1),
    );
    for (final session in state.sessions.values) {
      final channel = session.config.channels == ChannelSelection.a
          ? session.config.channelA
          : session.config.channelB;
      expect(session.config.durationSeconds, preset.durationSeconds);
      expect(channel.startStrength, preset.startStrength);
      expect(channel.maxStrength, preset.maxStrength);
      expect(channel.increaseEverySeconds, preset.increaseEverySeconds);
      expect(channel.increaseBy, preset.increaseBy);
      expect(channel.waveformId, preset.waveformId);
    }

    await controller.stopAll(reason: '测试结束');
    container.dispose();
  });

  test('首次通道查询未返回时自动检测仍能启动', () async {
    final ble = _FakeBleAdapter();
    final container = ProviderContainer(
      overrides: [
        bleAdapterProvider.overrideWithValue(ble),
        databaseProvider.overrideWithValue(_FakeDatabase()),
        countdownVoicePlayerProvider.overrideWithValue(
          _FakeCountdownVoicePlayer(),
        ),
      ],
    );
    final controller = container.read(appControllerProvider.notifier);
    await _waitUntil(() => container.read(appControllerProvider).initialized);

    const device = DiscoveredDevice(
      id: 'device-1',
      name: 'YYC-DJ-V2-001',
      rssi: -45,
      advertisedServices: <String>{UniversalBleAdapter.serviceUuid},
      protocol: DeviceProtocol.emsV2,
    );
    await controller.connect(device, DeviceProtocol.emsV2);
    final queryGate = Completer<void>();
    ble.channelQueryGate = queryGate;

    await controller.startDefaultRelay().timeout(
      const Duration(milliseconds: 500),
    );
    final state = container.read(appControllerProvider);
    expect(state.relayModeActive, isTrue);
    expect(state.sessions, hasLength(2));

    queryGate.complete();
    ble.channelQueryGate = null;
    await controller.stopAll(reason: '测试结束');
    container.dispose();
  });
}

bool _isBatteryQuery(Uint8List value) =>
    value.length == 4 &&
    value[0] == 0x35 &&
    value[1] == 0x71 &&
    value[2] == 0x04;

bool _isChannelQuery(Uint8List value, ChannelSelection channel) =>
    value.length == 4 &&
    value[0] == 0x35 &&
    value[1] == 0x71 &&
    value[2] == channel.protocolValue;

bool _isAnyChannelQuery(Uint8List value) =>
    _isChannelQuery(value, ChannelSelection.a) ||
    _isChannelQuery(value, ChannelSelection.b);

bool _isRelayTest(
  Uint8List value,
  ChannelSelection channel, {
  required bool enabled,
}) =>
    value.length == 9 &&
    value[0] == 0x35 &&
    value[1] == 0x11 &&
    value[2] == 0x03 &&
    value[3] == channel.protocolValue &&
    value[4] == 0x00 &&
    value[5] == (enabled ? 0x01 : 0x00) &&
    value[6] == 0x11 &&
    value[7] == 0x01;

EmsGameConfig _relayConfig(
  ChannelSelection channel,
  String name, {
  int maximumStrength = 60,
  String deviceId = 'device-1',
}) => EmsGameConfig(
  challengerName: name,
  deviceId: deviceId,
  protocol: DeviceProtocol.emsV2,
  channels: channel,
  durationSeconds: 30,
  channelA: ChannelGameConfig(
    startStrength: 10,
    maxStrength: maximumStrength,
    increaseEverySeconds: 10,
    increaseBy: 5,
    waveformId: WaveformCatalog.presets.first.id,
  ),
  channelB: ChannelGameConfig(
    startStrength: 10,
    maxStrength: maximumStrength,
    increaseEverySeconds: 10,
    increaseBy: 5,
    waveformId: WaveformCatalog.presets.first.id,
  ),
  channelsLinked: false,
);

EmsGameConfig _experienceRelayConfig(
  ChannelSelection channel,
  String name, {
  int durationSeconds = 60,
  int maxStrength = 20,
  int increaseBy = 1,
}) => EmsGameConfig(
  challengerName: name,
  deviceId: 'device-1',
  protocol: DeviceProtocol.emsV2,
  channels: channel,
  durationSeconds: durationSeconds,
  channelA: ChannelGameConfig(
    startStrength: 1,
    maxStrength: maxStrength,
    increaseEverySeconds: 1,
    increaseBy: increaseBy,
    waveformId: smoothRampWaveformId,
  ),
  channelB: ChannelGameConfig(
    startStrength: 1,
    maxStrength: maxStrength,
    increaseEverySeconds: 1,
    increaseBy: increaseBy,
    waveformId: smoothRampWaveformId,
  ),
  channelsLinked: false,
);

EmsGameConfig _dynamicRelayConfig(
  ChannelSelection channel,
  String name, {
  int startStrength = 1,
  int increaseBy = 1,
}) {
  final channelConfig = ChannelGameConfig(
    startStrength: startStrength,
    maxStrength: 20,
    increaseEverySeconds: 1,
    increaseBy: increaseBy,
    waveformId: smoothRampWaveformId,
  );
  return EmsGameConfig(
    challengerName: name,
    deviceId: 'device-1',
    protocol: DeviceProtocol.emsV2,
    channels: channel,
    durationSeconds: 60,
    channelA: channelConfig,
    channelB: channelConfig,
    channelsLinked: false,
  );
}

Uint8List _channelPacket(ChannelSelection channel, int electrode) {
  final body = <int>[
    0x35,
    0x71,
    channel.protocolValue,
    electrode,
    electrode == 0 ? 0 : 1,
    0,
    0,
    0x11,
  ];
  return Uint8List.fromList(<int>[
    ...body,
    body.fold(0, (sum, value) => (sum + value) & 0xff),
  ]);
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > timeout) throw TimeoutException('等待状态更新超时');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _FakeCountdownVoicePlayer implements CountdownVoicePlayer {
  final List<(String sessionId, CountdownVoiceCue cue)> played =
      <(String sessionId, CountdownVoiceCue cue)>[];
  final Set<String> stoppedSessions = <String>{};

  List<CountdownVoiceCue> cuesFor(String sessionId) => played
      .where((entry) => entry.$1 == sessionId)
      .map((entry) => entry.$2)
      .toList(growable: false);

  @override
  Future<void> play(String sessionId, CountdownVoiceCue cue) async {
    played.add((sessionId, cue));
  }

  @override
  Future<void> stop(String sessionId) async {
    stoppedSessions.add(sessionId);
  }

  @override
  Future<void> stopAll() async {}

  @override
  Future<void> dispose() async {}
}

class _FakeDatabase extends AppDatabase {
  final List<ChallengeRecord> records = <ChallengeRecord>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> replaceBuiltInWaveforms(List<EmsWaveform> waveforms) async {}

  @override
  Future<List<EmsWaveform>> loadWaveforms() async => WaveformCatalog.presets;

  @override
  Future<List<ChallengeRecord>> loadChallenges() async => [...records];

  @override
  Future<void> saveChallenge(ChallengeRecord record) async =>
      records.add(record);

  @override
  Future<DeviceProtocol?> protocolFor(String deviceId) async => null;

  @override
  Future<void> saveProtocol(String deviceId, DeviceProtocol protocol) async {}

  @override
  Future<void> close() async {}
}

class _FakeBleAdapter implements BleAdapter {
  final availability = StreamController<BleAvailability>.broadcast();
  final scans = StreamController<BleScanResult>.broadcast();
  final connections = StreamController<BleConnectionEvent>.broadcast();
  final notificationController = StreamController<BleNotification>.broadcast();
  final List<Uint8List> writes = <Uint8List>[];
  Completer<void>? channelQueryGate;
  int startScanCalls = 0;

  @override
  Stream<BleAvailability> get availabilityChanges => availability.stream;

  @override
  Stream<BleScanResult> get scanResults => scans.stream;

  @override
  Stream<BleConnectionEvent> get connectionEvents => connections.stream;

  @override
  Stream<BleNotification> get notifications => notificationController.stream;

  @override
  Future<BleAvailability> getAvailability() async => BleAvailability.poweredOn;

  @override
  Future<void> requestPermissions() async {}

  @override
  Future<void> startScan() async {
    startScanCalls++;
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(String deviceId) async {}

  @override
  Future<void> disconnect(String deviceId) async {}

  @override
  Future<List<BleService>> discoverServices(String deviceId) async =>
      const <BleService>[
        BleService(
          uuid: UniversalBleAdapter.serviceUuid,
          characteristics: <BleCharacteristic>[
            BleCharacteristic(
              uuid: UniversalBleAdapter.writeUuid,
              writeWithResponse: false,
              writeWithoutResponse: true,
              notify: false,
              indicate: false,
            ),
            BleCharacteristic(
              uuid: UniversalBleAdapter.notifyUuid,
              writeWithResponse: false,
              writeWithoutResponse: false,
              notify: true,
              indicate: false,
            ),
          ],
        ),
      ];

  @override
  Future<void> subscribe(String deviceId) async {}

  @override
  Future<void> write(
    String deviceId,
    Uint8List value, {
    required bool withResponse,
  }) async {
    writes.add(Uint8List.fromList(value));
    if (_isAnyChannelQuery(value)) await channelQueryGate?.future;
  }

  void sendNotification(String deviceId, Uint8List value) {
    notificationController.add(
      BleNotification(deviceId: deviceId, value: value),
    );
  }

  @override
  Future<void> dispose() async {
    await availability.close();
    await scans.close();
    await connections.close();
    await notificationController.close();
  }
}
