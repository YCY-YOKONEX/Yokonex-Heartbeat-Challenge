import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yokonex_ems_game/app/app_controller.dart';
import 'package:yokonex_ems_game/app/pages/home_page.dart';
import 'package:yokonex_ems_game/core/model/models.dart';

void main() {
  testWidgets('排行榜只展示前十五位，点击榜单返回游戏页', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/leaderboard',
      routes: <RouteBase>[
        GoRoute(
          path: '/leaderboard',
          builder: (_, _) => const LeaderboardPage(),
        ),
        GoRoute(
          path: '/game',
          builder: (_, _) => const Scaffold(body: Text('游戏页面')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _FakeAppController(
              AppState(
                initialized: true,
                relayModeActive: true,
                records: _records(20),
              ),
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    expect(find.text('荣耀排行榜'), findsOneWidget);
    expect(find.text('TOP 15'), findsOneWidget);
    expect(find.text('#1'), findsWidgets);
    expect(find.byType(Card), findsNothing);
    await tester.scrollUntilVisible(
      find.text('玩家15'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('玩家15'), findsOneWidget);
    expect(find.text('玩家16'), findsNothing);
    expect(tester.takeException(), isNull);

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).last,
    );
    scrollable.position.jumpTo(0);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      scrollable.position.pixels,
      closeTo(scrollable.position.viewportDimension, 1),
    );

    await tester.tap(find.text('荣耀排行榜'));
    await tester.pumpAndSettle();
    expect(find.text('游戏页面'), findsOneWidget);
  });

  testWidgets('排行榜检测到通道玩家后自动返回实时页', (tester) async {
    final controller = _FakeAppController(
      AppState(
        initialized: true,
        relayModeActive: true,
        sessions: <String, GameSessionState>{
          'device-1:a': GameSessionState(
            config: _sessionConfig(),
            status: GameStatus.ready,
          ),
        },
      ),
    );
    final router = GoRouter(
      initialLocation: '/leaderboard',
      routes: <RouteBase>[
        GoRoute(
          path: '/leaderboard',
          builder: (_, _) => const LeaderboardPage(),
        ),
        GoRoute(
          path: '/game',
          builder: (_, _) => const Scaffold(body: Text('游戏页面')),
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
    expect(find.text('荣耀排行榜'), findsOneWidget);

    controller.connectPlayer();
    await tester.pumpAndSettle();
    expect(find.text('游戏页面'), findsOneWidget);
  });
}

List<ChallengeRecord> _records(int count) => List<ChallengeRecord>.generate(
  count,
  (index) => ChallengeRecord(
    id: 'record-$index',
    challengerName: '玩家${index + 1}',
    configFingerprint: 'same-config',
    configJson: '{"durationSeconds":60}',
    protocol: DeviceProtocol.emsV2,
    channels: ChannelSelection.a,
    result: ChallengeResult.success,
    elapsedMs: (count - index) * 1000,
    maximumStrengthA: 30,
    maximumStrengthB: 0,
    finalStrengthA: 30,
    finalStrengthB: 0,
    startedAt: DateTime(2026, 8, 26, 12),
    finishedAt: DateTime(2026, 8, 26, 12, index),
  ),
);

class _FakeAppController extends AppController {
  _FakeAppController(this.initialState);

  final AppState initialState;

  @override
  AppState build() => initialState;

  void connectPlayer() {
    state = state.copyWith(
      sessions: <String, GameSessionState>{
        for (final entry in state.sessions.entries)
          entry.key: entry.value.copyWith(status: GameStatus.countdown),
      },
      liveDisplayRevision: state.liveDisplayRevision + 1,
    );
  }
}

EmsGameConfig _sessionConfig() => const EmsGameConfig(
  challengerName: 'A 通道等待位',
  deviceId: 'device-1',
  protocol: DeviceProtocol.emsV2,
  channels: ChannelSelection.a,
  durationSeconds: 60,
  channelA: ChannelGameConfig(
    startStrength: 30,
    maxStrength: 180,
    increaseEverySeconds: 1,
    increaseBy: 2,
    waveformId: 'smooth-ramp',
  ),
  channelB: ChannelGameConfig(
    startStrength: 30,
    maxStrength: 180,
    increaseEverySeconds: 1,
    increaseBy: 2,
    waveformId: 'smooth-ramp',
  ),
  channelsLinked: false,
);
