import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yokonex_ems_game/app/app_controller.dart';
import 'package:yokonex_ems_game/app/pages/game_page.dart';
import 'package:yokonex_ems_game/app/visual_style.dart';
import 'package:yokonex_ems_game/core/model/models.dart';
import 'package:yokonex_ems_game/features/waveforms/waveform_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final testCase in <({Size size, GameVisualStyle style, String label})>[
    (
      size: const Size(390, 844),
      style: GameVisualStyle.scoreboard,
      label: '竞技计分台移动端',
    ),
    (
      size: const Size(1280, 800),
      style: GameVisualStyle.arcade,
      label: '街机电流场 Windows',
    ),
  ]) {
    testWidgets('${testCase.label}无布局溢出', (tester) async {
      tester.view.physicalSize = testCase.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final state = _fixtureState();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appControllerProvider.overrideWith(() => _FakeAppController(state)),
            gameVisualStyleProvider.overrideWith(
              () => _FakeVisualStyleController(testCase.style),
            ),
          ],
          child: MaterialApp(
            theme: buildGameTheme(testCase.style),
            home: const GamePage(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('玩家1'), findsWidgets);
      expect(find.byTooltip('调整配置'), findsOneWidget);
      expect(find.text('终止挑战'), findsOneWidget);
      expect(find.byTooltip('终止 A 通道'), findsOneWidget);
      expect(find.byTooltip('终止 B 通道'), findsOneWidget);
      expect(find.text('终止 A'), findsOneWidget);
      expect(find.text('终止 B'), findsOneWidget);
      if (testCase.size.width >= 620) {
        expect(find.text('全部紧急停止'), findsOneWidget);
      }
      expect(find.text('目标强度'), findsNothing);
      expect(find.text('实时强度'), findsNWidgets(2));
      expect(find.text('游戏时间'), findsNWidgets(2));
      expect(find.text('实时电量'), findsNothing);
      expect(find.text('剩余'), findsNothing);
      expect(find.text('YYC-DJ-100'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('challenge-pyramid-device-1:a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('running-energy-device-1:a')),
        findsOneWidget,
      );
      expect(find.text('忍着！你是小孩子吗？'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('无人挑战时在结算页滚动展示排行榜', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fixture = _fixtureState();
    final waitingState = AppState(
      initialized: true,
      relayModeActive: true,
      devices: fixture.devices,
      sessions: <String, GameSessionState>{
        for (final entry in fixture.sessions.entries)
          entry.key: entry.value.copyWith(
            status: GameStatus.ready,
            elapsedMs: 0,
          ),
      },
      records: <ChallengeRecord>[
        _recordForSession(fixture.sessions.values.first),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _FakeAppController(waitingState),
          ),
          gameVisualStyleProvider.overrideWith(
            () => _FakeVisualStyleController(GameVisualStyle.scoreboard),
          ),
        ],
        child: MaterialApp(
          theme: buildGameTheme(GameVisualStyle.scoreboard),
          home: const GamePage(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('本轮结算'), findsOneWidget);
    expect(find.text('荣耀排行榜'), findsOneWidget);
    expect(find.text('玩家1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('running-energy-device-1:a')),
      findsNothing,
    );

    await tester.tap(find.text('荣耀排行榜'));
    await tester.pump();
    expect(find.text('抓住左侧单杠开始游戏'), findsOneWidget);
    expect(find.text('抓住右侧单杠开始游戏'), findsOneWidget);
    expect(find.text('手动开始 A'), findsOneWidget);
    expect(find.text('手动开始 B'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('等待状态可以手动开始指定通道', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = _fixtureState();
    final waitingState = fixture.copyWith(
      relayModeActive: true,
      sessions: <String, GameSessionState>{
        for (final entry in fixture.sessions.entries)
          entry.key: entry.value.copyWith(status: GameStatus.ready),
      },
    );
    final controller = _FakeAppController(waitingState);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(() => controller),
          gameVisualStyleProvider.overrideWith(
            () => _FakeVisualStyleController(GameVisualStyle.scoreboard),
          ),
        ],
        child: const MaterialApp(home: GamePage()),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('荣耀排行榜'));
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey<String>('manual-start-device-1:a')),
    );
    await tester.pump();

    expect(controller.manuallyStartedSessionId, 'device-1:a');
  });

  testWidgets('多设备运行时页面只展示当前设备的 A/B', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _multiDeviceFixtureState();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(() => _FakeAppController(state)),
          gameVisualStyleProvider.overrideWith(
            () => _FakeVisualStyleController(GameVisualStyle.arcade),
          ),
        ],
        child: MaterialApp(
          theme: buildGameTheme(GameVisualStyle.arcade),
          home: const GamePage(),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('challenge-pyramid-device-1:a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('challenge-pyramid-device-1:b')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('challenge-pyramid-device-2:a')),
      findsNothing,
    );
    expect(find.text('实时强度'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('终止挑战后返回首屏', (tester) async {
    final controller = _FakeAppController(_fixtureState());
    final router = GoRouter(
      initialLocation: '/game',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('首屏')),
        ),
        GoRoute(path: '/game', builder: (_, _) => const GamePage()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(() => controller),
          gameVisualStyleProvider.overrideWith(
            () => _FakeVisualStyleController(GameVisualStyle.scoreboard),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('终止挑战'));
    await tester.pumpAndSettle();

    expect(controller.stopped, isTrue);
    expect(find.text('首屏'), findsOneWidget);
  });

  testWidgets('可以单独终止 A 通道且不离开游戏页', (tester) async {
    final controller = _FakeAppController(_fixtureState());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(() => controller),
          gameVisualStyleProvider.overrideWith(
            () => _FakeVisualStyleController(GameVisualStyle.scoreboard),
          ),
        ],
        child: const MaterialApp(home: GamePage()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('终止 A 通道'));
    await tester.pump();

    expect(controller.stoppedSessionId, 'device-1:a');
    expect(controller.stoppedSessionResult, ChallengeResult.aborted);
    expect(find.byTooltip('终止 B 通道'), findsOneWidget);
  });

  testWidgets('游戏结束后弹出当前排名动画', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fixture = _fixtureState();
    final firstEntry = fixture.sessions.entries.first;
    final completedSession = firstEntry.value.copyWith(
      status: GameStatus.success,
      elapsedMs: firstEntry.value.config.durationSeconds * 1000,
      maximumStrengthA: 180,
    );
    final state = AppState(
      initialized: true,
      relayModeActive: true,
      devices: fixture.devices,
      sessions: <String, GameSessionState>{
        ...fixture.sessions,
        firstEntry.key: completedSession,
      },
      records: <ChallengeRecord>[
        ChallengeRecord(
          id: 'record-player-1',
          challengerName: completedSession.config.challengerName,
          configFingerprint: completedSession.config.fingerprint,
          configJson: '{}',
          protocol: completedSession.config.protocol,
          channels: completedSession.config.channels,
          result: ChallengeResult.success,
          elapsedMs: completedSession.elapsedMs,
          maximumStrengthA: 180,
          maximumStrengthB: 0,
          finalStrengthA: 180,
          finalStrengthB: 0,
          startedAt: DateTime(2026, 8, 26, 12),
          finishedAt: DateTime(2026, 8, 26, 12, 1),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(() => _FakeAppController(state)),
          gameVisualStyleProvider.overrideWith(
            () => _FakeVisualStyleController(GameVisualStyle.arcade),
          ),
        ],
        child: MaterialApp(
          theme: buildGameTheme(GameVisualStyle.arcade),
          home: const GamePage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('挑战成功'), findsOneWidget);
    expect(find.text('当前排名'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('settlement-rank')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

AppState _fixtureState() {
  const deviceId = 'device-1';
  final device = ConnectedDeviceState(
    id: deviceId,
    name: 'YYC-DJ-100',
    protocol: DeviceProtocol.emsV2,
    telemetry: const DeviceTelemetry(
      batteryPercent: 90,
      reportedStrengthA: 70,
      reportedStrengthB: 64,
      electrodeA: ElectrodeState.discharging,
      electrodeB: ElectrodeState.discharging,
    ),
  );
  final sessions = <String, GameSessionState>{};
  for (var index = 0; index < 2; index++) {
    final channel = index == 0 ? ChannelSelection.a : ChannelSelection.b;
    final config = EmsGameConfig(
      challengerName: '玩家${index + 1}',
      deviceId: deviceId,
      protocol: DeviceProtocol.emsV2,
      channels: channel,
      durationSeconds: 300,
      channelA: ChannelGameConfig(
        startStrength: 10,
        maxStrength: 120,
        increaseEverySeconds: 10,
        increaseBy: 5,
        waveformId: WaveformCatalog.presets.first.id,
      ),
      channelB: ChannelGameConfig(
        startStrength: 8,
        maxStrength: 100,
        increaseEverySeconds: 10,
        increaseBy: 4,
        waveformId: WaveformCatalog.presets[1].id,
      ),
      channelsLinked: false,
    );
    sessions['$deviceId:${channel.name}'] = GameSessionState(
      config: config,
      status: GameStatus.running,
      elapsedMs: 100000 + index * 24000,
      targetStrengthA: 70,
      targetStrengthB: 64,
    );
  }
  return AppState(
    initialized: true,
    devices: <String, ConnectedDeviceState>{deviceId: device},
    sessions: sessions,
  );
}

AppState _multiDeviceFixtureState() {
  final first = _fixtureState();
  const secondDeviceId = 'device-2';
  final sessions = <String, GameSessionState>{...first.sessions};
  for (final entry in first.sessions.values) {
    final config = entry.config;
    final channel = config.channels;
    sessions['$secondDeviceId:${channel.name}'] = GameSessionState(
      config: EmsGameConfig(
        challengerName: '${channel.label}通道等待位',
        deviceId: secondDeviceId,
        protocol: config.protocol,
        channels: channel,
        durationSeconds: config.durationSeconds,
        channelA: config.channelA,
        channelB: config.channelB,
        channelsLinked: false,
      ),
      status: GameStatus.ready,
    );
  }
  return first.copyWith(
    relayModeActive: true,
    devices: <String, ConnectedDeviceState>{
      ...first.devices,
      secondDeviceId: const ConnectedDeviceState(
        id: secondDeviceId,
        name: 'YYC-DJ-200',
        protocol: DeviceProtocol.emsV2,
      ),
    },
    sessions: sessions,
  );
}

ChallengeRecord _recordForSession(GameSessionState session) => ChallengeRecord(
  id: 'record-${session.config.channels.name}',
  challengerName: session.config.challengerName,
  configFingerprint: session.config.fingerprint,
  configJson: '{}',
  protocol: session.config.protocol,
  channels: session.config.channels,
  result: ChallengeResult.success,
  elapsedMs: 60000,
  maximumStrengthA: 90,
  maximumStrengthB: 0,
  finalStrengthA: 90,
  finalStrengthB: 0,
  startedAt: DateTime(2026, 8, 26, 12),
  finishedAt: DateTime(2026, 8, 26, 12, 1),
);

class _FakeAppController extends AppController {
  _FakeAppController(this.initialState);

  final AppState initialState;
  bool stopped = false;
  String? stoppedSessionId;
  ChallengeResult? stoppedSessionResult;
  String? manuallyStartedSessionId;

  @override
  AppState build() => initialState;

  @override
  Future<void> stopAll({
    ChallengeResult result = ChallengeResult.aborted,
    String reason = '全部挑战已停止',
  }) async {
    stopped = true;
  }

  @override
  Future<void> stopSession(
    String sessionId,
    ChallengeResult result, {
    required String reason,
  }) async {
    stoppedSessionId = sessionId;
    stoppedSessionResult = result;
  }

  @override
  void startRelaySessionManually(String sessionId) {
    manuallyStartedSessionId = sessionId;
  }
}

class _FakeVisualStyleController extends GameVisualStyleController {
  _FakeVisualStyleController(this.initialStyle);

  final GameVisualStyle initialStyle;

  @override
  GameVisualStyle build() => initialStyle;

  @override
  Future<void> setStyle(GameVisualStyle style) async => state = style;
}
