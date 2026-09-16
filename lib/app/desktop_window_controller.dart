import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yokonex_ems_game/app/app_controller.dart';

final desktopWindowControllerProvider = Provider<void>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
  final controller = _DesktopWindowController(ref);
  unawaited(controller.initialize());
  ref.onDispose(controller.dispose);
});

class _DesktopWindowController with WindowListener {
  _DesktopWindowController(this.ref);
  final Ref ref;
  bool _closing = false;

  Future<void> initialize() async {
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
  }

  @override
  void onWindowClose() {
    if (_closing) return;
    unawaited(_shutdown());
  }

  Future<void> _shutdown() async {
    _closing = true;
    try {
      await ref
          .read(appControllerProvider.notifier)
          .emergencyStop()
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // 停机超时后仍需退出窗口，避免应用残留在后台。
    }
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  void dispose() => windowManager.removeListener(this);
}
