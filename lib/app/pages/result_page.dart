import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yokonex_ems_game/app/app_controller.dart';
import 'package:yokonex_ems_game/core/model/models.dart';

class ResultPage extends ConsumerWidget {
  const ResultPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final record = state.lastRecord;
    if (record == null) {
      return Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('返回首页'),
          ),
        ),
      );
    }
    final success = record.result == ChallengeResult.success;
    return Scaffold(
      appBar: AppBar(
        title: const Text('挑战结果'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: <Widget>[
                      Icon(
                        success ? Icons.emoji_events : Icons.flag,
                        size: 72,
                        color: success
                            ? const Color(0xffd97706)
                            : Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        record.result.label,
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(state.message, textAlign: TextAlign.center),
                      if (state.error.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          state.error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 18,
                        runSpacing: 18,
                        alignment: WrapAlignment.center,
                        children: <Widget>[
                          _ResultMetric(
                            label: '挑战者',
                            value: record.challengerName,
                          ),
                          _ResultMetric(
                            label: '坚持时间',
                            value:
                                '${(record.elapsedMs / 1000).toStringAsFixed(1)} 秒',
                          ),
                          _ResultMetric(
                            label: 'A 最高强度',
                            value: '${record.maximumStrengthA}',
                          ),
                          _ResultMetric(
                            label: 'B 最高强度',
                            value: '${record.maximumStrengthB}',
                          ),
                          _ResultMetric(
                            label: '开始电量',
                            value: record.batteryAtStart == null
                                ? '--'
                                : '${record.batteryAtStart}%',
                          ),
                          _ResultMetric(
                            label: '结束电量',
                            value: record.batteryAtEnd == null
                                ? '--'
                                : '${record.batteryAtEnd}%',
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        onPressed: () => context.go('/'),
                        icon: const Icon(Icons.replay),
                        label: const Text('返回并再次挑战'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultMetric extends StatelessWidget {
  const _ResultMetric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: Column(
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}
