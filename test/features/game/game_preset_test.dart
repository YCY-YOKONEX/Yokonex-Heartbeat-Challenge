import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yokonex_ems_game/core/model/models.dart';
import 'package:yokonex_ems_game/features/game/game_preset.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('提供七套内置统一配置预设', () {
    expect(GamePresetStore.builtIns.map((item) => item.name), <String>[
      '男生',
      '女生',
      '默认挑战',
      '入门',
      '标准',
      '进阶',
      '平缓渐强',
    ]);
    expect(
      GamePresetStore.builtIns.every(
        (item) => item.startStrength <= item.maxStrength,
      ),
      isTrue,
    );
    expect(
      GamePresetStore.builtIns
          .where((item) => item.category == GamePresetCategory.heart)
          .map((item) => item.name),
      <String>['男生', '女生'],
    );
    expect(
      GamePresetStore.builtIns
          .where((item) => item.category == GamePresetCategory.endurance)
          .map((item) => item.name),
      <String>['默认挑战', '入门', '标准', '进阶', '平缓渐强'],
    );
    final male = GamePresetStore.builtIns.firstWhere(
      (item) => item.id == GamePresetStore.malePresetId,
    );
    final female = GamePresetStore.builtIns.firstWhere(
      (item) => item.id == GamePresetStore.femalePresetId,
    );
    for (final preset in <GamePreset>[male, female]) {
      expect(preset.durationSeconds, 10);
      expect(preset.startStrength, 1);
      expect(preset.maxStrength, 20);
      expect(preset.increaseEverySeconds, 1);
      expect(preset.waveformId, smoothRampWaveformId);
      expect(GamePresetStore.isExperiencePreset(preset.id), isTrue);
    }
    expect(male.increaseBy, 2);
    expect(female.increaseBy, 1);
    final defaultPreset = GamePresetStore.builtIns.firstWhere(
      (item) => item.id == GamePresetStore.defaultPresetId,
    );
    expect(defaultPreset.name, '默认挑战');
    expect(defaultPreset.durationSeconds, 45);
    expect(defaultPreset.startStrength, 1);
    expect(defaultPreset.maxStrength, 90);
    expect(defaultPreset.increaseEverySeconds, 1);
    expect(defaultPreset.increaseBy, 2);
    expect(defaultPreset.waveformId, smoothRampWaveformId);
    expect(GamePresetStore.isExperiencePreset(defaultPreset.id), isFalse);
    final smoothRamp = GamePresetStore.builtIns.last;
    expect(smoothRamp.durationSeconds, 60);
    expect(smoothRamp.startStrength, 30);
    expect(smoothRamp.maxStrength, 180);
    expect(smoothRamp.increaseEverySeconds, 1);
    expect(smoothRamp.increaseBy, 2);
    expect(smoothRamp.waveformId, smoothRampWaveformId);
  });

  test('自定义预设可以保存、覆盖和删除', () async {
    const first = GamePreset(
      id: 'custom-1',
      name: '比赛配置',
      durationSeconds: 60,
      startStrength: 10,
      maxStrength: 60,
      increaseEverySeconds: 10,
      increaseBy: 5,
      waveformId: 'coyote-pulse-111',
      category: GamePresetCategory.heart,
      custom: true,
    );
    await GamePresetStore.save(first);
    expect(await GamePresetStore.loadCustom(), hasLength(1));

    final replacement = GamePreset(
      id: first.id,
      name: first.name,
      durationSeconds: 90,
      startStrength: first.startStrength,
      maxStrength: 80,
      increaseEverySeconds: first.increaseEverySeconds,
      increaseBy: first.increaseBy,
      waveformId: first.waveformId,
      category: first.category,
      custom: true,
    );
    await GamePresetStore.save(replacement);
    final loaded = await GamePresetStore.loadCustom();
    expect(loaded, hasLength(1));
    expect(loaded.single.durationSeconds, 90);
    expect(loaded.single.maxStrength, 80);
    expect(loaded.single.category, GamePresetCategory.heart);

    await GamePresetStore.delete(first.id);
    expect(await GamePresetStore.loadCustom(), isEmpty);
  });

  test('旧版自定义预设默认归入耐久挑战', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'game_config_presets':
          '[{"id":"custom-legacy","name":"旧配置","durationSeconds":60,'
          '"startStrength":10,"maxStrength":60,"increaseEverySeconds":10,'
          '"increaseBy":5,"waveformId":"coyote-pulse-111","custom":true}]',
    });

    final loaded = await GamePresetStore.loadCustom();

    expect(loaded.single.category, GamePresetCategory.endurance);
  });
}
