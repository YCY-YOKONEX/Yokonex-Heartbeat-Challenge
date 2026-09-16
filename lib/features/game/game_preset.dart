import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:yokonex_ems_game/core/model/models.dart';

enum GamePresetCategory { endurance, heart }

extension GamePresetCategoryX on GamePresetCategory {
  String get label => switch (this) {
    GamePresetCategory.endurance => '耐久挑战',
    GamePresetCategory.heart => '心动挑战',
  };

  String get defaultPresetId => switch (this) {
    GamePresetCategory.endurance => GamePresetStore.defaultPresetId,
    GamePresetCategory.heart => GamePresetStore.malePresetId,
  };
}

class GamePreset {
  const GamePreset({
    required this.id,
    required this.name,
    required this.durationSeconds,
    required this.startStrength,
    required this.maxStrength,
    required this.increaseEverySeconds,
    required this.increaseBy,
    required this.waveformId,
    this.category = GamePresetCategory.endurance,
    this.custom = false,
  });

  final String id;
  final String name;
  final int durationSeconds;
  final int startStrength;
  final int maxStrength;
  final int increaseEverySeconds;
  final int increaseBy;
  final String waveformId;
  final GamePresetCategory category;
  final bool custom;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'durationSeconds': durationSeconds,
    'startStrength': startStrength,
    'maxStrength': maxStrength,
    'increaseEverySeconds': increaseEverySeconds,
    'increaseBy': increaseBy,
    'waveformId': waveformId,
    'category': category.name,
    'custom': custom,
  };

  factory GamePreset.fromJson(Map<String, Object?> value) {
    final id = value['id'] as String;
    return GamePreset(
      id: id,
      name: value['name'] as String,
      durationSeconds: value['durationSeconds'] as int,
      startStrength: value['startStrength'] as int,
      maxStrength: value['maxStrength'] as int,
      increaseEverySeconds: value['increaseEverySeconds'] as int,
      increaseBy: value['increaseBy'] as int,
      waveformId: value['waveformId'] as String,
      category: _presetCategoryFromJson(value['category'], id),
      custom: value['custom'] as bool? ?? true,
    );
  }
}

abstract final class GamePresetStore {
  static const String _storageKey = 'game_config_presets';
  static const String malePresetId = 'builtin-male';
  static const String femalePresetId = 'builtin-female';
  static const String defaultPresetId = 'builtin-default-45s';

  static const List<GamePreset> builtIns = <GamePreset>[
    // 男女预设只调整每秒增长值，其余心动挑战参数保持一致。
    GamePreset(
      id: malePresetId,
      name: '男生',
      durationSeconds: 10,
      startStrength: 1,
      maxStrength: 20,
      increaseEverySeconds: 1,
      increaseBy: 2,
      waveformId: smoothRampWaveformId,
      category: GamePresetCategory.heart,
    ),
    GamePreset(
      id: femalePresetId,
      name: '女生',
      durationSeconds: 10,
      startStrength: 1,
      maxStrength: 20,
      increaseEverySeconds: 1,
      increaseBy: 1,
      waveformId: smoothRampWaveformId,
      category: GamePresetCategory.heart,
    ),
    // 默认挑战用于首页快速开始，强度从 1 开始并按每秒 2 点稳定提升。
    GamePreset(
      id: defaultPresetId,
      name: '默认挑战',
      durationSeconds: 45,
      startStrength: 1,
      maxStrength: 90,
      increaseEverySeconds: 1,
      increaseBy: 2,
      waveformId: smoothRampWaveformId,
    ),
    GamePreset(
      id: 'builtin-beginner',
      name: '入门',
      durationSeconds: 60,
      startStrength: 10,
      maxStrength: 40,
      increaseEverySeconds: 10,
      increaseBy: 5,
      waveformId: 'coyote-pulse-111',
    ),
    GamePreset(
      id: 'builtin-standard',
      name: '标准',
      durationSeconds: 90,
      startStrength: 15,
      maxStrength: 80,
      increaseEverySeconds: 10,
      increaseBy: 5,
      waveformId: 'coyote-pulse-112',
    ),
    GamePreset(
      id: 'builtin-advanced',
      name: '进阶',
      durationSeconds: 120,
      startStrength: 20,
      maxStrength: 120,
      increaseEverySeconds: 10,
      increaseBy: 10,
      waveformId: 'coyote-pulse-116',
    ),
    GamePreset(
      id: 'builtin-smooth-ramp',
      name: '平缓渐强',
      durationSeconds: 60,
      startStrength: 30,
      maxStrength: 180,
      increaseEverySeconds: 1,
      increaseBy: 2,
      waveformId: smoothRampWaveformId,
    ),
  ];

  static bool isExperiencePreset(String? id) => builtIns.any(
    (preset) => preset.id == id && preset.category == GamePresetCategory.heart,
  );

  static Future<List<GamePreset>> loadCustom() async {
    final preferences = await SharedPreferences.getInstance();
    final source = preferences.getString(_storageKey);
    if (source == null || source.isEmpty) return const <GamePreset>[];
    try {
      return (jsonDecode(source) as List<Object?>)
          .map(
            (value) => GamePreset.fromJson(
              (value as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .where((preset) => preset.custom)
          .toList(growable: false);
    } on Object {
      return const <GamePreset>[];
    }
  }

  static Future<void> save(GamePreset preset) async {
    final preferences = await SharedPreferences.getInstance();
    final presets = <GamePreset>[
      ...(await loadCustom()).where((item) => item.id != preset.id),
      preset,
    ];
    await preferences.setString(
      _storageKey,
      jsonEncode(presets.map((item) => item.toJson()).toList()),
    );
  }

  static Future<void> delete(String id) async {
    final preferences = await SharedPreferences.getInstance();
    final presets = (await loadCustom())
        .where((item) => item.id != id)
        .toList();
    await preferences.setString(
      _storageKey,
      jsonEncode(presets.map((item) => item.toJson()).toList()),
    );
  }
}

GamePresetCategory _presetCategoryFromJson(Object? value, String id) {
  for (final category in GamePresetCategory.values) {
    if (category.name == value) return category;
  }
  // 兼容旧版本保存的数据；原有男女配置属于心动挑战，其余归入耐久挑战。
  return id == GamePresetStore.malePresetId ||
          id == GamePresetStore.femalePresetId
      ? GamePresetCategory.heart
      : GamePresetCategory.endurance;
}
