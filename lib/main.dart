import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yokonex_ems_game/app/ems_game_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    await windowManager.ensureInitialized();
  }
  // Android flavor 决定启动哪个独立应用，底层设备和玩法能力继续共用。
  final app = appFlavor == 'heart'
      ? const EmsGameApp.heartExperience()
      : const EmsGameApp();
  runApp(ProviderScope(child: app));
}
