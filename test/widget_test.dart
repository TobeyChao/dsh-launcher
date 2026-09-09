import 'dart:async';
import 'dart:io';

import 'package:dsh_launcher/services/auto_launch.dart';
import 'package:dsh_launcher/services/settings_store.dart';
import 'package:dsh_launcher/services/upgrade_service.dart';
import 'package:dsh_launcher/services/web_service.dart';
import 'package:dsh_launcher/ui/launcher_screen.dart';
import 'package:dsh_launcher/ui/pages/settings_page.dart';
import 'package:flutter/material.dart' hide StepState;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final List<String> _tempDirs = [];

/// 建一个含 .git 的临时"仓库"目录(供 repoValid 等校验通过)。
String tempRepo() {
  final temp = Directory.systemTemp.createTempSync('dsh-repo-');
  Directory('${temp.path}${Platform.pathSeparator}.git').createSync();
  _tempDirs.add(temp.path);
  return temp.path;
}

void main() {
  tearDownAll(() {
    for (final dir in _tempDirs) {
      try {
        Directory(dir).deleteSync(recursive: true);
      } catch (_) {
        // 清理失败不影响断言结果。
      }
    }
  });

  group('WebService 纯函数', () {
    test('stripAnsi 剥离 ANSI 转义', () {
      expect(WebService.stripAnsi('\u001B[32m绿色\u001B[0m'), '绿色');
      expect(WebService.stripAnsi('\u001B[1;34m[B\u001B[m'), '[B');
      expect(WebService.stripAnsi('plain'), 'plain');
    });

    test('parseReadyUrl 解析 token URL', () {
      const line = 'dsh web: http://127.0.0.1:3080/?token=abc123';
      final uri = WebService.parseReadyUrl(line);
      expect(uri, isNotNull);
      expect(uri!.toString(), 'http://127.0.0.1:3080/?token=abc123');
      expect(WebService.parseReadyUrl('其他输出行'), isNull);
      expect(WebService.parseReadyUrl('dsh web: 无 URL'), isNull);
    });

    test('buildLaunchCommand 构造启动命令', () {
      final repo = tempRepo();
      final command = WebService.buildLaunchCommand(
        repoPath: repo,
        port: 3080,
        pnpmPath: r'C:\pnpm\pnpm.cmd',
      );
      expect(command, isNotNull);
      expect(command!.executable, r'C:\pnpm\pnpm.cmd');
      expect(command.args, ['dsh', 'web', '--port', '3080']);
      // suppressDshBrowser:true 时追加 --no-open(测试防弹浏览器用)。
      final suppressed = WebService.buildLaunchCommand(
        repoPath: repo,
        port: 3080,
        pnpmPath: r'C:\pnpm\pnpm.cmd',
        suppressDshBrowser: true,
      );
      expect(suppressed!.args, ['dsh', 'web', '--no-open', '--port', '3080']);
      expect(
        WebService.buildLaunchCommand(repoPath: '', port: 3080, pnpmPath: 'pnpm'),
        isNull,
      );
    });

    test('resolvePnpm 从 PATH 找到 pnpm.cmd', () {
      if (!Platform.isWindows) return;
      final temp = Directory.systemTemp.createTempSync('dsh-pnpm-');
      addTearDown(() => temp.deleteSync(recursive: true));
      File('${temp.path}${Platform.pathSeparator}pnpm.cmd')
          .writeAsStringSync('@echo off');
      final found = WebService.resolvePnpm(
        envPath: 'C:\\missing\\dir;${temp.path};C:\\missing2',
      );
      expect(found, '${temp.path}${Platform.pathSeparator}pnpm.cmd');
    });
  });

  group('SettingsStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('默认值:端口 3080、托盘常驻开、开发模式关', () async {
      final store = SettingsStore();
      await store.load();
      expect(store.port, 3080);
      expect(store.trayResident, isTrue);
      expect(store.devMode, isFalse);
      expect(store.autoStart, isFalse);
    });

    test('持久化读写', () async {
      final store = SettingsStore();
      await store.load();
      await store.setPort(4000);
      await store.setDevMode(true);
      await store.setTrayResident(false);

      final reloaded = SettingsStore();
      await reloaded.load();
      expect(reloaded.port, 4000);
      expect(reloaded.devMode, isTrue);
      expect(reloaded.trayResident, isFalse);
    });

    test('repoValid:有 .git 才有效', () async {
      final store = SettingsStore();
      await store.load();
      store.repoPath = tempRepo();
      expect(store.repoValid, isTrue);
      final noGit = Directory.systemTemp.createTempSync('dsh-nogit-');
      _tempDirs.add(noGit.path);
      store.repoPath = noGit.path;
      expect(store.repoValid, isFalse);
    });
  });

  group('UpgradeService 状态机(注入 runner/executor)', () {
    Future<ProcessResult> ok(String cmd, List<String> args, String cwd) async {
      if (args.contains('status')) return ProcessResult(0, 0, '', '');
      if (args.first == 'rev-list') return ProcessResult(0, 0, '3\n', '');
      if (args.contains('--abbrev-ref')) return ProcessResult(0, 0, 'main\n', '');
      return ProcessResult(0, 0, 'abc1234\n', '');
    }

    UpgradeService makeService(
      SettingsStore settings,
      WebService web, {
      Future<int> Function(String, List<String>, void Function(String))? exec,
    }) {
      final upgrade = UpgradeService(settings: settings, web: web);
      upgrade.runner = ok;
      upgrade.executor = (exe, args, onLine) async {
        if (exec != null) return exec(exe, args, onLine);
        return 0;
      };
      return upgrade;
    }

    test('检查更新:落后数与 HEAD', () async {
      final settings = SettingsStore()..repoPath = tempRepo();
      final web = WebService(settings: settings);
      final upgrade = makeService(settings, web);
      await upgrade.checkForUpdates();
      expect(upgrade.checkState, CheckState.ok);
      expect(upgrade.aheadCount, 3);
      expect(upgrade.currentHead, 'abc1234');
      expect(upgrade.updateAvailable, isTrue);
    });

    test('检查更新失败:不可用不阻塞', () async {
      final settings = SettingsStore()..repoPath = tempRepo();
      final web = WebService(settings: settings);
      final upgrade = UpgradeService(settings: settings, web: web);
      upgrade.runner = (cmd, args, cwd) async => throw Exception('offline');
      await upgrade.checkForUpdates();
      expect(upgrade.checkState, CheckState.unavailable);
      expect(upgrade.phase, UpgradePhase.idle);
    });

    test('成功升级:五步全 done、阶段 done', () async {
      final settings = SettingsStore()..repoPath = tempRepo();
      final web = WebService(settings: settings);
      final upgrade = makeService(settings, web);
      upgrade.beginUpgrade();
      await _waitFor(() => upgrade.phase == UpgradePhase.done);
      expect(upgrade.phase, UpgradePhase.done);
      for (final step in upgrade.steps) {
        expect(step.state, StepState.done, reason: step.label);
      }
      expect(web.upgradeLocked, isFalse);
    });

    test('失败停在步骤,重试从失败步续跑', () async {
      final settings = SettingsStore()..repoPath = tempRepo();
      final web = WebService(settings: settings);
      var calls = 0;
      final upgrade = makeService(settings, web, exec: (exe, args, onLine) async {
        if (args.first == 'pull') {
          calls++;
          return calls == 1 ? 1 : 0;
        }
        return 0;
      });
      upgrade.beginUpgrade();
      await _waitFor(() => upgrade.phase == UpgradePhase.failed);
      expect(upgrade.failedIndex, 1);
      expect(upgrade.steps[0].state, StepState.done);
      expect(upgrade.steps[1].state, StepState.failed);
      expect(upgrade.steps[2].state, StepState.pending);

      upgrade.retry();
      await _waitFor(() => upgrade.phase == UpgradePhase.done);
      for (final step in upgrade.steps) {
        expect(step.state, StepState.done, reason: step.label);
      }
    });

    test('取消:置失败态且解锁服务', () async {
      final settings = SettingsStore()..repoPath = tempRepo();
      final web = WebService(settings: settings);
      var pullStarted = false;
      final upgrade = makeService(settings, web, exec: (exe, args, onLine) async {
        if (args.first == 'pull') {
          pullStarted = true;
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return 0;
        }
        return 0;
      });
      upgrade.beginUpgrade();
      await _waitFor(() => pullStarted);
      upgrade.cancel();
      await _waitFor(() => upgrade.phase == UpgradePhase.failed);
      expect(web.upgradeLocked, isFalse);
      expect(
        upgrade.steps.any((s) => s.state == StepState.failed),
        isTrue,
      );
    });
  });

  group('设置页交互', () {
    late AutoLaunch realAutoLaunch;

    setUp(() {
      realAutoLaunch = AutoLaunch.instance;
      AutoLaunch.instance = _FakeAutoLaunch();
    });

    tearDown(() {
      AutoLaunch.instance = realAutoLaunch;
    });

    testWidgets('服务运行中:仓库/端口禁用并提示', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsStore()..repoPath = tempRepo();
      await settings.load();
      final web = WebService(settings: settings)..status = WebStatus.running;

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SettingsPage(settings: settings, web: web))),
      );
      await tester.pump();

      final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(fields, isNotEmpty);
      for (final field in fields) {
        expect(field.enabled, isFalse);
      }
      expect(find.textContaining('先停止服务'), findsOneWidget);
    });

    testWidgets('启动器主屏构建冒烟', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsStore()..repoPath = tempRepo();
      await settings.load();
      final web = WebService(settings: settings);
      final upgrade = UpgradeService(settings: settings, web: web)
        ..runner = (cmd, args, cwd) async => ProcessResult(0, 0, '', '');

      await tester.pumpWidget(
        MaterialApp(
          home: LauncherScreen(settings: settings, web: web, upgrade: upgrade),
        ),
      );
      await tester.pump();
      expect(find.text('概览'), findsWidgets);
      expect(find.text('DSH Launcher'), findsOneWidget);
    });
  });
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('条件未满足');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// 测试用假自启实现:不触碰真实注册表。
class _FakeAutoLaunch extends AutoLaunch {
  @override
  Future<bool> get isEnabled async => false;

  @override
  Future<void> updateStatus(bool enabled) async {}
}
