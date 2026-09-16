import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yokonex_ems_game/core/model/models.dart';
import 'package:yokonex_ems_game/features/leaderboard/leaderboard.dart';

void main() {
  test('配置指纹忽略挑战者和设备', () {
    final first = _config(name: '甲', deviceId: 'device-a');
    final second = _config(name: '乙', deviceId: 'device-b');
    expect(first.fingerprint, second.fingerprint);

    final differentDuration = _config(
      name: '甲',
      deviceId: 'device-a',
      durationSeconds: 31,
    );
    expect(first.fingerprint, isNot(differentDuration.fingerprint));
  });

  test('忽略配置和结果，全部记录按坚持时长排名', () {
    final base = DateTime(2026, 8, 26, 12);
    final records = <ChallengeRecord>[
      _record(
        id: 'a-failed-short',
        fingerprint: 'a',
        result: ChallengeResult.failed,
        elapsedMs: 10000,
        time: base,
      ),
      _record(
        id: 'b-failed',
        fingerprint: 'b',
        result: ChallengeResult.failed,
        elapsedMs: 5000,
        time: base.add(const Duration(minutes: 3)),
      ),
      _record(
        id: 'a-success-1',
        fingerprint: 'a',
        result: ChallengeResult.success,
        elapsedMs: 30000,
        time: base.add(const Duration(minutes: 1)),
      ),
      _record(
        id: 'a-failed-long',
        fingerprint: 'a',
        result: ChallengeResult.aborted,
        elapsedMs: 20000,
        time: base.add(const Duration(minutes: 2)),
      ),
      _record(
        id: 'a-success-2',
        fingerprint: 'a',
        result: ChallengeResult.success,
        elapsedMs: 30000,
        time: base.add(const Duration(minutes: 4)),
      ),
    ];

    final groups = Leaderboard.groupAndRank(records);
    expect(groups, hasLength(1));
    expect(groups.first.fingerprint, 'global-duration');
    expect(groups.first.title, '全场耐久榜');
    expect(groups.first.records.map((item) => item.record.id), <String>[
      'a-success-2',
      'a-success-1',
      'a-failed-long',
      'a-failed-short',
      'b-failed',
    ]);
    expect(groups.first.records.map((item) => item.rank), <int>[1, 1, 2, 3, 4]);
  });
}

EmsGameConfig _config({
  required String name,
  required String deviceId,
  int durationSeconds = 30,
}) => EmsGameConfig(
  challengerName: name,
  deviceId: deviceId,
  protocol: DeviceProtocol.emsV2,
  channels: ChannelSelection.a,
  durationSeconds: durationSeconds,
  channelA: const ChannelGameConfig(
    startStrength: 1,
    maxStrength: 10,
    increaseEverySeconds: 1,
    increaseBy: 1,
    waveformId: 'steady',
  ),
  channelB: const ChannelGameConfig(
    startStrength: 0,
    maxStrength: 0,
    increaseEverySeconds: 1,
    increaseBy: 1,
    waveformId: 'steady',
  ),
  channelsLinked: false,
);

ChallengeRecord _record({
  required String id,
  required String fingerprint,
  required ChallengeResult result,
  required int elapsedMs,
  required DateTime time,
}) => ChallengeRecord(
  id: id,
  challengerName: id,
  configFingerprint: fingerprint,
  configJson: jsonEncode(<String, Object?>{'durationSeconds': 30}),
  protocol: DeviceProtocol.emsV2,
  channels: ChannelSelection.a,
  result: result,
  elapsedMs: elapsedMs,
  maximumStrengthA: 10,
  maximumStrengthB: 0,
  finalStrengthA: 10,
  finalStrengthB: 0,
  startedAt: time.subtract(Duration(milliseconds: elapsedMs)),
  finishedAt: time,
);
