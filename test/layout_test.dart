import 'dart:io';

import 'package:dsh_launcher/services/auto_launch.dart';
import 'package:dsh_launcher/services/settings_store.dart';
import 'package:dsh_launcher/services/upgrade_service.dart';
import 'package:dsh_launcher/services/web_service.dart';
import 'package:dsh_launcher/ui/launcher_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 启动器窗口固定为 720x460(不可缩放),此处用真实尺寸回归三页是否溢出。
void main() {
  testWidgets('720x460 三页无溢出', (tester) async {
    tester.view.physicalSize = const Size(720, 460);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 设置页会查询 AutoLaunch 平台插件,测试环境换成假实现,避免真实调用挂起。
    final realAutoLaunch = AutoLaunch.instance;
    AutoLaunch.instance = _FakeAutoLaunch();
    addTearDown(() => AutoLaunch.instance = realAutoLaunch);

    final repo = Directory.systemTemp.createTempSync('dsh-layout-');
    addTearDown(() => repo.deleteSync(recursive: true));
    Directory('${repo.path}${Platform.pathSeparator}.git').createSync();

    SharedPreferences.setMockInitialValues({});
    final settings = SettingsStore();
    await settings.load();
    settings.repoPath = repo.path;
    final web = WebService(settings: settings)..status = WebStatus.running;
    final upgrade = UpgradeService(settings: settings, web: web)
      ..runner = (cmd, args, cwd) async => ProcessResult(0, 0, '', '');

    await tester.pumpWidget(
      MaterialApp(
        home: LauncherScreen(settings: settings, web: web, upgrade: upgrade),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull, reason: '概览页溢出');

    await tester.tap(find.text('日志').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull, reason: '日志页溢出');

    await tester.tap(find.text('设置').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull, reason: '设置页溢出');
  });
}

/// 测试用假自启实现:不触碰真实注册表。
class _FakeAutoLaunch extends AutoLaunch {
  @override
  Future<bool> get isEnabled async => false;

  @override
  Future<void> updateStatus(bool enabled) async {}
}
