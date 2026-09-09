import 'dart:io';

import 'package:tray_manager/tray_manager.dart';

import 'web_service.dart';

/// 系统托盘:菜单随服务状态联动(升级中禁用服务操作)。
class TrayService with TrayListener {
  TrayService({
    required this.web,
    required this.onQuit,
    this.onShowWindow,
    this.onOpenBrowser,
  });

  final WebService web;
  final Future<void> Function() onQuit;

  final Future<void> Function()? onShowWindow;
  final Future<void> Function()? onOpenBrowser;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    trayManager.addListener(this);
    try {
      await trayManager.setIcon(
        Platform.isWindows ? 'assets/icons/tray_icon.ico' : 'assets/icons/tray_icon.png',
        isTemplate: Platform.isMacOS,
      );
      await trayManager.setToolTip('DSH Launcher');
    } catch (_) {
      // 托盘初始化失败不阻塞主界面。
    }
    web.addListener(_syncMenu);
    await _syncMenu();
  }

  Future<void> _syncMenu() async {
    if (!_initialized) return;
    final locked = web.upgradeLocked;
    final running = web.status == WebStatus.running;
    final external = web.status == WebStatus.externalRunning;
    final active = running || external;
    final toggleLabel = running ? '停止服务' : '启动服务';
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(
            key: 'open',
            label: '打开界面',
            disabled: !active || locked,
            onClick: (_) => onOpenBrowser?.call(),
          ),
          MenuItem(
            key: 'toggle',
            label: toggleLabel,
            disabled: external || locked,
            onClick: (_) {
              if (running) {
                web.stop();
              } else {
                web.start();
              }
            },
          ),
          MenuItem(
            key: 'restart',
            label: '重启服务',
            disabled: !running || locked,
            onClick: (_) => web.restart(),
          ),
          MenuItem(
            key: 'show',
            label: '显示启动器',
            onClick: (_) => onShowWindow?.call(),
          ),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: '退出', onClick: (_) => onQuit()),
        ],
      ),
    );
  }

  @override
  void onTrayIconMouseDown() {
    onShowWindow?.call();
  }

  @override
  void onTrayIconRightMouseDown() {
    // 左键显示窗口、右键弹菜单(与 FlClash/ct-tool 一致)。
    // ignore: deprecated_member_use
    trayManager.popUpContextMenu(bringAppToFront: true);
  }

  void dispose() {
    trayManager.removeListener(this);
    web.removeListener(_syncMenu);
  }
}
