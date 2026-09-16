import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum GameVisualStyle { scoreboard, arcade }

extension GameVisualStyleX on GameVisualStyle {
  String get label => switch (this) {
    GameVisualStyle.scoreboard => '竞技',
    GameVisualStyle.arcade => '街机',
  };
}

final gameVisualStyleProvider =
    NotifierProvider<GameVisualStyleController, GameVisualStyle>(
      GameVisualStyleController.new,
    );

class GameVisualStyleController extends Notifier<GameVisualStyle> {
  static const String _preferenceKey = 'game_visual_style';

  @override
  GameVisualStyle build() {
    unawaited(_load());
    return GameVisualStyle.scoreboard;
  }

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_preferenceKey);
    if (saved == null) return;
    final style = GameVisualStyle.values.where((item) => item.name == saved);
    if (style.isNotEmpty) state = style.first;
  }

  Future<void> setStyle(GameVisualStyle style) async {
    if (state == style) return;
    // 视觉皮肤与设备控制状态分离，切换时不会影响正在运行的挑战。
    state = style;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferenceKey, style.name);
  }
}

class GameVisualStyleSwitch extends ConsumerWidget {
  const GameVisualStyleSwitch({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(gameVisualStyleProvider);
    return SegmentedButton<GameVisualStyle>(
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        minimumSize: WidgetStatePropertyAll(Size(compact ? 54 : 68, 36)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10),
        ),
      ),
      segments: <ButtonSegment<GameVisualStyle>>[
        ButtonSegment<GameVisualStyle>(
          value: GameVisualStyle.scoreboard,
          icon: compact ? const Icon(Icons.scoreboard, size: 17) : null,
          label: Text(compact ? '竞技' : '竞技计分台'),
        ),
        ButtonSegment<GameVisualStyle>(
          value: GameVisualStyle.arcade,
          icon: compact ? const Icon(Icons.sports_esports, size: 17) : null,
          label: Text(compact ? '街机' : '街机电流场'),
        ),
      ],
      selected: <GameVisualStyle>{style},
      onSelectionChanged: (value) =>
          ref.read(gameVisualStyleProvider.notifier).setStyle(value.single),
    );
  }
}

ThemeData buildGameTheme(GameVisualStyle style) {
  final arcade = style == GameVisualStyle.arcade;
  final scheme = arcade
      ? const ColorScheme.dark(
          primary: Color(0xfff4ff4a),
          onPrimary: Color(0xff101310),
          secondary: Color(0xff4fffd7),
          onSecondary: Color(0xff101310),
          error: Color(0xffffb020),
          onError: Color(0xff101310),
          surface: Color(0xff171a17),
          onSurface: Color(0xfff4f6ee),
          outline: Color(0xff4b544b),
        )
      : const ColorScheme.light(
          primary: Color(0xff111312),
          onPrimary: Colors.white,
          secondary: Color(0xffdfff43),
          onSecondary: Color(0xff101310),
          error: Color(0xffb56a00),
          onError: Colors.white,
          surface: Colors.white,
          onSurface: Color(0xff111312),
          outline: Color(0xff111312),
        );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: arcade ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: arcade
        ? const Color(0xff0f110f)
        : const Color(0xffe8ebea),
    fontFamily: arcade ? 'Consolas' : 'Microsoft YaHei UI',
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: arcade ? const Color(0xff101310) : Colors.white,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      shape: Border(
        bottom: BorderSide(
          color: arcade ? const Color(0xff4b544b) : const Color(0xff111312),
          width: arcade ? 1 : 3,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(
          color: arcade ? const Color(0xff4b544b) : const Color(0xff111312),
          width: arcade ? 1 : 2,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: const Color(0xff121514),
      indicatorColor: arcade ? const Color(0xfff4ff4a) : Colors.white,
      selectedIconTheme: const IconThemeData(color: Color(0xff101310)),
      selectedLabelTextStyle: TextStyle(
        color: arcade ? const Color(0xfff4ff4a) : Colors.white,
        fontWeight: FontWeight.w800,
      ),
      unselectedIconTheme: const IconThemeData(color: Color(0xff929a96)),
      unselectedLabelTextStyle: const TextStyle(color: Color(0xff929a96)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: arcade ? const Color(0xff121514) : Colors.white,
      indicatorColor: arcade
          ? const Color(0xfff4ff4a)
          : const Color(0xff111312),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(
            color: arcade ? const Color(0xff101310) : Colors.white,
          );
        }
        return IconThemeData(color: scheme.onSurface);
      }),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: arcade,
      fillColor: arcade ? const Color(0xff111411) : Colors.white,
      border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(
          color: arcade ? const Color(0xff4b544b) : const Color(0xff111312),
        ),
      ),
    ),
    dividerColor: arcade ? const Color(0xff394039) : const Color(0xff111312),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: arcade ? const Color(0xfff4ff4a) : const Color(0xffdfff43),
      linearTrackColor: arcade
          ? const Color(0xff2c312c)
          : const Color(0xffd9dedb),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return arcade ? const Color(0xfff4ff4a) : const Color(0xff111312);
          }
          return arcade ? const Color(0xff171a17) : Colors.white;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return arcade ? const Color(0xff101310) : Colors.white;
          }
          return scheme.onSurface;
        }),
      ),
    ),
  );
}
