import 'package:yokonex_ems_game/core/model/models.dart';

class RankedChallengeRecord {
  const RankedChallengeRecord({required this.rank, required this.record});

  final int rank;
  final ChallengeRecord record;
}

class LeaderboardGroup {
  const LeaderboardGroup({
    required this.fingerprint,
    required this.title,
    required this.records,
  });

  final String fingerprint;
  final String title;
  final List<RankedChallengeRecord> records;
}

abstract final class Leaderboard {
  // 所有挑战记录进入同一耐久榜，只按实际坚持时长排名。
  static List<LeaderboardGroup> groupAndRank(List<ChallengeRecord> records) {
    if (records.isEmpty) return const <LeaderboardGroup>[];
    final sorted = <ChallengeRecord>[...records]..sort(_compareRecords);
    var rank = 0;
    int? previousElapsedMs;
    final ranked = <RankedChallengeRecord>[];
    for (final record in sorted) {
      if (previousElapsedMs != record.elapsedMs) {
        rank++;
        previousElapsedMs = record.elapsedMs;
      }
      ranked.add(RankedChallengeRecord(rank: rank, record: record));
    }
    return <LeaderboardGroup>[
      LeaderboardGroup(
        fingerprint: 'global-duration',
        title: '全场耐久榜',
        records: ranked,
      ),
    ];
  }

  static int _compareRecords(ChallengeRecord left, ChallengeRecord right) {
    final elapsed = right.elapsedMs.compareTo(left.elapsedMs);
    return elapsed != 0 ? elapsed : right.finishedAt.compareTo(left.finishedAt);
  }
}
