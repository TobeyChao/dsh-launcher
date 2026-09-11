import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

/// 开机自启(launch_at_startup 包装)。测试可替换 [instance]。
class AutoLaunch {
  AutoLaunch();

  static AutoLaunch instance = AutoLaunch();

  static bool _setup = false;

  static LaunchAtStartup get _launcher {
    if (!_setup) {
      LaunchAtStartup.instance.setup(
        appName: 'DSH Launcher',
        appPath: Platform.resolvedExecutable,
      );
      _setup = true;
    }
    return LaunchAtStartup.instance;
  }

  Future<bool> get isEnabled async => _launcher.isEnabled();

  /// debug 模式不写登录项(避免开发时污染系统,对齐 FlClash/ct-tool)。
  Future<void> updateStatus(bool enabled) async {
    if (kDebugMode) return;
    if (await isEnabled == enabled) return;
    if (enabled) {
      if (Platform.isMacOS) {
        await Directory('${Platform.environment['HOME']}/Library/LaunchAgents')
            .create(recursive: true);
      }
      await _launcher.enable();
    } else {
      await _launcher.disable();
    }
  }
}
