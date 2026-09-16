import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yokonex_ems_game/app/app_controller.dart';
import 'package:yokonex_ems_game/app/pages/home_page.dart';
import 'package:yokonex_ems_game/app/pages/landing_page.dart';
import 'package:yokonex_ems_game/core/model/models.dart';
import 'package:yokonex_ems_game/features/game/game_preset.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('运行中重新打开自定义配置并应用时不覆盖游戏模式', (tester) async {
    const channel = ChannelGameConfig(
      startStrength: 1,
      maxStrength: 3,
      increaseEverySeconds: 1,
      increaseBy: 2,
      waveformId: smoothRampWaveformId,
    );
    final controller = _FakeAppController(
      AppState(
        initialized: true,
        relayModeActive: true,
        devices: const <String, ConnectedDeviceState>{
          'device-1': ConnectedDeviceState(
            id: 'device-1',
            name: 'YYC-DJ-V2-001',
            protocol: DeviceProtocol.emsV2,
            gameRole: DeviceGameRole.couple,
          ),
        },
        waveforms: const <EmsWaveform>[
          EmsWaveform(
            id: smoothRampWaveformId,
            name: '平缓渐强',
            steps: <WaveformStep>[
              WaveformStep(durationMs: 500, frequency: 30, pulseWidth: 100),
            ],
          ),
        ],
        sessions: <String, GameSessionState>{
          for (final selection in [ChannelSelection.a, ChannelSelection.b])
            'device-1:${selection.name}': GameSessionState(
              config: EmsGameConfig(
                challengerName: '玩家',
                deviceId: 'device-1',
                protocol: DeviceProtocol.emsV2,
                channels: selection,
                durationSeconds: 5,
                channelA: channel,
                channelB: channel,
                channelsLinked: false,
              ),
              status: selection == ChannelSelection.a
                  ? GameStatus.running
                  : GameStatus.ready,
              elapsedMs: selection == ChannelSelection.a ? 6000 : 0,
            ),
        },
      ),
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: GameSetupPage()),
        ),
        GoRoute(
          path: '/couple-game',
          builder: (_, _) => const Scaffold(body: Text('心动页')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith(() => controller)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.fling(find.byType(ListView), const Offset(0, -1000), 1000);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '应用配置'));
    await tester.pumpAndSettle();

    expect(controller.updatedConfigs, hasLength(2));
    expect(controller.updatedExperienceMode, isNull);
    expect(controller.updatedConfigs!.first.channelA.maxStrength, 3);
    expect(find.text('心动页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页展示开始游戏和心动挑战入口', (tester) async {
    final controller = _FakeAppController(const AppState(initialized: true));
    await _pumpLanding(tester, controller);

    expect(find.text('耐久挑战'), findsOneWidget);
    expect(find.text('开始游戏'), findsOneWidget);
    expect(find.text('心动挑战'), findsOneWidget);
    expect(find.text('排行榜'), findsOneWidget);
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(find.text('设备连接'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('网页小游戏首页在 Windows 尺寸无布局溢出', (tester) async {
    final controller = _FakeAppController(const AppState(initialized: true));
    await _pumpLanding(tester, controller, size: const Size(1280, 800));

    expect(find.text('耐久挑战'), findsOneWidget);
    expect(find.text('开始游戏'), findsOneWidget);
    expect(find.text('心动挑战'), findsOneWidget);
    expect(find.text('排行榜'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未连接设备时点击开始进入设置', (tester) async {
    final controller = _FakeAppController(const AppState(initialized: true));
    await _pumpLanding(tester, controller);

    await tester.tap(find.byKey(const ValueKey<String>('start-game')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('设置页'), findsOneWidget);
    expect(find.text('endurance'), findsOneWidget);
    expect(controller.defaultRelayStarted, isFalse);
  });

  testWidgets('已连接设备时点击开始也进入同一个设置页', (tester) async {
    final controller = _FakeAppController(
      const AppState(
        initialized: true,
        devices: <String, ConnectedDeviceState>{
          'device-1': ConnectedDeviceState(
            id: 'device-1',
            name: 'YYC-DJ-V2-001',
            protocol: DeviceProtocol.emsV2,
          ),
        },
      ),
    );
    await _pumpLanding(tester, controller);

    await tester.tap(find.byKey(const ValueKey<String>('start-game')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.defaultRelayStarted, isFalse);
    expect(find.text('设置页'), findsOneWidget);
    expect(find.text('endurance'), findsOneWidget);
  });

  testWidgets('点击排行榜进入排行榜页面', (tester) async {
    final controller = _FakeAppController(const AppState(initialized: true));
    await _pumpLanding(tester, controller);

    await tester.tap(find.byKey(const ValueKey<String>('open-leaderboard')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('排行榜页'), findsOneWidget);
  });

  testWidgets('点击心动挑战进入同一个设置页', (tester) async {
    final controller = _FakeAppController(const AppState(initialized: true));
    await _pumpLanding(tester, controller);

    await tester.tap(
      find.byKey(const ValueKey<String>('open-heart-experience')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('设置页'), findsOneWidget);
    expect(find.text('heart'), findsOneWidget);
    expect(controller.defaultRelayStarted, isFalse);
  });

  testWidgets('男生预设会预选心动挑战配置', (tester) async {
    final controller = _FakeAppController(
      const AppState(
        initialized: true,
        devices: <String, ConnectedDeviceState>{
          'device-1': ConnectedDeviceState(
            id: 'device-1',
            name: 'YYC-DJ-V2-001',
            protocol: DeviceProtocol.emsV2,
          ),
        },
        waveforms: <EmsWaveform>[
          EmsWaveform(
            id: smoothRampWaveformId,
            name: '平缓渐强',
            steps: <WaveformStep>[
              WaveformStep(durationMs: 500, frequency: 30, pulseWidth: 100),
            ],
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith(() => controller)],
        child: const MaterialApp(
          home: Scaffold(
            body: GameSetupPage(initialPresetId: GamePresetStore.malePresetId),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('男生'), findsOneWidget);
    final selector = tester.widget<SegmentedButton<GamePresetCategory>>(
      find.byKey(const ValueKey<String>('game-config-category')),
    );
    expect(selector.selected, <GamePresetCategory>{GamePresetCategory.heart});

    await tester.fling(find.byType(ListView), const Offset(0, -1000), 1000);
    await tester.pumpAndSettle();
    expect(find.text('启动全部设备检测'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('不同游戏分别使用对应配置', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _FakeAppController(
      const AppState(
        initialized: true,
        devices: <String, ConnectedDeviceState>{
          'device-1': ConnectedDeviceState(
            id: 'device-1',
            name: '竞技设备',
            protocol: DeviceProtocol.emsV2,
          ),
          'device-2': ConnectedDeviceState(
            id: 'device-2',
            name: '心动设备',
            protocol: DeviceProtocol.emsV2,
            gameRole: DeviceGameRole.couple,
          ),
        },
        waveforms: <EmsWaveform>[
          EmsWaveform(
            id: smoothRampWaveformId,
            name: '平缓渐强',
            steps: <WaveformStep>[
              WaveformStep(durationMs: 500, frequency: 30, pulseWidth: 100),
            ],
          ),
        ],
      ),
    );
    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: GameSetupPage()),
        ),
        GoRoute(
          path: '/couple-game',
          builder: (_, _) => const Scaffold(body: Text('游戏页')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith(() => controller)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('耐久挑战 · 1 台设备'), findsOneWidget);
    expect(find.text('默认挑战'), findsOneWidget);

    await tester.tap(find.text('心动挑战'));
    await tester.pumpAndSettle();

    expect(find.text('心动挑战 · 1 台设备'), findsOneWidget);
    expect(find.text('男生'), findsOneWidget);

    await tester.fling(find.byType(ListView), const Offset(0, -1000), 1000);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '启动全部设备检测'));
    await tester.pumpAndSettle();

    final configs = controller.startedConfigs!;
    final arenaConfig = configs.firstWhere(
      (config) =>
          config.deviceId == 'device-1' &&
          config.channels == ChannelSelection.a,
    );
    final heartConfig = configs.firstWhere(
      (config) =>
          config.deviceId == 'device-2' &&
          config.channels == ChannelSelection.a,
    );
    expect(arenaConfig.channelA.maxStrength, 90);
    expect(heartConfig.channelA.maxStrength, 20);
    expect(controller.startedExperienceMode, isFalse);
    expect(find.text('游戏页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('独立心动设置页保留完整入口', (tester) async {
    final controller = _FakeAppController(const AppState(initialized: true));
    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) => const GameSettingsPage(heartExperienceOnly: true),
        ),
        GoRoute(
          path: '/leaderboard',
          builder: (_, _) => const Scaffold(body: Text('体验记录页')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith(() => controller)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('心动体验'), findsOneWidget);
    expect(find.text('设备连接'), findsWidgets);
    expect(find.text('体验设置'), findsOneWidget);
    expect(find.byTooltip('体验记录'), findsOneWidget);
    expect(find.byTooltip('返回首页'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('独立心动设置使用任意配置都直接启用体验模式', (tester) async {
    final controller = _FakeAppController(
      const AppState(
        initialized: true,
        devices: <String, ConnectedDeviceState>{
          'device-1': ConnectedDeviceState(
            id: 'device-1',
            name: 'YYC-DJ-V2-001',
            protocol: DeviceProtocol.emsV2,
          ),
        },
        waveforms: <EmsWaveform>[
          EmsWaveform(
            id: smoothRampWaveformId,
            name: '平缓渐强',
            steps: <WaveformStep>[
              WaveformStep(durationMs: 500, frequency: 30, pulseWidth: 100),
            ],
          ),
        ],
      ),
    );
    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) =>
              const Scaffold(body: GameSetupPage(experienceOnly: true)),
        ),
        GoRoute(
          path: '/couple-game',
          builder: (_, _) => const Scaffold(body: Text('心动页')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith(() => controller)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.fling(find.byType(ListView), const Offset(0, -1000), 1000);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '启动心动体验'));
    await tester.pumpAndSettle();

    expect(controller.startedExperienceMode, isTrue);
    expect(controller.startedConfigs, hasLength(2));
    expect(
      controller.state.devices['device-1']?.gameRole,
      DeviceGameRole.couple,
    );
    expect(find.text('心动页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpLanding(
  WidgetTester tester,
  _FakeAppController controller, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const GameLandingPage()),
      GoRoute(
        path: '/settings',
        builder: (_, state) => Scaffold(
          body: Column(
            children: <Widget>[
              const Text('设置页'),
              Text(state.uri.queryParameters['game'] ?? ''),
            ],
          ),
        ),
      ),
      GoRoute(
        path: '/game',
        builder: (_, _) => const Scaffold(body: Text('游戏页')),
      ),
      GoRoute(
        path: '/couple-game',
        builder: (_, _) => const Scaffold(body: Text('心动页')),
      ),
      GoRoute(
        path: '/leaderboard',
        builder: (_, _) => const Scaffold(body: Text('排行榜页')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appControllerProvider.overrideWith(() => controller)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
}

class _FakeAppController extends AppController {
  _FakeAppController(this.initialState);

  final AppState initialState;
  bool defaultRelayStarted = false;
  List<EmsGameConfig>? startedConfigs;
  bool? startedExperienceMode;
  List<EmsGameConfig>? updatedConfigs;
  bool? updatedExperienceMode;

  @override
  Future<void> startRelay(
    List<EmsGameConfig> configs, {
    bool experienceMode = false,
  }) async {
    startedConfigs = configs;
    startedExperienceMode = experienceMode;
  }

  @override
  Future<void> updateRelayConfigs(
    List<EmsGameConfig> configs, {
    bool? experienceMode,
  }) async {
    updatedConfigs = configs;
    updatedExperienceMode = experienceMode;
  }

  @override
  AppState build() => initialState;

  @override
  Future<void> startDefaultRelay() async {
    defaultRelayStarted = true;
    state = initialState;
  }
}
