import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yokonex_ems_game/app/app_controller.dart';
import 'package:yokonex_ems_game/app/pages/home_page.dart' show LeaderboardPage;
import 'package:yokonex_ems_game/app/visual_style.dart';
import 'package:yokonex_ems_game/core/model/models.dart';
import 'package:yokonex_ems_game/features/leaderboard/leaderboard.dart';

class GamePage extends ConsumerStatefulWidget {
  const GamePage({super.key});

  @override
  ConsumerState<GamePage> createState() => _GamePageState();
}

class _GamePageState extends ConsumerState<GamePage> {
  bool _showWaitingCards = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final visualStyle = ref.watch(gameVisualStyleProvider);
    final compactHeader = MediaQuery.sizeOf(context).width < 700;
    final activeDeviceId = state.activeRelayDeviceId;
    final activeDevice = activeDeviceId == null
        ? null
        : state.devices[activeDeviceId];
    if (activeDevice?.gameRole == DeviceGameRole.couple) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/couple-game');
      });
    }
    ref.listen<int>(
      appControllerProvider.select((value) => value.leaderboardRevision),
      (previous, next) {
        if (previous != null && next > previous) {
          setState(() => _showWaitingCards = false);
        }
      },
    );
    final allSessions = state.sessions.entries.toList();
    final visibleDeviceId = _visibleRelayDeviceId(state, allSessions);
    final sessions =
        allSessions
            .where((entry) => entry.value.config.deviceId == visibleDeviceId)
            .toList()
          ..sort((left, right) {
            return _channelOrder(
              left.value.config.channels,
            ).compareTo(_channelOrder(right.value.config.channels));
          });
    final ranks = _ranksForSessions(state.records, sessions);
    final showSettlementLeaderboard =
        state.relayWaitingForPlayers && !_showWaitingCards;

    return Scaffold(
      backgroundColor: const Color(0xff080c0a),
      appBar: AppBar(
        backgroundColor: const Color(0xff0d120f),
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: '返回首页',
          onPressed: () => context.go('/'),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(
          showSettlementLeaderboard
              ? (compactHeader ? '本轮结算' : '本轮结算 · 荣耀排行榜')
              : (compactHeader ? '多设备对战' : '电流登顶 · 多设备对战'),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '调整配置',
            onPressed: () => context.go('/settings'),
            icon: const Icon(Icons.tune),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 9),
            child: GameVisualStyleSwitch(compact: true),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: CustomPaint(
                painter: _DuelArenaPainter(style: visualStyle),
              ),
            ),
            if (sessions.isEmpty)
              _EmptyArena(onBack: () => context.go('/'))
            else
              Column(
                children: <Widget>[
                  Expanded(
                    child: showSettlementLeaderboard
                        ? LeaderboardPage(
                            onReturnToGame: () =>
                                setState(() => _showWaitingCards = true),
                          )
                        : _SessionGrid(
                            sessions: sessions,
                            devices: state.devices,
                            ranks: ranks,
                            style: visualStyle,
                            onStopSession: (sessionId) =>
                                controller.stopSession(
                                  sessionId,
                                  ChallengeResult.aborted,
                                  reason: '用户终止单通道挑战',
                                ),
                            onStartSession:
                                controller.startRelaySessionManually,
                          ),
                  ),
                  _BottomActions(
                    active: state.gameActive,
                    onBack: () => context.go('/'),
                    onClear: () {
                      controller.clearFinishedSessions();
                      context.go('/');
                    },
                    onStopAll: () async {
                      await controller.stopAll(reason: '用户终止挑战');
                      if (context.mounted) context.go('/');
                    },
                    onEmergencyStop: controller.emergencyStop,
                  ),
                ],
              ),
            if (state.error.isNotEmpty)
              Positioned(
                top: 8,
                left: 16,
                right: 16,
                child: _ErrorBanner(message: state.error),
              ),
          ],
        ),
      ),
    );
  }
}

String? _visibleRelayDeviceId(
  AppState state,
  List<MapEntry<String, GameSessionState>> sessions,
) {
  // 页面只展示当前执行设备的 A/B，其他设备继续在后台检测。
  for (final entry in sessions) {
    if (entry.value.active) return entry.value.config.deviceId;
  }
  final lastRecordId = state.lastRecord?.id;
  if (lastRecordId != null) {
    for (final entry in sessions) {
      if (lastRecordId.startsWith('${entry.key}-')) {
        return entry.value.config.deviceId;
      }
    }
  }
  for (final entry in sessions) {
    if (entry.value.status != GameStatus.ready) {
      return entry.value.config.deviceId;
    }
  }
  return sessions.isEmpty ? null : sessions.first.value.config.deviceId;
}

class _SessionGrid extends StatelessWidget {
  const _SessionGrid({
    required this.sessions,
    required this.devices,
    required this.ranks,
    required this.style,
    required this.onStopSession,
    required this.onStartSession,
  });

  final List<MapEntry<String, GameSessionState>> sessions;
  final Map<String, ConnectedDeviceState> devices;
  final Map<String, int> ranks;
  final GameVisualStyle style;
  final Future<void> Function(String sessionId) onStopSession;
  final void Function(String sessionId) onStartSession;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final horizontal = constraints.maxWidth >= 720;
      if (horizontal) {
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sessions.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 570,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemBuilder: (context, index) => _buildCard(sessions[index], index),
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: sessions.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (context, index) =>
            SizedBox(height: 570, child: _buildCard(sessions[index], index)),
      );
    },
  );

  Widget _buildCard(MapEntry<String, GameSessionState> entry, int index) =>
      _PlayerRuntimeCard(
        key: ValueKey<String>('player-card-${entry.key}'),
        playerIndex: index,
        sessionId: entry.key,
        session: entry.value,
        device: devices[entry.value.config.deviceId],
        rank: ranks[entry.key],
        style: style,
        onStop: () => onStopSession(entry.key),
        onStart: () => onStartSession(entry.key),
      );
}

class _PlayerRuntimeCard extends StatelessWidget {
  const _PlayerRuntimeCard({
    super.key,
    required this.playerIndex,
    required this.sessionId,
    required this.session,
    required this.device,
    required this.rank,
    required this.style,
    required this.onStop,
    required this.onStart,
  });

  final int playerIndex;
  final String sessionId;
  final GameSessionState session;
  final ConnectedDeviceState? device;
  final int? rank;
  final GameVisualStyle style;
  final VoidCallback onStop;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final channel = session.config.channels == ChannelSelection.b
        ? ChannelSelection.b
        : ChannelSelection.a;
    final accent = channel == ChannelSelection.a
        ? const Color(0xff49f7d2)
        : const Color(0xffffd84a);
    final telemetry = device?.telemetry ?? const DeviceTelemetry();
    final reportedStrength = channel == ChannelSelection.a
        ? telemetry.reportedStrengthA
        : telemetry.reportedStrengthB;
    final totalMs = session.config.durationSeconds * 1000;
    final progress = totalMs <= 0
        ? 0.0
        : (session.elapsedMs / totalMs).clamp(0.0, 1.0);
    final completed = _isCompleted(session.status);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xff101713),
        border: Border.all(color: accent.withValues(alpha: 0.78), width: 2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accent.withValues(alpha: 0.2),
            blurRadius: 22,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: CustomPaint(painter: _CardCircuitPainter(accent: accent)),
          ),
          if (session.status == GameStatus.running)
            Positioned.fill(
              child: IgnorePointer(
                child: _RunningEnergyLayer(
                  key: ValueKey<String>('running-energy-$sessionId'),
                  accent: accent,
                  strength: reportedStrength,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: <Widget>[
                _PlayerHeader(
                  playerIndex: playerIndex,
                  sessionId: sessionId,
                  channel: channel,
                  challengerName: session.config.challengerName,
                  status: session.status,
                  accent: accent,
                  onStop:
                      session.status == GameStatus.countdown ||
                          session.status == GameStatus.running
                      ? onStop
                      : null,
                  onStart: session.status == GameStatus.ready ? onStart : null,
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: completed
                      ? _CompletedResultPanel(
                          session: session,
                          accent: accent,
                          rank: rank,
                        )
                      : Column(
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: _GameMetric(
                                    label: '游戏时间',
                                    value: _formatTime(session.elapsedMs),
                                    accent: accent,
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 74,
                                  color: accent.withValues(alpha: 0.3),
                                ),
                                Expanded(
                                  child: _GameMetric(
                                    label: '实时强度',
                                    value: '$reportedStrength',
                                    accent: accent,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: _ChallengePyramid(
                                key: ValueKey<String>(
                                  'challenge-pyramid-$sessionId',
                                ),
                                progress: progress,
                                status: session.status,
                                accent: accent,
                                style: style,
                              ),
                            ),
                            if (session.status == GameStatus.countdown)
                              _CountdownNumber(
                                seconds: session.countdownSeconds,
                                accent: accent,
                              )
                            else if (session.status == GameStatus.ready)
                              Text(
                                channel == ChannelSelection.a
                                    ? '抓住左侧单杠开始游戏'
                                    : '抓住右侧单杠开始游戏',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RunningEnergyLayer extends StatefulWidget {
  const _RunningEnergyLayer({
    super.key,
    required this.accent,
    required this.strength,
  });

  final Color accent;
  final int strength;

  @override
  State<_RunningEnergyLayer> createState() => _RunningEnergyLayerState();
}

class _RunningEnergyLayerState extends State<_RunningEnergyLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) {
      return CustomPaint(
        painter: _RunningEnergyPainter(
          phase: 0.55,
          accent: widget.accent,
          strength: widget.strength,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _RunningEnergyPainter(
          phase: _controller.value,
          accent: widget.accent,
          strength: widget.strength,
        ),
      ),
    );
  }
}

class _RunningEnergyPainter extends CustomPainter {
  const _RunningEnergyPainter({
    required this.phase,
    required this.accent,
    required this.strength,
  });

  final double phase;
  final Color accent;
  final int strength;

  @override
  void paint(Canvas canvas, Size size) {
    final power = (strength / emsMaximumStrength).clamp(0.12, 1.0);
    final pulse = (math.sin(phase * math.pi * 2) + 1) / 2;
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // 强度越高，边框呼吸、冲击波和上升电流越醒目。
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 + pulse * 2
      ..color = accent.withValues(alpha: 0.28 + power * pulse * 0.34)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + power * 8);
    canvas.drawRect(
      Rect.fromLTWH(4, 4, size.width - 8, size.height - 8),
      borderPaint,
    );

    final center = Offset(size.width / 2, size.height * 0.63);
    final maximumRadius = math.max(size.width, size.height) * 0.58;
    for (var index = 0; index < 3; index++) {
      final wave = (phase + index / 3) % 1;
      final radius = 24 + maximumRadius * wave;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 - wave * 1.7
          ..color = accent.withValues(
            alpha: (1 - wave) * (0.18 + power * 0.22),
          ),
      );
    }

    final streamPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus;
    for (var index = 0; index < 8; index++) {
      final travel = (phase * (0.8 + power * 0.8) + index / 8) % 1;
      final y = size.height * (1 - travel);
      final spread = 0.16 + travel * 0.34;
      final halfWidth = size.width * spread;
      streamPaint
        ..strokeWidth = index.isEven ? 2.4 : 1.2
        ..color = accent.withValues(
          alpha: (0.08 + power * 0.24) * (1 - travel * 0.55),
        );
      canvas.drawLine(
        Offset(size.width / 2 - halfWidth, y),
        Offset(size.width / 2 + halfWidth, y),
        streamPaint,
      );
    }

    final sparkPaint = Paint()
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.plus;
    for (var index = 0; index < 12; index++) {
      final travel = (phase * (1.1 + power) + index / 12) % 1;
      final angle = index * 2.399 + phase * math.pi * 2;
      final radius = 30 + travel * math.min(size.width, size.height) * 0.48;
      final point = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius * 0.58,
      );
      sparkPaint.color = accent.withValues(
        alpha: (1 - travel) * (0.22 + power * 0.5),
      );
      canvas.drawCircle(point, 1.5 + power * 2, sparkPaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RunningEnergyPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.accent != accent ||
      oldDelegate.strength != strength;
}

class _PlayerHeader extends StatelessWidget {
  const _PlayerHeader({
    required this.playerIndex,
    required this.sessionId,
    required this.channel,
    required this.challengerName,
    required this.status,
    required this.accent,
    required this.onStop,
    required this.onStart,
  });

  final int playerIndex;
  final String sessionId;
  final ChannelSelection channel;
  final String challengerName;
  final GameStatus status;
  final Color accent;
  final VoidCallback? onStop;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        color: accent,
        child: Text(
          channel.name.toUpperCase(),
          style: const TextStyle(
            color: Color(0xff07100c),
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              challengerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              'PLAYER ${playerIndex + 1}',
              style: TextStyle(
                color: accent.withValues(alpha: 0.75),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          _GameStatusPill(status: status, accent: accent),
          const SizedBox(height: 6),
          Tooltip(
            message: onStart != null
                ? '手动开始 ${channel.label}'
                : '终止 ${channel.label}',
            child: SizedBox(
              height: 34,
              child: FilledButton.icon(
                key: onStart == null
                    ? null
                    : ValueKey<String>('manual-start-$sessionId'),
                style: FilledButton.styleFrom(
                  backgroundColor: onStart != null
                      ? accent
                      : const Color(0xffc92f3d),
                  disabledBackgroundColor: const Color(0xff3d2428),
                  foregroundColor: onStart != null
                      ? const Color(0xff07100c)
                      : Colors.white,
                  disabledForegroundColor: const Color(0xffa98287),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: onStart ?? onStop,
                icon: Icon(
                  onStart != null ? Icons.play_arrow : Icons.stop,
                  size: 16,
                ),
                label: Text(
                  onStart != null
                      ? '手动开始 ${channel.name.toUpperCase()}'
                      : '终止 ${channel.name.toUpperCase()}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

class _GameMetric extends StatelessWidget {
  const _GameMetric({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Text(
        label,
        style: const TextStyle(
          color: Color(0xff98a59f),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 4),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          style: TextStyle(
            color: accent,
            fontSize: 38,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ],
  );
}

class _ChallengePyramid extends StatelessWidget {
  const _ChallengePyramid({
    super.key,
    required this.progress,
    required this.status,
    required this.accent,
    required this.style,
  });

  final double progress;
  final GameStatus status;
  final Color accent;
  final GameVisualStyle style;

  @override
  Widget build(BuildContext context) {
    final normalizedProgress = progress.clamp(0.0, 1.0);
    final percentage = (normalizedProgress * 100).round();
    final copy = _challengeCopy(status, normalizedProgress);
    return Semantics(
      label: '登顶进度 $percentage%，$copy',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pyramidHeight = math.min(constraints.maxHeight - 120, 310.0);
          final pyramidWidth = math.min(constraints.maxWidth * 0.82, 300.0);
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: pyramidWidth,
                height: pyramidHeight.clamp(120.0, 310.0),
                child: CustomPaint(
                  painter: _PyramidProgressPainter(
                    progress: normalizedProgress,
                    activeGradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      // 五种颜色各自保留主要区域，只在交界处做短渐变，顶部固定为红色。
                      colors: <Color>[
                        const Color(0xff35d9ff),
                        const Color(0xff35d9ff),
                        const Color(0xff49f7d2),
                        const Color(0xff49f7d2),
                        const Color(0xffffd84a),
                        const Color(0xffffd84a),
                        const Color(0xffff8a3d),
                        const Color(0xffff8a3d),
                        const Color(0xffff3b4d),
                        const Color(0xffff3b4d),
                      ],
                      stops: const <double>[
                        0,
                        0.15,
                        0.23,
                        0.35,
                        0.43,
                        0.57,
                        0.65,
                        0.77,
                        0.85,
                        1,
                      ],
                    ),
                    inactiveColor: const Color(0xff26312b),
                    borderColor: accent.withValues(alpha: 0.55),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                normalizedProgress <= 0 ? '等待登场' : '登顶进度 $percentage%',
                style: TextStyle(
                  color: accent,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 64),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  border: Border.symmetric(
                    horizontal: BorderSide(
                      color: accent.withValues(alpha: 0.55),
                    ),
                  ),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    copy,
                    key: ValueKey<String>(copy),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PyramidProgressPainter extends CustomPainter {
  const _PyramidProgressPainter({
    required this.progress,
    required this.activeGradient,
    required this.inactiveColor,
    required this.borderColor,
  });

  final double progress;
  final LinearGradient activeGradient;
  final Color inactiveColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    const apexWidth = 14.0;
    final pyramidPath = Path()
      ..moveTo((size.width - apexWidth) / 2, 0)
      ..lineTo((size.width + apexWidth) / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final inactivePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = inactiveColor;
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = borderColor;
    canvas.drawPath(pyramidPath, inactivePaint);
    canvas.drawPath(pyramidPath, borderPaint);

    if (progress <= 0) return;
    final activePaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = activeGradient.createShader(Offset.zero & size);
    canvas.save();
    // 进度从底部连续填充，避免分段金字塔产生明显的层级跳变。
    canvas.clipRect(
      Rect.fromLTRB(0, size.height * (1 - progress), size.width, size.height),
    );
    canvas.drawPath(pyramidPath, activePaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PyramidProgressPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.activeGradient != activeGradient ||
      oldDelegate.inactiveColor != inactiveColor ||
      oldDelegate.borderColor != borderColor;
}

class _CountdownNumber extends StatelessWidget {
  const _CountdownNumber({required this.seconds, required this.accent});

  final int seconds;
  final Color accent;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 180),
    transitionBuilder: (child, animation) => ScaleTransition(
      scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
      child: child,
    ),
    child: Text(
      '$seconds',
      key: ValueKey<int>(seconds),
      style: TextStyle(
        color: accent,
        fontSize: 58,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _CompletedResultPanel extends StatefulWidget {
  const _CompletedResultPanel({
    required this.session,
    required this.accent,
    required this.rank,
  });

  final GameSessionState session;
  final Color accent;
  final int? rank;

  @override
  State<_CompletedResultPanel> createState() => _CompletedResultPanelState();
}

class _CompletedResultPanelState extends State<_CompletedResultPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rankController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  @override
  void dispose() {
    _rankController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final maximum = math.max(
      session.maximumStrengthA,
      session.maximumStrengthB,
    );
    final success = session.status == GameStatus.success;
    final resultColor = success
        ? const Color(0xffffd84a)
        : Theme.of(context).colorScheme.error;
    final rankText = widget.rank == null ? '--' : '#${widget.rank}';
    return AnimatedBuilder(
      animation: _rankController,
      builder: (context, child) {
        final entry = Curves.easeOut.transform(
          (_rankController.value / 0.35).clamp(0.0, 1.0),
        );
        final rankEntry = Curves.elasticOut.transform(
          ((_rankController.value - 0.28) / 0.72).clamp(0.0, 1.0),
        );
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            CustomPaint(
              painter: _RankBurstPainter(
                progress: _rankController.value,
                color: resultColor,
              ),
            ),
            Opacity(
              opacity: entry,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    success ? Icons.emoji_events : Icons.sports_score,
                    color: resultColor,
                    size: 48,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    success ? '挑战成功' : _statusText(session.status),
                    style: TextStyle(
                      color: resultColor,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '当前排名',
                    style: TextStyle(
                      color: Color(0xffa8b3ad),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Transform.scale(
                    scale: rankEntry,
                    child: Text(
                      rankText,
                      key: const ValueKey<String>('settlement-rank'),
                      style: TextStyle(
                        color: resultColor,
                        fontSize: 72,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _SettlementMetric(
                          label: '挑战时长',
                          value: _formatTime(session.elapsedMs),
                        ),
                      ),
                      Expanded(
                        child: _SettlementMetric(
                          label: '最高强度',
                          value: '$maximum',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 1, end: 0),
                    duration: const Duration(seconds: 10),
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 5,
                      color: resultColor,
                      backgroundColor: const Color(0xff303b35),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SettlementMetric extends StatelessWidget {
  const _SettlementMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Text(
        label,
        style: const TextStyle(color: Color(0xff96a39c), fontSize: 12),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );
}

class _RankBurstPainter extends CustomPainter {
  const _RankBurstPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.46);
    final burst = Curves.easeOut.transform(progress.clamp(0.0, 1.0));
    for (var index = 0; index < 18; index++) {
      final angle = math.pi * 2 * index / 18;
      final startRadius = 58 + burst * 22;
      final endRadius = startRadius + 18 + burst * 42;
      canvas.drawLine(
        center + Offset(math.cos(angle), math.sin(angle)) * startRadius,
        center + Offset(math.cos(angle), math.sin(angle)) * endRadius,
        Paint()
          ..color = color.withValues(alpha: (1 - progress) * 0.72)
          ..strokeWidth = index.isEven ? 3 : 1,
      );
    }
  }

  @override
  bool shouldRepaint(_RankBurstPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

class _GameStatusPill extends StatelessWidget {
  const _GameStatusPill({required this.status, required this.accent});

  final GameStatus status;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final color = _isCompleted(status)
        ? status == GameStatus.success
              ? const Color(0xffffd84a)
              : Theme.of(context).colorScheme.error
        : accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.8)),
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(
        _statusText(status),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _EmptyArena extends StatelessWidget {
  const _EmptyArena({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.electric_bolt, color: Color(0xff49f7d2), size: 64),
        const SizedBox(height: 14),
        const Text(
          '等待游戏启动',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.home),
          label: const Text('返回首页'),
        ),
      ],
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.error,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: <Widget>[
          const Icon(Icons.warning_amber, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.active,
    required this.onBack,
    required this.onClear,
    required this.onStopAll,
    required this.onEmergencyStop,
  });

  final bool active;
  final VoidCallback onBack;
  final VoidCallback onClear;
  final VoidCallback onStopAll;
  final VoidCallback onEmergencyStop;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xff0d120f),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            final back = compact
                ? IconButton.outlined(
                    tooltip: active ? '返回首页' : '完成',
                    onPressed: active ? onBack : onClear,
                    icon: Icon(active ? Icons.home : Icons.done),
                  )
                : Expanded(
                    child: OutlinedButton.icon(
                      onPressed: active ? onBack : onClear,
                      icon: Icon(active ? Icons.home : Icons.done),
                      label: Text(active ? '返回首页' : '完成'),
                    ),
                  );
            final emergency = compact
                ? IconButton.filled(
                    tooltip: '全部紧急停止',
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: active ? onEmergencyStop : null,
                    icon: const Icon(Icons.stop_circle),
                  )
                : Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: active ? onEmergencyStop : null,
                      icon: const Icon(Icons.stop_circle),
                      label: const Text('全部紧急停止'),
                    ),
                  );
            return Row(
              children: <Widget>[
                back,
                const SizedBox(width: 10),
                Expanded(
                  flex: compact ? 1 : 2,
                  child: FilledButton.icon(
                    onPressed: active ? onStopAll : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('终止挑战'),
                  ),
                ),
                const SizedBox(width: 10),
                emergency,
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _DuelArenaPainter extends CustomPainter {
  const _DuelArenaPainter({required this.style});

  final GameVisualStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final lineColor = style == GameVisualStyle.arcade
        ? const Color(0xff49f7d2)
        : const Color(0xffa9ff43);
    final gridPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    const gap = 46.0;
    for (var x = 0.0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final centerPaint = Paint()
      ..color = const Color(0xffffd84a).withValues(alpha: 0.2)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      centerPaint,
    );
  }

  @override
  bool shouldRepaint(_DuelArenaPainter oldDelegate) =>
      oldDelegate.style != style;
}

class _CardCircuitPainter extends CustomPainter {
  const _CardCircuitPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accent.withValues(alpha: 0.055)
      ..strokeWidth = 1;
    for (var y = 92.0; y < size.height; y += 58) {
      final path = Path()
        ..moveTo(0, y)
        ..lineTo(size.width * 0.18, y)
        ..lineTo(size.width * 0.24, y + 10)
        ..lineTo(size.width * 0.52, y + 10)
        ..lineTo(size.width * 0.58, y)
        ..lineTo(size.width, y);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_CardCircuitPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

Map<String, int> _ranksForSessions(
  List<ChallengeRecord> records,
  List<MapEntry<String, GameSessionState>> sessions,
) {
  final ranks = <String, int>{};
  final rankedRecords = Leaderboard.groupAndRank(
    records,
  ).expand((group) => group.records).toList(growable: false);
  for (final sessionEntry in sessions) {
    final session = sessionEntry.value;
    final matchingRecords =
        records
            .where(
              (record) =>
                  record.challengerName == session.config.challengerName &&
                  record.configFingerprint == session.config.fingerprint,
            )
            .toList(growable: false)
          ..sort((left, right) => right.finishedAt.compareTo(left.finishedAt));
    if (matchingRecords.isEmpty) continue;
    final recordId = matchingRecords.first.id;
    for (final ranked in rankedRecords) {
      if (ranked.record.id == recordId) {
        ranks[sessionEntry.key] = ranked.rank;
        break;
      }
    }
  }
  return ranks;
}

int _channelOrder(ChannelSelection channel) => switch (channel) {
  ChannelSelection.a => 0,
  ChannelSelection.b => 1,
  ChannelSelection.ab => 2,
};

bool _isCompleted(GameStatus status) =>
    status == GameStatus.success ||
    status == GameStatus.failed ||
    status == GameStatus.aborted ||
    status == GameStatus.error;

String _challengeCopy(GameStatus status, double progress) {
  if (status == GameStatus.ready) return '抓住单杠，挑战你的耐力极限';
  if (status == GameStatus.countdown) return '准备登塔';
  if (status == GameStatus.stopping) return '正在结算';
  if (progress < 0.15) return '这才刚开始，你行不行啊？';
  if (progress < 0.35) return '忍着！你是小孩子吗？';
  if (progress < 0.55) return '现在还像点样子，但也仅此而已';
  if (progress < 0.75) return '哟？比多数人强点';
  if (progress < 0.95) return '可以可以，让人刮目相看';
  return '真能坚持到现在？你是天选抖M吧？';
}

String _formatTime(int value) {
  final safe = value < 0 ? 0 : value;
  final minutes = safe ~/ 60000;
  final seconds = (safe ~/ 1000) % 60;
  final tenths = (safe % 1000) ~/ 100;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}.$tenths';
}

String _statusText(GameStatus status) => switch (status) {
  GameStatus.ready => '等待接入',
  GameStatus.countdown => '准备开始',
  GameStatus.running => '挑战中',
  GameStatus.stopping => '结算中',
  GameStatus.success => '成功',
  GameStatus.failed => '失败',
  GameStatus.aborted => '已中止',
  GameStatus.error => '异常',
};
