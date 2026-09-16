import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yokonex_ems_game/app/app_controller.dart';
import 'package:yokonex_ems_game/app/pages/home_page.dart';
import 'package:yokonex_ems_game/app/visual_style.dart';
import 'package:yokonex_ems_game/features/game/game_preset.dart';

class GameLandingPage extends ConsumerStatefulWidget {
  const GameLandingPage({super.key});

  @override
  ConsumerState<GameLandingPage> createState() => _GameLandingPageState();
}

class _GameLandingPageState extends ConsumerState<GameLandingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fieldController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _fieldController.dispose();
    super.dispose();
  }

  void _openSettings(GamePresetCategory category) {
    final state = ref.read(appControllerProvider);
    if (state.gameActive) {
      context.go('/couple-game');
      return;
    }
    // 首页选择只负责预选游戏，设置页仍可切换并分别调整两套配置。
    context.go('/settings?game=${category.name}');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 760;
    return Scaffold(
      backgroundColor: const Color(0xff090d0b),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          CustomPaint(
            painter: _ElectricArenaPainter(
              animation: _fieldController,
              primary: scheme.secondary,
              secondaryAccent: const Color(0xffffd84a),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Stack(
                children: <Widget>[
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton.filledTonal(
                      tooltip: '设置',
                      onPressed: () => context.go('/settings'),
                      icon: const Icon(Icons.settings),
                    ),
                  ),
                  Align(
                    alignment: wide
                        ? const Alignment(-0.72, 0.08)
                        : const Alignment(0, 0.38),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '耐久挑战',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: wide ? 58 : 42,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                            shadows: <Shadow>[
                              Shadow(
                                color: scheme.secondary.withValues(alpha: 0.8),
                                blurRadius: 18,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 34),
                        SizedBox(
                          width: 260,
                          height: 58,
                          child: FilledButton.icon(
                            key: const ValueKey<String>('start-game'),
                            style: FilledButton.styleFrom(
                              backgroundColor: scheme.secondary,
                              foregroundColor: scheme.onSecondary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            onPressed: () =>
                                _openSettings(GamePresetCategory.endurance),
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('开始游戏'),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: 260,
                          height: 52,
                          child: OutlinedButton.icon(
                            key: const ValueKey<String>(
                              'open-heart-experience',
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xffff9ab4),
                              side: const BorderSide(color: Color(0xffff6f91)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            onPressed: () =>
                                _openSettings(GamePresetCategory.heart),
                            icon: const Icon(Icons.favorite),
                            label: const Text('心动挑战'),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: 260,
                          height: 52,
                          child: OutlinedButton.icon(
                            key: const ValueKey<String>('open-leaderboard'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Color(0xff9ba7a0)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            onPressed: () => context.go('/leaderboard'),
                            icon: const Icon(Icons.leaderboard),
                            label: const Text('排行榜'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GameSettingsPage extends ConsumerStatefulWidget {
  const GameSettingsPage({
    super.key,
    this.heartExperienceOnly = false,
    this.initialCategory = GamePresetCategory.endurance,
  });

  final bool heartExperienceOnly;
  final GamePresetCategory initialCategory;

  @override
  ConsumerState<GameSettingsPage> createState() => _GameSettingsPageState();
}

class _GameSettingsPageState extends ConsumerState<GameSettingsPage> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = ref.read(appControllerProvider).gameActive ? 1 : 0;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final pages = <Widget>[
      DevicePage(
        fixedGameRole: widget.heartExperienceOnly
            ? DeviceGameRole.couple
            : null,
      ),
      GameSetupPage(
        initialCategory: widget.heartExperienceOnly
            ? GamePresetCategory.heart
            : widget.initialCategory,
        experienceOnly: widget.heartExperienceOnly,
      ),
    ];
    final content = IndexedStack(index: _index, children: pages);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: widget.heartExperienceOnly && !state.gameActive
            ? null
            : IconButton(
                tooltip: state.gameActive ? '返回游戏' : '返回首页',
                onPressed: () =>
                    context.go(state.gameActive ? '/couple-game' : '/'),
                icon: const Icon(Icons.arrow_back),
              ),
        title: Text(widget.heartExperienceOnly ? '心动体验' : '设置'),
        actions: <Widget>[
          if (widget.heartExperienceOnly)
            IconButton(
              tooltip: '体验记录',
              onPressed: () => context.go('/leaderboard'),
              icon: const Icon(Icons.leaderboard),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 9),
            child: GameVisualStyleSwitch(compact: true),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '全部紧急停止',
            onPressed: state.devices.isEmpty
                ? null
                : () => unawaited(
                    ref.read(appControllerProvider.notifier).emergencyStop(),
                  ),
            icon: const Icon(Icons.stop_circle),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: wide
            ? Row(
                children: <Widget>[
                  NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: (value) =>
                        setState(() => _index = value),
                    labelType: NavigationRailLabelType.all,
                    destinations: <NavigationRailDestination>[
                      NavigationRailDestination(
                        icon: const Icon(Icons.bluetooth_searching),
                        label: const Text('设备连接'),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.tune),
                        label: Text(
                          widget.heartExperienceOnly ? '体验设置' : '玩法配置',
                        ),
                      ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              )
            : content,
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              destinations: <NavigationDestination>[
                const NavigationDestination(
                  icon: Icon(Icons.bluetooth_searching),
                  label: '设备连接',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.tune),
                  label: widget.heartExperienceOnly ? '体验设置' : '玩法配置',
                ),
              ],
            ),
    );
  }
}

class GameLeaderboardPage extends StatelessWidget {
  const GameLeaderboardPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: const Color(0xff0d120f),
      foregroundColor: Colors.white,
      leading: IconButton(
        tooltip: '返回首页',
        onPressed: () => context.go('/'),
        icon: const Icon(Icons.arrow_back),
      ),
    ),
    body: const SafeArea(child: LeaderboardPage()),
  );
}

class _ElectricArenaPainter extends CustomPainter {
  _ElectricArenaPainter({
    required this.animation,
    required this.primary,
    required this.secondaryAccent,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color primary;
  final Color secondaryAccent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xff090d0b),
    );
    _drawGrid(canvas, size);
    _drawPyramid(canvas, size);
    _drawCurrent(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xff728078).withValues(alpha: 0.14)
      ..strokeWidth = 1;
    const gap = 48.0;
    for (var x = 0.0; x <= size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawPyramid(Canvas canvas, Size size) {
    final mobile = size.width < 760;
    final center = Offset(
      mobile ? size.width * 0.5 : size.width * 0.73,
      mobile ? size.height * 0.33 : size.height * 0.54,
    );
    final width = math.min(
      mobile ? size.width * 0.72 : size.width * 0.42,
      520.0,
    );
    final height = math.min(
      mobile ? size.height * 0.3 : size.height * 0.58,
      520.0,
    );
    final bounds = Rect.fromCenter(
      center: center,
      width: width,
      height: height,
    );
    final gradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: <Color>[
        primary.withValues(alpha: 0.16),
        const Color(0xffffb020).withValues(alpha: 0.24),
        secondaryAccent.withValues(alpha: 0.36),
      ],
    ).createShader(bounds);
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..shader = gradient;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = primary.withValues(alpha: 0.65);
    const levels = 6;
    const gap = 7.0;
    final levelHeight = (height - gap * (levels - 1)) / levels;
    for (var level = 0; level < levels; level++) {
      final bottom = bounds.bottom - level * (levelHeight + gap);
      final top = bottom - levelHeight;
      final bottomRatio = (bottom - bounds.top) / height;
      final topRatio = (top - bounds.top) / height;
      final bottomWidth = 18 + (width - 18) * bottomRatio;
      final topWidth = 18 + (width - 18) * topRatio;
      final path = Path()
        ..moveTo(center.dx - topWidth / 2, top)
        ..lineTo(center.dx + topWidth / 2, top)
        ..lineTo(center.dx + bottomWidth / 2, bottom)
        ..lineTo(center.dx - bottomWidth / 2, bottom)
        ..close();
      canvas.drawPath(path, fill);
      canvas.drawPath(path, outline);
    }
  }

  void _drawCurrent(Canvas canvas, Size size) {
    final phase = animation.value * math.pi * 2;
    for (var line = 0; line < 3; line++) {
      final baseY = size.height * (0.22 + line * 0.27);
      final path = Path()..moveTo(-20, baseY);
      const segments = 18;
      for (var segment = 1; segment <= segments; segment++) {
        final x = size.width * segment / segments;
        final pulse = math.sin(phase + segment * 1.8 + line) * 10;
        final spike = segment % 4 == 0 ? (line.isEven ? -22.0 : 22.0) : 0.0;
        path.lineTo(x, baseY + pulse + spike);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = line == 1 ? 2 : 1
          ..color = (line == 1 ? secondaryAccent : primary).withValues(
            alpha: line == 1 ? 0.22 : 0.16,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_ElectricArenaPainter oldDelegate) =>
      oldDelegate.primary != primary ||
      oldDelegate.secondaryAccent != secondaryAccent;
}
