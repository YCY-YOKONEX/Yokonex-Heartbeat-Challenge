import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yokonex_ems_game/app/app_controller.dart';
import 'package:yokonex_ems_game/app/pages/couple_game_page.dart';
import 'package:yokonex_ems_game/app/pages/game_page.dart';
import 'package:yokonex_ems_game/core/model/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in <Size>[const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('心动挑战进行中在 ${size.width.toInt()} 宽度展示爱心动画', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = _FakeAppController(_coupleState());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith(() => controller)],
          child: const MaterialApp(home: CoupleGamePage()),
        ),
      );
      await tester.pump();

      expect(find.text('心动挑战'), findsOneWidget);
      expect(find.text('游戏时间'), findsOneWidget);
      expect(find.text('实时强度'), findsOneWidget);
      expect(find.text('坚持住，让爱心慢慢亮满'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('couple-challenge-running')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('couple-scene')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('couple-dogs-heart')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('couple-dogs-illustration')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('stop-couple-game')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('couple-running-parameters')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in <Size>[const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('独立体验在 ${size.width.toInt()} 宽度同时展示双通道信息', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appControllerProvider.overrideWith(
              () => _FakeAppController(_coupleState()),
            ),
          ],
          child: const MaterialApp(
            home: CoupleGamePage(standaloneExperience: true),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('双通道状态'), findsOneWidget);
      expect(find.text('A 通道'), findsOneWidget);
      expect(find.text('B 通道'), findsOneWidget);
      expect(find.text('实时强度'), findsNWidgets(2));
      expect(find.text('游戏时间'), findsNWidgets(2));
      expect(find.text('起始强度'), findsNWidgets(2));
      expect(find.text('强度上限'), findsNWidgets(2));
      expect(find.text('递增规则'), findsNWidgets(2));
      expect(find.text('当前波形'), findsNWidgets(2));
      expect(find.text('waveform-1'), findsNWidgets(2));
      expect(find.text('18'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('experience-channel-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('experience-channel-b')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('couple-running-parameters')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('couple-challenge-running')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('couple-dogs-illustration')),
        findsNothing,
      );
      expect(find.text('结束本次体验'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('心动挑战接通后进入倒计时场景', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _FakeAppController(
              _coupleState(status: GameStatus.countdown, elapsedMs: 0),
            ),
          ),
        ],
        child: const MaterialApp(home: CoupleGamePage()),
      ),
    );
    await tester.pump();

    expect(find.text('心动挑战'), findsOneWidget);
    expect(find.text('心动倒计时'), findsOneWidget);
    expect(find.text('别松手，我们马上出发'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('couple-scene')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('couple-hold-hands-prompt')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('情侣页结束后显示结算排名和成绩', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _FakeAppController(
              _coupleState(status: GameStatus.success, elapsedMs: 60000),
            ),
          ),
        ],
        child: const MaterialApp(home: CoupleGamePage()),
      ),
    );
    await tester.pump();

    expect(find.text('本轮结算'), findsOneWidget);
    expect(find.text('心动挑战成功'), findsOneWidget);
    expect(find.text('当前排名'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('挑战时长'), findsOneWidget);
    expect(find.text('最高强度'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('couple-settlement-rank')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('couple-dogs-illustration')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('等待时显示双人触摸动画和文字提示', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _FakeAppController(
              _coupleState(
                status: GameStatus.ready,
                elapsedMs: 0,
                electrodeA: ElectrodeState.detached,
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: CoupleGamePage(standaloneExperience: true),
        ),
      ),
    );
    await tester.pump();

    final prompt = find.byKey(const ValueKey<String>('couple-touch-prompt'));
    final touch = find.byKey(const ValueKey<String>('couple-touch-animation'));
    expect(prompt, findsOneWidget);
    expect(touch, findsOneWidget);
    expect(find.text('等待触摸'), findsOneWidget);
    expect(find.text('请两位玩家触摸'), findsOneWidget);
    expect(find.text('触摸接通后自动开始'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('couple-running-parameters')),
      findsNothing,
    );
    final before = tester.widget<CustomPaint>(touch).painter;
    await tester.pump(const Duration(milliseconds: 400));
    final after = tester.widget<CustomPaint>(touch).painter;
    expect(after, isNot(same(before)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('挑战版等待时保留双人牵手动画', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _FakeAppController(
              _coupleState(
                status: GameStatus.ready,
                elapsedMs: 0,
                electrodeA: ElectrodeState.detached,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: CoupleGamePage()),
      ),
    );
    await tester.pump();

    final hands = find.byKey(
      const ValueKey<String>('couple-people-hold-hands-animation'),
    );
    expect(find.text('心动牵手'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('couple-hold-hands-prompt')),
      findsOneWidget,
    );
    expect(hands, findsOneWidget);
    expect(find.text('请两位玩家牵手'), findsOneWidget);
    expect(find.text('接通回路后自动开始'), findsOneWidget);
    expect(find.text('牵起手，心动就会开始'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('couple-touch-animation')),
      findsNothing,
    );
    final before = tester.widget<CustomPaint>(hands).painter;
    await tester.pump(const Duration(milliseconds: 400));
    final after = tester.widget<CustomPaint>(hands).painter;
    expect(after, isNot(same(before)));
    expect(tester.takeException(), isNull);
  });
  testWidgets('情侣职责形成回路后从竞技页跳到情侣页', (tester) async {
    final router = GoRouter(
      initialLocation: '/game',
      routes: <RouteBase>[
        GoRoute(path: '/game', builder: (_, _) => const GamePage()),
        GoRoute(
          path: '/couple-game',
          builder: (_, _) => const CoupleGamePage(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _FakeAppController(_coupleState()),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('心动挑战'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('couple-challenge-running')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

AppState _coupleState({
  GameStatus status = GameStatus.running,
  int elapsedMs = 24000,
  ElectrodeState electrodeA = ElectrodeState.discharging,
}) {
  const deviceId = 'couple-device';
  const channelConfig = ChannelGameConfig(
    startStrength: 1,
    maxStrength: 60,
    increaseEverySeconds: 10,
    increaseBy: 5,
    waveformId: 'waveform-1',
  );
  final activeConfig = EmsGameConfig(
    challengerName: '玩家1',
    deviceId: deviceId,
    protocol: DeviceProtocol.emsV2,
    channels: ChannelSelection.a,
    durationSeconds: 60,
    channelA: channelConfig,
    channelB: channelConfig,
    channelsLinked: false,
  );
  final waitingConfig = EmsGameConfig(
    challengerName: 'B 通道等待位',
    deviceId: deviceId,
    protocol: DeviceProtocol.emsV2,
    channels: ChannelSelection.b,
    durationSeconds: 60,
    channelA: activeConfig.channelA,
    channelB: activeConfig.channelB,
    channelsLinked: false,
  );
  final completed =
      status == GameStatus.success ||
      status == GameStatus.failed ||
      status == GameStatus.aborted ||
      status == GameStatus.error;
  final record = ChallengeRecord(
    id: '$deviceId:a-record',
    challengerName: activeConfig.challengerName,
    configFingerprint: activeConfig.fingerprint,
    configJson: '{}',
    protocol: activeConfig.protocol,
    channels: activeConfig.channels,
    result: status == GameStatus.success
        ? ChallengeResult.success
        : ChallengeResult.failed,
    elapsedMs: elapsedMs,
    maximumStrengthA: 18,
    maximumStrengthB: 0,
    finalStrengthA: 18,
    finalStrengthB: 0,
    startedAt: DateTime(2026, 9, 4, 12),
    finishedAt: DateTime(2026, 9, 4, 12, 1),
  );
  return AppState(
    initialized: true,
    relayModeActive: true,
    devices: <String, ConnectedDeviceState>{
      deviceId: ConnectedDeviceState(
        id: deviceId,
        name: '情侣设备',
        protocol: DeviceProtocol.emsV2,
        gameRole: DeviceGameRole.couple,
        telemetry: DeviceTelemetry(
          reportedStrengthA: 18,
          reportedStrengthB: 7,
          electrodeA: electrodeA,
          electrodeB: ElectrodeState.attachedIdle,
        ),
      ),
    },
    sessions: <String, GameSessionState>{
      '$deviceId:a': GameSessionState(
        config: activeConfig,
        status: status,
        elapsedMs: elapsedMs,
        targetStrengthA: 18,
        maximumStrengthA: 18,
      ),
      '$deviceId:b': GameSessionState(
        config: waitingConfig,
        status: GameStatus.ready,
      ),
    },
    records: completed ? <ChallengeRecord>[record] : const <ChallengeRecord>[],
    lastRecord: completed ? record : null,
  );
}

class _FakeAppController extends AppController {
  _FakeAppController(this.initialState);

  final AppState initialState;
  String? stoppedSessionId;

  @override
  AppState build() => initialState;

  @override
  Future<void> stopSession(
    String sessionId,
    ChallengeResult result, {
    required String reason,
  }) async {
    stoppedSessionId = sessionId;
  }
}
