import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'services/settings_store.dart';
import 'services/desktop_process.dart';
import 'services/single_instance_lock.dart';

/// 顶层持有锁句柄:防止对象被 GC 后句柄关闭、锁提前释放(保持进程生命周期)。
final SingleInstanceLock _instanceLock = SingleInstanceLock();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // 单实例:已有实例在运行时直接退出(对齐 FlClash/ct-tool)。
  if (!await _instanceLock.acquire()) {
    exit(0);
  }

  await DesktopProcess.initialize();

  final settings = SettingsStore();
  await settings.load();

  final windowOptions = WindowOptions(
    // 对齐 ct-tool:720x460,内容区容纳概览/日志/设置三页。
    size: const Size(720, 460),
    minimumSize: const Size(720, 460),
    center: true,
    title: 'DSH Launcher',
    titleBarStyle: TitleBarStyle.normal,
    backgroundColor: const Color(0xFFF5F6F4),
  );
  await windowManager.waitUntilReadyToShow(windowOptions);
  await windowManager.setResizable(false);
  // 关闭事件由 app 层决策(托盘常驻 or 退出)。
  await windowManager.setPreventClose(true);

  runApp(LauncherApp(settings: settings));
  // MainFlutterWindow 先 order 后立即隐藏，让引擎启动但不暴露黑色 surface。
  await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
  await windowManager.show();
  await windowManager.focus();
}
