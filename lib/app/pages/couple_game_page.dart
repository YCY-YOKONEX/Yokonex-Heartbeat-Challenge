import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yokonex_ems_game/app/app_controller.dart';
import 'package:yokonex_ems_game/core/model/models.dart';
import 'package:yokonex_ems_game/features/leaderboard/leaderboard.dart';

class CoupleGamePage extends ConsumerStatefulWidget {
  const CoupleGamePage({super.key, this.standaloneExperience = false});

  final bool standaloneExperience;

  @override
  ConsumerState<CoupleGamePage> createState() => _CoupleGamePageState();
}

class _CoupleGamePageState extends ConsumerState<CoupleGamePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final activeDeviceId = state.activeRelayDeviceId;
    final activeDevice = activeDeviceId == null
        ? null
        : state.devices[activeDeviceId];
    if (activeDevice?.gameRole == DeviceGameRole.arena) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/game');
      });
    }

    final entry = _visibleCoupleSession(state);
    if (entry == null) {
      return Scaffold(
        backgroundColor: _CoupleColors.background,
        body: Center(
          child: FilledButton.icon(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.arrow_back),
            label: const Text('返回设置'),
          ),
        ),
      );
    }

    final session = entry.value;
    final device = state.devices[session.config.deviceId];
    final channelASession = _coupleSessionForChannel(
      state,
      session.config.deviceId,
      ChannelSelection.a,
    );
    final channelBSession = _coupleSessionForChannel(
      state,
      session.config.deviceId,
      ChannelSelection.b,
    );
    final strength = session.config.channels == ChannelSelection.a
        ? device?.telemetry.reportedStrengthA ?? 0
        : device?.telemetry.reportedStrengthB ?? 0;
    // 独立体验页同时观察 A/B 两路，但控制器仍只允许一路实际输出。
    final experienceChannels = <_ExperienceChannelInfo>[
      _ExperienceChannelInfo(
        channel: ChannelSelection.a,
        session: channelASession,
        electrode: device?.telemetry.electrodeA ?? ElectrodeState.unknown,
        currentStrength: device?.telemetry.reportedStrengthA ?? 0,
        config: channelASession?.config.channelA ?? session.config.channelA,
        waveformName: _waveformName(
          state.waveforms,
          (channelASession?.config.channelA ?? session.config.channelA)
              .waveformId,
        ),
      ),
      _ExperienceChannelInfo(
        channel: ChannelSelection.b,
        session: channelBSession,
        electrode: device?.telemetry.electrodeB ?? ElectrodeState.unknown,
        currentStrength: device?.telemetry.reportedStrengthB ?? 0,
        config: channelBSession?.config.channelB ?? session.config.channelB,
        waveformName: _waveformName(
          state.waveforms,
          (channelBSession?.config.channelB ?? session.config.channelB)
              .waveformId,
        ),
      ),
    ];
    final runningOrStopping =
        session.status == GameStatus.running ||
        session.status == GameStatus.stopping;
    final showingExperienceParameters =
        widget.standaloneExperience && runningOrStopping;
    final showingChallengeScene =
        !widget.standaloneExperience && session.status != GameStatus.ready;
    final totalMs = session.config.durationSeconds * 1000;
    final challengeProgress = totalMs <= 0
        ? 0.0
        : (session.elapsedMs / totalMs).clamp(0.0, 1.0).toDouble();
    final completed = _isCoupleCompleted(session.status);
    final rank = completed ? _coupleRank(state.records, session) : null;

    return Scaffold(
      backgroundColor: _CoupleColors.background,
      appBar: AppBar(
        backgroundColor: _CoupleColors.surface,
        foregroundColor: _CoupleColors.text,
        leading: IconButton(
          tooltip: '返回首页',
          onPressed: () => context.go('/'),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(
          completed
              ? '本轮结算'
              : showingExperienceParameters
              ? '双通道状态'
              : widget.standaloneExperience
              ? '等待触摸'
              : showingChallengeScene
              ? '心动挑战'
              : '心动牵手',
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '调整配置',
            onPressed: () => context.go('/settings'),
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: '全部紧急停止',
            onPressed: controller.emergencyStop,
            icon: const Icon(Icons.stop_circle_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: completed
            ? Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: _CoupleSettlementPanel(session: session, rank: rank),
                  ),
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 680;
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 14 : 28,
                          compact ? 12 : 20,
                          compact ? 14 : 28,
                          18,
                        ),
                        child: showingExperienceParameters
                            ? _CoupleRunningParameters(
                                compact: compact,
                                channels: experienceChannels,
                                onStop: () => controller.stopSession(
                                  entry.key,
                                  ChallengeResult.aborted,
                                  reason: '用户终止情侣挑战',
                                ),
                              )
                            : showingChallengeScene
                            ? _HeartChallengeRunningPanel(
                                animation: _animation,
                                compact: compact,
                                progress: challengeProgress,
                                name: session.config.challengerName,
                                status: session.status,
                                countdownSeconds: session.countdownSeconds,
                                elapsedMs: session.elapsedMs,
                                currentStrength: strength,
                                onStop: () => controller.stopSession(
                                  entry.key,
                                  ChallengeResult.aborted,
                                  reason: '用户终止情侣挑战',
                                ),
                              )
                            : widget.standaloneExperience
                            ? _TouchWaitingPanel(
                                animation: _animation,
                                compact: compact,
                              )
                            : _HoldHandsWaitingPanel(
                                animation: _animation,
                                compact: compact,
                              ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _CoupleSettlementPanel extends StatelessWidget {
  const _CoupleSettlementPanel({required this.session, required this.rank});

  final GameSessionState session;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final success = session.status == GameStatus.success;
    final maximum = math.max(
      session.maximumStrengthA,
      session.maximumStrengthB,
    );
    final resultColor = success ? _CoupleColors.yellow : _CoupleColors.coral;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(
          success ? Icons.favorite : Icons.heart_broken,
          color: resultColor,
          size: 64,
        ),
        const SizedBox(height: 10),
        Text(
          success ? '心动挑战成功' : _coupleStatus(session.status),
          style: TextStyle(
            color: resultColor,
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          session.config.challengerName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _CoupleColors.text,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          '当前排名',
          style: TextStyle(
            color: _CoupleColors.muted,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 1500),
          curve: Curves.elasticOut,
          builder: (context, value, child) =>
              Transform.scale(scale: value, child: child),
          child: Text(
            rank == null ? '--' : '#$rank',
            key: const ValueKey<String>('couple-settlement-rank'),
            style: TextStyle(
              color: resultColor,
              fontSize: 76,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: <Widget>[
            Expanded(
              child: _CoupleSettlementMetric(
                label: '挑战时长',
                value: _formatCoupleTime(session.elapsedMs),
              ),
            ),
            Expanded(
              child: _CoupleSettlementMetric(label: '最高强度', value: '$maximum'),
            ),
          ],
        ),
        const SizedBox(height: 28),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 1, end: 0),
            duration: const Duration(seconds: 10),
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 6,
              color: resultColor,
              backgroundColor: _CoupleColors.heartTrack,
            ),
          ),
        ),
      ],
    );
  }
}

class _CoupleSettlementMetric extends StatelessWidget {
  const _CoupleSettlementMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Text(
        label,
        style: const TextStyle(color: _CoupleColors.muted, fontSize: 13),
      ),
      const SizedBox(height: 5),
      Text(
        value,
        style: const TextStyle(
          color: _CoupleColors.text,
          fontSize: 26,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );
}

class _HeartChallengeRunningPanel extends StatelessWidget {
  const _HeartChallengeRunningPanel({
    required this.animation,
    required this.compact,
    required this.progress,
    required this.name,
    required this.status,
    required this.countdownSeconds,
    required this.elapsedMs,
    required this.currentStrength,
    required this.onStop,
  });

  final Animation<double> animation;
  final bool compact;
  final double progress;
  final String name;
  final GameStatus status;
  final int countdownSeconds;
  final int elapsedMs;
  final int currentStrength;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final active =
        status == GameStatus.countdown || status == GameStatus.running;
    return Column(
      key: const ValueKey<String>('couple-challenge-running'),
      children: <Widget>[
        _CoupleHeader(name: name, status: status),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: _CoupleMetric(
                icon: Icons.timer_outlined,
                label: '游戏时间',
                value: _formatCoupleTime(elapsedMs),
                color: _CoupleColors.mint,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CoupleMetric(
                icon: Icons.bolt,
                label: '实时强度',
                value: '$currentStrength',
                color: _CoupleColors.yellow,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _CoupleScene(
            animation: animation,
            active: active,
            compact: compact,
            progress: progress,
            status: status,
            countdownSeconds: countdownSeconds,
            onStop: onStop,
          ),
        ),
      ],
    );
  }
}

class _CoupleHeader extends StatelessWidget {
  const _CoupleHeader({required this.name, required this.status});

  final String name;
  final GameStatus status;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _CoupleColors.coral,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.favorite, color: _CoupleColors.background),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _CoupleColors.text,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Text(
              '两个人靠近一点，心跳会替你们计时',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _CoupleColors.muted),
            ),
          ],
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(color: _CoupleColors.coral),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          _coupleStatus(status),
          style: const TextStyle(
            color: _CoupleColors.coral,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ],
  );
}

class _CoupleMetric extends StatelessWidget {
  const _CoupleMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    height: 86,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: _CoupleColors.surface,
      border: Border.all(color: color.withValues(alpha: 0.55)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: <Widget>[
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: const TextStyle(color: _CoupleColors.muted)),
              Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CoupleScene extends StatelessWidget {
  const _CoupleScene({
    required this.animation,
    required this.active,
    required this.compact,
    required this.progress,
    required this.status,
    required this.countdownSeconds,
    required this.onStop,
  });

  final Animation<double> animation;
  final bool active;
  final bool compact;
  final double progress;
  final GameStatus status;
  final int countdownSeconds;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const ValueKey<String>('couple-scene'),
    decoration: BoxDecoration(
      color: _CoupleColors.surface,
      border: Border.all(color: _CoupleColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Stack(
      fit: StackFit.expand,
      children: <Widget>[
        AnimatedBuilder(
          animation: animation,
          builder: (context, _) => LayoutBuilder(
            builder: (context, sceneConstraints) {
              final animationsDisabled = MediaQuery.disableAnimationsOf(
                context,
              );
              final pulse = active && !animationsDisabled
                  ? 1 + math.sin(animation.value * math.pi * 2) * 0.025
                  : 1.0;
              final compositionWidth = math.min(
                sceneConstraints.maxWidth * (compact ? 0.9 : 0.62),
                compact ? 360.0 : 520.0,
              );
              final compositionHeight = math.min(
                sceneConstraints.maxHeight - 52,
                compositionWidth * (compact ? 0.98 : 0.82),
              );
              final imageWidth = compositionWidth * (compact ? 0.62 : 0.58);
              return Padding(
                padding: const EdgeInsets.only(bottom: 46),
                child: Center(
                  // 插画和爱心保持在同一构图区，避免上下分离。
                  child: SizedBox(
                    key: const ValueKey<String>('couple-composition'),
                    width: compositionWidth,
                    height: math.max(0.0, compositionHeight),
                    child: Transform.scale(
                      key: const ValueKey<String>('couple-dogs-heart'),
                      scale: pulse,
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          CustomPaint(
                            painter: _CoupleScenePainter(
                              progress: progress,
                              compact: compact,
                            ),
                          ),
                          Positioned(
                            top: 0,
                            left: (compositionWidth - imageWidth) / 2,
                            width: imageWidth,
                            child: Image.asset(
                              'assets/illustrations/couple_dogs.png',
                              key: const ValueKey<String>(
                                'couple-dogs-illustration',
                              ),
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (status == GameStatus.countdown)
          Center(child: _CountdownBadge(seconds: countdownSeconds)),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _coupleMessage(status),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _CoupleColors.text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (active)
          Positioned(
            top: 12,
            right: 12,
            child: compact
                ? Tooltip(
                    message: '结束本次挑战',
                    child: IconButton.filled(
                      key: const ValueKey<String>('stop-couple-game'),
                      style: IconButton.styleFrom(
                        backgroundColor: _CoupleColors.coral,
                        foregroundColor: _CoupleColors.background,
                      ),
                      onPressed: onStop,
                      icon: const Icon(Icons.stop),
                    ),
                  )
                : FilledButton.icon(
                    key: const ValueKey<String>('stop-couple-game'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _CoupleColors.coral,
                      foregroundColor: _CoupleColors.background,
                    ),
                    onPressed: onStop,
                    icon: const Icon(Icons.stop),
                    label: const Text('结束本次挑战'),
                  ),
          ),
      ],
    ),
  );
}

class _CountdownBadge extends StatelessWidget {
  const _CountdownBadge({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) => Container(
    width: 112,
    height: 112,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: _CoupleColors.background.withValues(alpha: 0.9),
      shape: BoxShape.circle,
      border: Border.all(color: _CoupleColors.yellow, width: 3),
    ),
    child: Text(
      '$seconds',
      style: const TextStyle(
        color: _CoupleColors.yellow,
        fontSize: 58,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _CoupleScenePainter extends CustomPainter {
  const _CoupleScenePainter({required this.progress, required this.compact});

  final double progress;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final heartWidth = size.width * (compact ? 0.78 : 0.68);
    final heartHeight = size.height * (compact ? 0.58 : 0.6);
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * (compact ? 0.66 : 0.65)),
      width: heartWidth,
      height: heartHeight,
    );
    final path = _heartPath(rect);
    canvas.drawPath(
      path,
      Paint()
        ..color = _CoupleColors.heartTrack
        ..style = PaintingStyle.fill,
    );
    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(
      Rect.fromLTRB(
        rect.left,
        rect.bottom - rect.height * progress,
        rect.right,
        rect.bottom,
      ),
      Paint()..color = _CoupleColors.coral,
    );
    canvas.restore();
    canvas.drawPath(
      path,
      Paint()
        ..color = _CoupleColors.pink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
  }

  @override
  bool shouldRepaint(covariant _CoupleScenePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.compact != compact;
}

Path _heartPath(Rect rect) {
  final path = Path();
  path.moveTo(rect.center.dx, rect.bottom);
  path.cubicTo(
    rect.left - rect.width * 0.08,
    rect.top + rect.height * 0.58,
    rect.left + rect.width * 0.04,
    rect.top + rect.height * 0.08,
    rect.left + rect.width * 0.27,
    rect.top + rect.height * 0.08,
  );
  path.cubicTo(
    rect.left + rect.width * 0.42,
    rect.top + rect.height * 0.08,
    rect.center.dx,
    rect.top + rect.height * 0.26,
    rect.center.dx,
    rect.top + rect.height * 0.34,
  );
  path.cubicTo(
    rect.center.dx,
    rect.top + rect.height * 0.26,
    rect.right - rect.width * 0.42,
    rect.top + rect.height * 0.08,
    rect.right - rect.width * 0.27,
    rect.top + rect.height * 0.08,
  );
  path.cubicTo(
    rect.right - rect.width * 0.04,
    rect.top + rect.height * 0.08,
    rect.right + rect.width * 0.08,
    rect.top + rect.height * 0.58,
    rect.center.dx,
    rect.bottom,
  );
  path.close();
  return path;
}

class _ExperienceChannelInfo {
  const _ExperienceChannelInfo({
    required this.channel,
    required this.session,
    required this.electrode,
    required this.currentStrength,
    required this.config,
    required this.waveformName,
  });

  final ChannelSelection channel;
  final GameSessionState? session;
  final ElectrodeState electrode;
  final int currentStrength;
  final ChannelGameConfig config;
  final String waveformName;
}

class _CoupleRunningParameters extends StatelessWidget {
  const _CoupleRunningParameters({
    required this.compact,
    required this.channels,
    required this.onStop,
  });

  final bool compact;
  final List<_ExperienceChannelInfo> channels;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final channelPanels = <Widget>[
      for (final channel in channels)
        Expanded(child: _ExperienceChannelPanel(info: channel)),
    ];
    final panels = compact
        ? Column(
            children: <Widget>[
              channelPanels[0],
              const SizedBox(height: 12),
              channelPanels[1],
            ],
          )
        : Row(
            children: <Widget>[
              channelPanels[0],
              const SizedBox(width: 14),
              channelPanels[1],
            ],
          );

    return Column(
      key: const ValueKey<String>('couple-running-parameters'),
      children: <Widget>[
        Expanded(child: panels),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              key: const ValueKey<String>('stop-couple-game'),
              style: FilledButton.styleFrom(
                backgroundColor: _CoupleColors.coral,
                foregroundColor: _CoupleColors.background,
              ),
              onPressed: onStop,
              icon: const Icon(Icons.stop),
              label: const Text('结束本次体验'),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExperienceChannelPanel extends StatelessWidget {
  const _ExperienceChannelPanel({required this.info});

  final _ExperienceChannelInfo info;

  @override
  Widget build(BuildContext context) {
    final accent = info.channel == ChannelSelection.a
        ? _CoupleColors.mint
        : _CoupleColors.yellow;
    final maximum = info.config.maxStrength;
    final strengthProgress = maximum <= 0
        ? 0.0
        : (info.currentStrength / maximum).clamp(0.0, 1.0).toDouble();
    final elapsedMs = info.session?.elapsedMs ?? 0;
    return Container(
      key: ValueKey<String>('experience-channel-${info.channel.name}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _CoupleColors.surface,
        border: Border.all(color: accent.withValues(alpha: 0.65), width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  info.channel == ChannelSelection.a ? 'A' : 'B',
                  style: TextStyle(
                    color: accent,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      info.channel.label,
                      style: const TextStyle(
                        color: _CoupleColors.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      info.electrode.label,
                      style: const TextStyle(
                        color: _CoupleColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: accent.withValues(alpha: 0.72)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _experienceChannelStatus(info),
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: <Widget>[
              Expanded(
                child: _ExperienceValue(
                  label: '实时强度',
                  value: '${info.currentStrength}',
                  color: accent,
                  key: ValueKey<String>(
                    'experience-strength-${info.channel.name}',
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 48,
                color: accent.withValues(alpha: 0.28),
              ),
              Expanded(
                child: _ExperienceValue(
                  label: '游戏时间',
                  value: _formatCoupleTime(elapsedMs),
                  color: _CoupleColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: strengthProgress,
              minHeight: 7,
              color: accent,
              backgroundColor: _CoupleColors.heartTrack,
            ),
          ),
          const Spacer(),
          Row(
            children: <Widget>[
              Expanded(
                child: _ExperienceDetail(
                  label: '起始强度',
                  value: '${info.config.startStrength}',
                ),
              ),
              Expanded(
                child: _ExperienceDetail(
                  label: '强度上限',
                  value: '${info.config.maxStrength}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _ExperienceDetail(
                  label: '递增规则',
                  value:
                      '每 ${info.config.increaseEverySeconds} 秒 +${info.config.increaseBy}',
                ),
              ),
              Expanded(
                child: _ExperienceDetail(
                  label: '当前波形',
                  value: info.waveformName,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExperienceValue extends StatelessWidget {
  const _ExperienceValue({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Text(
        label,
        style: const TextStyle(color: _CoupleColors.muted, fontSize: 12),
      ),
      const SizedBox(height: 3),
      SizedBox(
        width: double.infinity,
        height: 30,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    ],
  );
}

class _ExperienceDetail extends StatelessWidget {
  const _ExperienceDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _CoupleColors.muted, fontSize: 11),
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: double.infinity,
          height: 21,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: _CoupleColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

String _experienceChannelStatus(_ExperienceChannelInfo info) {
  final status = info.session?.status;
  if (status == GameStatus.running) return '体验中';
  if (status == GameStatus.stopping) return '停止中';
  if (status != null && _isCoupleCompleted(status)) return '已结束';
  return switch (info.electrode) {
    ElectrodeState.discharging => '输出中',
    ElectrodeState.attachedIdle => '已接入',
    ElectrodeState.detached => '未接入',
    ElectrodeState.unknown => '等待设备',
  };
}

class _HoldHandsWaitingPanel extends StatelessWidget {
  const _HoldHandsWaitingPanel({
    required this.animation,
    required this.compact,
  });

  final Animation<double> animation;
  final bool compact;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const ValueKey<String>('couple-hold-hands-prompt'),
    decoration: BoxDecoration(
      color: _CoupleColors.surface,
      border: Border.all(color: _CoupleColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Semantics(
      label: '请两位玩家牵手，接通回路后自动开始',
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final animationsDisabled = MediaQuery.disableAnimationsOf(context);
          final cycle = animation.value;
          final progress = animationsDisabled
              ? 1.0
              : cycle < 0.4
              ? Curves.easeOutCubic.transform(cycle / 0.4)
              : cycle < 0.72
              ? 1.0
              : Curves.easeInOutCubic.transform((1 - cycle) / 0.28);
          return Center(
            child: SizedBox(
              width: compact ? 310 : 470,
              height: compact ? 300 : 350,
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: CustomPaint(
                      key: const ValueKey<String>(
                        'couple-people-hold-hands-animation',
                      ),
                      painter: _HoldHandsPainter(
                        progress: progress,
                        pulse: animationsDisabled ? 1 : cycle,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '请两位玩家牵手',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _CoupleColors.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    '接通回路后自动开始',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _CoupleColors.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '牵起手，心动就会开始',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _CoupleColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _HoldHandsPainter extends CustomPainter {
  const _HoldHandsPainter({required this.progress, required this.pulse});

  final double progress;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final heart = Path()
      ..moveTo(centerX, size.height * 0.92)
      ..cubicTo(
        size.width * 0.13,
        size.height * 0.66,
        size.width * 0.16,
        size.height * 0.3,
        size.width * 0.34,
        size.height * 0.31,
      )
      ..cubicTo(
        size.width * 0.43,
        size.height * 0.31,
        centerX,
        size.height * 0.39,
        centerX,
        size.height * 0.48,
      )
      ..cubicTo(
        centerX,
        size.height * 0.39,
        size.width * 0.57,
        size.height * 0.31,
        size.width * 0.66,
        size.height * 0.31,
      )
      ..cubicTo(
        size.width * 0.84,
        size.height * 0.3,
        size.width * 0.87,
        size.height * 0.66,
        centerX,
        size.height * 0.92,
      );
    canvas.drawPath(
      heart,
      Paint()
        ..color = _CoupleColors.pink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final restingOffset = size.width * 0.16;
    final joinedOffset = size.width * 0.1;
    final offset = restingOffset + (joinedOffset - restingOffset) * progress;
    final personY = size.height * 0.13;
    final handY = size.height * 0.28;
    final handGap = size.width * 0.025 * (1 - progress);
    final leftHand = Offset(centerX - handGap, handY);
    final rightHand = Offset(centerX + handGap, handY);
    final personScale = math
        .min(size.width / 470, size.height / 230)
        .clamp(0.85, 1.15);

    _paintPerson(
      canvas,
      center: Offset(centerX - offset, personY),
      color: _CoupleColors.mint,
      joinedHand: leftHand,
      facingRight: true,
      scale: personScale,
    );
    _paintPerson(
      canvas,
      center: Offset(centerX + offset, personY),
      color: _CoupleColors.yellow,
      joinedHand: rightHand,
      facingRight: false,
      scale: personScale,
    );

    if (progress < 0.82) return;
    final beat = 0.9 + 0.12 * math.sin(pulse * math.pi * 4);
    final smallHeart = _smallHeartPath(Offset(centerX, handY - 12), 14 * beat);
    canvas.drawPath(smallHeart, Paint()..color = _CoupleColors.coral);
  }

  void _paintPerson(
    Canvas canvas, {
    required Offset center,
    required Color color,
    required Offset joinedHand,
    required bool facingRight,
    required double scale,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final headRadius = 18.0 * scale;
    final torsoTop = center.dy + headRadius * 0.72;
    final torsoHeight = 62.0 * scale;
    final torsoWidth = 40.0 * scale;
    final neckWidth = 16.0 * scale;

    // 颈部与头、躯干互相重叠，缩放和运动时始终保持完整轮廓。
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center.dx, torsoTop + 3 * scale),
          width: neckWidth,
          height: 24 * scale,
        ),
        Radius.circular(neckWidth / 2),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center.dx, torsoTop + torsoHeight / 2),
          width: torsoWidth,
          height: torsoHeight,
        ),
        Radius.circular(torsoWidth * 0.48),
      ),
      paint,
    );
    canvas.drawCircle(center, headRadius, paint);

    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final shoulder = Offset(
      center.dx + (facingRight ? torsoWidth * 0.42 : -torsoWidth * 0.42),
      torsoTop + 17 * scale,
    );
    final elbow = Offset(
      (shoulder.dx + joinedHand.dx) / 2,
      joinedHand.dy + 8 * scale,
    );
    canvas.drawPath(
      Path()
        ..moveTo(shoulder.dx, shoulder.dy)
        ..quadraticBezierTo(elbow.dx, elbow.dy, joinedHand.dx, joinedHand.dy),
      line,
    );

    final outsideShoulder = Offset(
      center.dx + (facingRight ? -torsoWidth * 0.42 : torsoWidth * 0.42),
      torsoTop + 19 * scale,
    );
    final outsideHand = Offset(
      outsideShoulder.dx + (facingRight ? -10 * scale : 10 * scale),
      torsoTop + torsoHeight * 0.75,
    );
    canvas.drawPath(
      Path()
        ..moveTo(outsideShoulder.dx, outsideShoulder.dy)
        ..quadraticBezierTo(
          outsideHand.dx + (facingRight ? 4 * scale : -4 * scale),
          torsoTop + torsoHeight * 0.48,
          outsideHand.dx,
          outsideHand.dy,
        ),
      line,
    );

    final hipY = torsoTop + torsoHeight - 5 * scale;
    final footY = hipY + 42 * scale;
    canvas.drawPath(
      Path()
        ..moveTo(center.dx - 8 * scale, hipY)
        ..quadraticBezierTo(
          center.dx - 12 * scale,
          hipY + 20 * scale,
          center.dx - 13 * scale,
          footY,
        ),
      line,
    );
    canvas.drawPath(
      Path()
        ..moveTo(center.dx + 8 * scale, hipY)
        ..quadraticBezierTo(
          center.dx + 12 * scale,
          hipY + 20 * scale,
          center.dx + 13 * scale,
          footY,
        ),
      line,
    );
  }

  Path _smallHeartPath(Offset center, double size) => Path()
    ..moveTo(center.dx, center.dy + size * 0.8)
    ..cubicTo(
      center.dx - size * 1.3,
      center.dy,
      center.dx - size * 0.8,
      center.dy - size,
      center.dx,
      center.dy - size * 0.35,
    )
    ..cubicTo(
      center.dx + size * 0.8,
      center.dy - size,
      center.dx + size * 1.3,
      center.dy,
      center.dx,
      center.dy + size * 0.8,
    );

  @override
  bool shouldRepaint(_HoldHandsPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.pulse != pulse;
}

class _TouchWaitingPanel extends StatelessWidget {
  const _TouchWaitingPanel({required this.animation, required this.compact});

  final Animation<double> animation;
  final bool compact;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const ValueKey<String>('couple-touch-prompt'),
    decoration: BoxDecoration(
      color: _CoupleColors.surface,
      border: Border.all(color: _CoupleColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Semantics(
      label: '请两位玩家触摸，接通回路后自动开始',
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final animationsDisabled = MediaQuery.disableAnimationsOf(context);
          final cycle = animation.value;
          final phase = animationsDisabled
              ? 1.0
              : cycle < 0.38
              ? Curves.easeOutCubic.transform(cycle / 0.38)
              : cycle < 0.7
              ? 1.0
              : Curves.easeInOutCubic.transform((1 - cycle) / 0.3);
          return Center(
            child: SizedBox(
              width: compact ? 300 : 460,
              height: compact ? 280 : 340,
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: CustomPaint(
                      key: const ValueKey<String>('couple-touch-animation'),
                      painter: _TouchPainter(
                        progress: phase,
                        pulse: animationsDisabled ? 1 : cycle,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '请两位玩家触摸',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _CoupleColors.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    '触摸接通后自动开始',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _CoupleColors.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _TouchPainter extends CustomPainter {
  const _TouchPainter({required this.progress, required this.pulse});

  final double progress;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.48);
    final gap = size.width * 0.16 * (1 - progress);
    final fingerHeight = size.height * 0.18;
    final palmHeight = size.height * 0.4;
    final leftTip = center.dx - gap;
    final rightTip = center.dx + gap;
    final radius = Radius.circular(fingerHeight / 2);
    final leftPaint = Paint()..color = _CoupleColors.mint;
    final rightPaint = Paint()..color = _CoupleColors.coral;

    // 两侧手掌各伸出一根手指，靠近后在中心形成接触脉冲。
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          -size.width * 0.03,
          center.dy - palmHeight * 0.12,
          size.width * 0.24,
          center.dy + palmHeight * 0.88,
        ),
        Radius.circular(palmHeight * 0.26),
      ),
      leftPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          size.width * 0.76,
          center.dy - palmHeight * 0.12,
          size.width * 1.03,
          center.dy + palmHeight * 0.88,
        ),
        Radius.circular(palmHeight * 0.26),
      ),
      rightPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          size.width * 0.16,
          center.dy - fingerHeight / 2,
          leftTip,
          center.dy + fingerHeight / 2,
        ),
        radius,
      ),
      leftPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          rightTip,
          center.dy - fingerHeight / 2,
          size.width * 0.84,
          center.dy + fingerHeight / 2,
        ),
        radius,
      ),
      rightPaint,
    );

    if (progress < 0.88) return;
    final pulsePhase = (math.sin(pulse * math.pi * 4) + 1) / 2;
    canvas.drawCircle(
      center,
      5 + pulsePhase * 3,
      Paint()..color = _CoupleColors.yellow,
    );
    for (var index = 0; index < 3; index++) {
      final ringRadius = 18 + index * 13 + pulsePhase * 8;
      canvas.drawCircle(
        center,
        ringRadius,
        Paint()
          ..color = _CoupleColors.yellow.withValues(alpha: 0.42 - index * 0.1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_TouchPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.pulse != pulse;
}

GameSessionState? _coupleSessionForChannel(
  AppState state,
  String deviceId,
  ChannelSelection channel,
) {
  for (final session in state.sessions.values) {
    if (session.config.deviceId == deviceId &&
        session.config.channels == channel) {
      return session;
    }
  }
  return null;
}

String _waveformName(List<EmsWaveform> waveforms, String waveformId) {
  for (final waveform in waveforms) {
    if (waveform.id == waveformId) return waveform.name;
  }
  return waveformId;
}

MapEntry<String, GameSessionState>? _visibleCoupleSession(AppState state) {
  final activeDeviceId = state.activeRelayDeviceId;
  if (activeDeviceId != null &&
      state.devices[activeDeviceId]?.gameRole == DeviceGameRole.couple) {
    for (final entry in state.sessions.entries) {
      if (entry.value.config.deviceId == activeDeviceId && entry.value.active) {
        return entry;
      }
    }
  }
  final lastRecordId = state.lastRecord?.id;
  if (lastRecordId != null) {
    for (final entry in state.sessions.entries) {
      final device = state.devices[entry.value.config.deviceId];
      if (device?.gameRole == DeviceGameRole.couple &&
          lastRecordId.startsWith('${entry.key}-')) {
        return entry;
      }
    }
  }
  for (final entry in state.sessions.entries) {
    if (state.devices[entry.value.config.deviceId]?.gameRole ==
        DeviceGameRole.couple) {
      return entry;
    }
  }
  // 尚未形成回路时没有活跃设备，先用首个等待位展示触摸引导。
  for (final entry in state.sessions.entries) {
    return entry;
  }
  return null;
}

int? _coupleRank(List<ChallengeRecord> records, GameSessionState session) {
  final matchingRecords =
      records
          .where(
            (record) =>
                record.challengerName == session.config.challengerName &&
                record.configFingerprint == session.config.fingerprint,
          )
          .toList(growable: false)
        ..sort((left, right) => right.finishedAt.compareTo(left.finishedAt));
  if (matchingRecords.isEmpty) return null;
  final recordId = matchingRecords.first.id;
  for (final ranked in Leaderboard.groupAndRank(
    records,
  ).expand((group) => group.records)) {
    if (ranked.record.id == recordId) return ranked.rank;
  }
  return null;
}

bool _isCoupleCompleted(GameStatus status) =>
    status == GameStatus.success ||
    status == GameStatus.failed ||
    status == GameStatus.aborted ||
    status == GameStatus.error;

String _formatCoupleTime(int elapsedMs) {
  final minutes = elapsedMs ~/ 60000;
  final seconds = (elapsedMs % 60000) ~/ 1000;
  final tenths = (elapsedMs % 1000) ~/ 100;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}.$tenths';
}

String _coupleStatus(GameStatus status) => switch (status) {
  GameStatus.ready => '等待牵手',
  GameStatus.countdown => '心动倒计时',
  GameStatus.running => '默契进行中',
  GameStatus.stopping => '正在结算',
  GameStatus.success => '牵手成功',
  GameStatus.failed => '挑战结束',
  GameStatus.aborted => '已经结束',
  GameStatus.error => '状态异常',
};

String _coupleMessage(GameStatus status) => switch (status) {
  GameStatus.ready => '牵起手，心动就会开始',
  GameStatus.countdown => '别松手，我们马上出发',
  GameStatus.running => '坚持住，让爱心慢慢亮满',
  GameStatus.stopping => '正在记录你们的默契',
  GameStatus.success => '爱心已点亮，挑战成功',
  GameStatus.failed => '这次先到这里，下次再牵紧一点',
  GameStatus.aborted => '本次挑战已经结束',
  GameStatus.error => '设备状态异常，请重新连接',
};

abstract final class _CoupleColors {
  static const background = Color(0xff1b1018);
  static const surface = Color(0xff271821);
  static const border = Color(0xff573342);
  static const text = Color(0xfffff8f3);
  static const muted = Color(0xffc8abb6);
  static const coral = Color(0xffff6f91);
  static const pink = Color(0xffffa6bd);
  static const mint = Color(0xff72d6c9);
  static const yellow = Color(0xffffd36e);
  static const heartTrack = Color(0xff4b2735);
}
