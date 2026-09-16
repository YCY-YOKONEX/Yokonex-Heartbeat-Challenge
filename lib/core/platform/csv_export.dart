import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:file_selector/file_selector.dart' as files;
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart' as share;
import 'package:yokonex_ems_game/core/model/models.dart';
import 'package:yokonex_ems_game/features/leaderboard/leaderboard.dart';

abstract final class ChallengeCsvExporter {
  static Future<bool> export(List<ChallengeRecord> records) async {
    final rows = <List<Object?>>[
      <Object?>[
        '榜单',
        '名次',
        '挑战者',
        '结果',
        '设备',
        '通道',
        '坚持时间(秒)',
        'A最高强度',
        'B最高强度',
        'A结束强度',
        'B结束强度',
        '开始电量',
        '结束电量',
        '开始时间',
        '结束时间',
        '配置详情',
      ],
    ];
    for (final group in Leaderboard.groupAndRank(records)) {
      for (final ranked in group.records) {
        final record = ranked.record;
        rows.add(<Object?>[
          group.title,
          ranked.rank,
          record.challengerName,
          record.result.label,
          record.protocol.label,
          record.channels.label,
          (record.elapsedMs / 1000).toStringAsFixed(1),
          record.maximumStrengthA,
          record.maximumStrengthB,
          record.finalStrengthA,
          record.finalStrengthB,
          record.batteryAtStart ?? '',
          record.batteryAtEnd ?? '',
          record.startedAt.toIso8601String(),
          record.finishedAt.toIso8601String(),
          record.configJson,
        ]);
      }
    }
    final csv = const ListToCsvConverter(eol: '\r\n').convert(rows);
    final bytes = Uint8List.fromList(<int>[
      0xef,
      0xbb,
      0xbf,
      ...utf8.encode(csv),
    ]);
    final name = '电击挑战排行榜_${DateTime.now().millisecondsSinceEpoch}.csv';

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      final location = await files.getSaveLocation(
        suggestedName: name,
        acceptedTypeGroups: const <files.XTypeGroup>[
          files.XTypeGroup(
            label: 'CSV',
            extensions: <String>['csv'],
            mimeTypes: <String>['text/csv'],
          ),
        ],
      );
      if (location == null) return false;
      await files.XFile.fromData(
        bytes,
        mimeType: 'text/csv',
        name: name,
      ).saveTo(location.path);
      return true;
    }

    final result = await share.SharePlus.instance.share(
      share.ShareParams(
        files: <share.XFile>[
          share.XFile.fromData(bytes, mimeType: 'text/csv', name: name),
        ],
        fileNameOverrides: <String>[name],
        downloadFallbackEnabled: true,
      ),
    );
    return result.status != share.ShareResultStatus.dismissed;
  }
}
