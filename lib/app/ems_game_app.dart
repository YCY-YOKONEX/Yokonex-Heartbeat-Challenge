import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yokonex_ems_game/app/app_controller.dart';
import 'package:yokonex_ems_game/app/desktop_window_controller.dart';
import 'package:yokonex_ems_game/app/pages/couple_game_page.dart';
import 'package:yokonex_ems_game/app/pages/game_page.dart';
import 'package:yokonex_ems_game/app/pages/landing_page.dart';
import 'package:yokonex_ems_game/app/pages/result_page.dart';
import 'package:yokonex_ems_game/app/visual_style.dart';
import 'package:yokonex_ems_game/features/game/game_preset.dart';

class EmsGameApp extends ConsumerStatefulWidget {
  const EmsGameApp({super.key}) : heartExperienceOnly = false;

  const EmsGameApp.heartExperience({super.key}) : heartExperienceOnly = true;

  final bool heartExperienceOnly;

  @override
  ConsumerState<EmsGameApp> createState() => _EmsGameAppState();
}

class _EmsGameAppState extends ConsumerState<EmsGameApp>
    with WidgetsBindingObserver {
  late final GoRouter _router = GoRouter(
    routes: widget.heartExperienceOnly
        ? <RouteBase>[
            GoRoute(
              path: '/',
              builder: (context, state) =>
                  const GameSettingsPage(heartExperienceOnly: true),
            ),
            GoRoute(
              path: '/settings',
              builder: (context, state) =>
                  const GameSettingsPage(heartExperienceOnly: true),
            ),
            GoRoute(
              path: '/leaderboard',
              builder: (context, state) => const GameLeaderboardPage(),
            ),
            GoRoute(
              path: '/couple-game',
              builder: (context, state) =>
                  const CoupleGamePage(standaloneExperience: true),
            ),
          ]
        : <RouteBase>[
            GoRoute(
              path: '/',
              builder: (context, state) => const GameLandingPage(),
            ),
            GoRoute(
              path: '/settings',
              builder: (context, state) =>
                  GameSettingsPage(initialCategory: _categoryFromRoute(state)),
            ),
            GoRoute(
              path: '/leaderboard',
              builder: (context, state) => const GameLeaderboardPage(),
            ),
            GoRoute(
              path: '/game',
              builder: (context, state) => const GamePage(),
            ),
            GoRoute(
              path: '/couple-game',
              builder: (context, state) => const CoupleGamePage(),
            ),
            GoRoute(
              path: '/result',
              builder: (context, state) => const ResultPage(),
            ),
          ],
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(ref.read(appControllerProvider.notifier).handleAppBackground());
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(desktopWindowControllerProvider);
    final visualStyle = ref.watch(gameVisualStyleProvider);
    return MaterialApp.router(
      title: widget.heartExperienceOnly ? '心动体验' : '耐久挑战',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: buildGameTheme(visualStyle),
      themeAnimationDuration: const Duration(milliseconds: 180),
    );
  }
}

GamePresetCategory _categoryFromRoute(GoRouterState state) {
  final name = state.uri.queryParameters['game'];
  for (final category in GamePresetCategory.values) {
    if (category.name == name) return category;
  }
  return GamePresetCategory.endurance;
}
