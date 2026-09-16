import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yokonex_ems_game/app/visual_style.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('视觉皮肤可以切换并保存', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(gameVisualStyleProvider), GameVisualStyle.scoreboard);
    await container
        .read(gameVisualStyleProvider.notifier)
        .setStyle(GameVisualStyle.arcade);

    expect(container.read(gameVisualStyleProvider), GameVisualStyle.arcade);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('game_visual_style'), 'arcade');
  });

  test('两套主题使用不同的明暗模式', () {
    expect(
      buildGameTheme(GameVisualStyle.scoreboard).brightness,
      Brightness.light,
    );
    expect(buildGameTheme(GameVisualStyle.arcade).brightness, Brightness.dark);
  });
}
