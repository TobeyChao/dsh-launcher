import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'services/settings_store.dart';
import 'services/tray_service.dart';
import 'services/upgrade_service.dart';
import 'services/web_service.dart';
import 'theme.dart';
import 'ui/launcher_screen.dart';

class LauncherApp extends StatefulWidget {
  const LauncherApp({super.key, required this.settings});

  final SettingsStore settings;

  @override
  State<LauncherApp> createState() => _LauncherAppState();
}

class _LauncherAppState extends State<LauncherApp> with WindowListener {
  late final WebService _web;
  late final UpgradeService _upgrade;
  late final TrayService _tray;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _web = WebService(settings: widget.settings);
    _upgrade = UpgradeService(settings: widget.settings, web: _web);
    _tray = TrayService(
      web: _web,
      onQuit: _quit,
      onShowWindow: () async {
        await windowManager.setSkipTaskbar(false);
        await windowManager.show();
        await windowManager.focus();
      },
      onOpenBrowser: () => _web.openInBrowser(),
    );
    // 拦截系统退出请求:先停子进程再退出,避免孤儿进程。
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: () async {
        await _web.stop();
        return AppExitResponse.exit;
      },
    );
    windowManager.addListener(this);
    _web.init();
    // 启动时静默检查更新(fetch 失败只置更新卡不可用,不阻塞)。
    unawaited(_upgrade.checkForUpdates());
    _tray.init();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _lifecycleListener.dispose();
    _tray.dispose();
    _web.dispose();
    super.dispose();
  }

  Future<void> _quit() async {
    await _web.stop();
    await windowManager.destroy();
    exit(0);
  }

  @override
  void onWindowClose() async {
    if (widget.settings.trayResident) {
      // 托盘常驻:隐藏窗口并从任务栏消失(服务不中断)。
      await windowManager.hide();
      try {
        await windowManager.setSkipTaskbar(true);
      } catch (_) {
        // 个别平台不支持跳过任务栏时忽略。
      }
      return;
    }
    // 退出:3 秒兜底强退,避免任何残留。
    Future.delayed(const Duration(seconds: 3), () => exit(0));
    try {
      await _web.stop().timeout(const Duration(seconds: 8), onTimeout: () {});
      await windowManager.destroy();
    } finally {
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DSH Launcher',
      theme: buildDshTheme(),
      debugShowCheckedModeBanner: false,
      home: LauncherScreen(
        settings: widget.settings,
        web: _web,
        upgrade: _upgrade,
      ),
    );
  }
}
