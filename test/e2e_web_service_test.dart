import 'dart:io';

import 'package:dsh_launcher/services/settings_store.dart';
import 'package:dsh_launcher/services/desktop_process.dart';
import 'package:dsh_launcher/services/web_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真实端到端:spawn 本机 dsh checkout 的 `pnpm dsh web`,验证
/// 就绪行解析(openUrl 带 token)、状态流转与进程树终结(端口释放)。
///
/// 生产路径浏览器由 dsh 自行打开(openBrowser 默认 true,Loader settle 后
/// 用 token URL 打开);本测试置 suppressDshBrowser 以免弹出真浏览器,
/// 但不传 --no-open 的那条生产路径由 dsh 自身测试保证。
///
/// 固定使用 3180:每次运行可预测。启动前若发现残留监听且命令行匹配
/// 本测试启动的 dsh web(上一次运行遗留),先清理再跑;不换端口绕开。
/// 需要本机有 dsh checkout + pnpm。
void main() {
  // 仓库位置从环境变量读取,默认取用户主目录下的常见 checkout,避免写死机器路径。
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
  final repo = Platform.environment['DSH_E2E_REPO'] ??
      '$home${Platform.pathSeparator}Proj${Platform.pathSeparator}deepseek-harness';
  const port = 3180;

  test(
    '真实 dsh web:启动→就绪(token URL)→停止(端口释放)',
    () async {
      if (!Directory('$repo/.git').existsSync()) {
        markTestSkipped('本机无 dsh checkout,跳过真实 E2E');
        return;
      }
      await DesktopProcess.initialize();
      // dsh 的 Web 应用对同一 DSH_HOME 是单写者(~/.dsh/.credentials.yaml
      // 写锁,atomic-write 等待超时即失败);本机已有其他 dsh web 实例时
      // E2E 必须独占,明确跳过而非硬跑(非启动器缺陷,是 dsh 上游约束)。
      final otherInstance = await _findOtherDshWeb();
      if (otherInstance != null) {
        markTestSkipped(
          '本机已有 dsh web 实例运行(PID $otherInstance,共享 credentials 写锁),'
          'E2E 需独占运行:请先停止它(或稍后重跑)',
        );
        return;
      }
      await _preflightCleanup(port, repo);

      final settings = SettingsStore()
        ..repoPath = repo
        ..port = port;
      final web = WebService(settings: settings)..suppressDshBrowser = true;
      web.init();

      try {
        await web.start();
        // 就绪(就绪行或健康探测)最长等待 90s。
        final deadline = DateTime.now().add(const Duration(seconds: 90));
        while (web.status != WebStatus.running) {
          if (web.status == WebStatus.failed ||
              web.status == WebStatus.externalRunning) {
            fail('服务未进入 running:${web.status} ${web.failureReason ?? ''}\n日志:\n${web.logText}');
          }
          if (DateTime.now().isAfter(deadline)) {
            fail('等待就绪超时\n日志:\n${web.logText}');
          }
          await Future<void>.delayed(const Duration(seconds: 1));
        }

        // 认证 URL 行由 dsh 在 Loader settle 后打印,可能比健康探测晚几秒,
        // 到达后 openUrl 应带 token("打开界面"按钮使用)。
        final lineDeadline = DateTime.now().add(const Duration(seconds: 30));
        while (!web.openUrl.contains('token=')) {
          if (DateTime.now().isAfter(lineDeadline)) {
            fail('30s 内未解析到认证 URL\nopenUrl=${web.openUrl}\n日志:\n${web.logText}');
          }
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        expect(web.openUrl, startsWith('http://127.0.0.1:$port/'));
        expect(web.openUrl, contains('token='));

        // 端口确实可访问。
        expect(await _portOpen(port), isTrue);

        // 停止:进程树应被终结,端口释放。
        await web.stop();
        expect(web.status, WebStatus.stopped);
        expect(await _portOpen(port), isFalse,
            reason: '停止后端口应释放(残留会被 _ensurePortReleased 清理)');
      } finally {
        await web.stop();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// 预检:3180 若有监听,命令行为我们上次运行的残留(含 bin.ts web 与端口)
/// 则清理;否则明确报错(外部占用不该被我们杀掉)。
Future<void> _preflightCleanup(int port, String repo) async {
  final pid = await _listenerPid(port);
  if (pid == null) return;
  final commandLine = await _commandLine(pid);
  final isOurs = commandLine != null &&
      commandLine.contains('apps/cli/src/bin.ts') &&
      RegExp(r'\bweb\b').hasMatch(commandLine) &&
      commandLine.contains('--port') &&
      commandLine.contains('$port');
  if (!isOurs) {
    fail('端口 $port 被进程 $pid 占用(非本测试残留,不清理):$commandLine');
  }
  // 上一次运行遗留:先杀树再跑(根治,而不是换端口绕开)。
  await DesktopProcess.killTree(pid);
  await Future<void>.delayed(const Duration(seconds: 1));
  if (await _portOpen(port)) {
    fail('清理上一次运行残留失败(端口 $port 仍被占用)');
  }
}

/// 查找已运行的其他 dsh web 实例(node bin.ts "web")的 PID;无则返回 null。
Future<int?> _findOtherDshWeb() async {
  try {
    if (!Platform.isWindows) {
      final result = await Process.run('/bin/ps', ['-axo', 'pid=,command=']);
      for (final line in result.stdout.toString().split('\n')) {
        if (line.contains('bin.ts') && RegExp(r'\bweb\b').hasMatch(line)) {
          return int.tryParse(line.trim().split(RegExp(r'\s+')).first);
        }
      }
      return null;
    }
    final result = await Process.run('wmic',
        ['process', 'where', "name='node.exe'", 'get', 'processid,commandline', '/value']);
    if (result.exitCode != 0) return null;
    final text = result.stdout.toString();
    final chunks = text.split('CommandLine=');
    for (final chunk in chunks.skip(1)) {
      if (chunk.contains('bin.ts') && chunk.contains('"web"')) {
        final pidMatch = RegExp(r'ProcessId=(\d+)').firstMatch(chunk);
        if (pidMatch != null) return int.tryParse(pidMatch.group(1)!);
      }
    }
  } catch (_) {
    // wmic 不可用时视为无冲突,交给预检端口检查兜底。
  }
  return null;
}

Future<int?> _listenerPid(int port) async {
  if (!Platform.isWindows) {
    final result = await Process.run('/usr/sbin/lsof',
        ['-nP', '-tiTCP:$port', '-sTCP:LISTEN']);
    return int.tryParse(result.stdout.toString().trim().split('\n').first);
  }
  final result = await Process.run('netstat', ['-ano', '-p', 'tcp']);
  final pattern =
      RegExp('127\\.0\\.0\\.1:$port\\s+\\S+\\s+LISTENING\\s+(\\d+)');
  for (final line in result.stdout.toString().split('\n')) {
    final match = pattern.firstMatch(line);
    if (match != null) return int.tryParse(match.group(1)!);
  }
  return null;
}

Future<String?> _commandLine(int pid) async {
  try {
    if (!Platform.isWindows) {
      final result = await Process.run('/bin/ps', ['-p', '$pid', '-o', 'command=']);
      return result.exitCode == 0 ? result.stdout.toString() : null;
    }
    final result = await Process.run(
        'wmic', ['process', 'where', 'processid=$pid', 'get', 'commandline', '/value']);
    if (result.exitCode != 0) return null;
    return result.stdout.toString();
  } catch (_) {
    return null;
  }
}

Future<bool> _portOpen(int port) async {
  try {
    final socket = await Socket.connect('127.0.0.1', port,
        timeout: const Duration(milliseconds: 400));
    socket.destroy();
    return true;
  } on SocketException {
    return false;
  }
}
