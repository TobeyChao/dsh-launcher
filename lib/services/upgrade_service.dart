import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/log_entry.dart';
import 'settings_store.dart';
import 'web_service.dart';

enum UpgradePhase { idle, checking, ready, running, done, failed }

enum CheckState { none, ok, unavailable }

enum UpgradeStepId { preflight, pull, install, build, restart }

enum StepState { pending, running, done, failed }

class UpgradeStepState {
  UpgradeStepState(this.id, this.label, this.detail)
      : state = StepState.pending;

  final UpgradeStepId id;
  final String label;
  final String detail;
  StepState state;
  String? note;
}

/// 升级流程:检查更新 + 五步 runner(预检/拉取/安装/构建/重启)。
/// 全部通过 git/pnpm 子进程实现,不依赖任何外部脚本。
class UpgradeService extends ChangeNotifier {
  UpgradeService({required this.settings, required this.web});

  final SettingsStore settings;
  final WebService web;

  /// 注入点:顺序执行一步并逐行回调输出,返回退出码。默认流式 spawn。
  @visibleForTesting
  Future<int> Function(String executable, List<String> args, void Function(String line) onLine)?
      executor;

  /// 注入点:快速命令(检查更新/预检/取 HEAD)。默认 Process.run。
  @visibleForTesting
  Future<ProcessResult> Function(String command, List<String> args, String cwd)? runner;

  UpgradePhase phase = UpgradePhase.idle;
  CheckState checkState = CheckState.none;
  int aheadCount = 0;
  String? currentHead;
  String? targetHead;
  String? branch;

  final List<UpgradeStepState> steps = [
    UpgradeStepState(UpgradeStepId.preflight, '预检', '工作区干净 · 服务已停止'),
    UpgradeStepState(UpgradeStepId.pull, '拉取', 'git pull --ff-only'),
    UpgradeStepState(UpgradeStepId.install, '安装', 'pnpm install'),
    UpgradeStepState(UpgradeStepId.build, '构建', 'pnpm run clean && pnpm run build'),
    UpgradeStepState(UpgradeStepId.restart, '重启', '重启服务并打开界面'),
  ];

  final List<LogEntry> logs = [];
  int _failedIndex = -1;
  bool _cancelled = false;
  bool _wasRunningBefore = false;
  Process? _currentProcess;
  String? _newHead;

  int get failedIndex => _failedIndex;
  bool get isRunning => phase == UpgradePhase.running;
  bool get updateAvailable => checkState == CheckState.ok && aheadCount > 0;

  /// 检查更新:git fetch + 落后数。失败置 unavailable,不阻塞启动器。
  Future<void> checkForUpdates() async {
    if (phase == UpgradePhase.running || phase == UpgradePhase.checking) return;
    phase = UpgradePhase.checking;
    notifyListeners();
    if (!settings.repoValid) {
      checkState = CheckState.unavailable;
      phase = UpgradePhase.idle;
      notifyListeners();
      return;
    }
    try {
      final fetch = await _run('git', ['fetch', 'origin']).timeout(const Duration(seconds: 30));
      if (fetch.exitCode != 0) throw StateError('git fetch 失败(${fetch.exitCode})');
      branch = (await _run('git', ['rev-parse', '--abbrev-ref', 'HEAD'])).stdout.trim();
      currentHead = (await _run('git', ['rev-parse', '--short', 'HEAD'])).stdout.trim();
      final behind = await _run('git', ['rev-list', '--count', 'HEAD..origin/$branch']);
      if (behind.exitCode != 0) throw StateError('无法比较远端(origin/$branch)');
      aheadCount = int.tryParse(behind.stdout.trim()) ?? 0;
      targetHead =
          (await _run('git', ['rev-parse', '--short', 'origin/$branch'])).stdout.trim();
      checkState = CheckState.ok;
    } catch (e) {
      checkState = CheckState.unavailable;
      _append(LogLevel.warn, '检查更新失败:$e(离线或仓库异常)', LogSource.sys);
    }
    phase = UpgradePhase.idle;
    notifyListeners();
  }

  /// 重新检查并返回是否有更新(按钮入口用;不发日志以外的提示)。
  Future<bool> refreshAndHasUpdate() async {
    await checkForUpdates();
    return updateAvailable;
  }

  /// 开始升级:预检时停止服务(由重启步决定是否恢复)并锁定服务操作。
  void beginUpgrade() {
    if (phase == UpgradePhase.running) return;
    _wasRunningBefore = web.status == WebStatus.running;
    _newHead = null;
    _cancelled = false;
    _failedIndex = -1;
    for (final step in steps) {
      step.state = StepState.pending;
      step.note = null;
    }
    web.setUpgradeLocked(true);
    phase = UpgradePhase.running;
    _append(LogLevel.info, '开始升级(${_headLabel()})…', LogSource.sys);
    notifyListeners();
    unawaited(_runSteps(0));
  }

  /// 从失败步骤重试(已成功的步骤不重跑)。
  void retry() {
    if (phase != UpgradePhase.failed || _failedIndex < 0) return;
    _cancelled = false;
    _failedIndex = -1;
    phase = UpgradePhase.running;
    _append(LogLevel.info, '从「${steps[_failedStepIndex()].label}」重试…', LogSource.sys);
    notifyListeners();
    unawaited(_runSteps(_failedStepIndex()));
  }

  int _failedStepIndex() {
    var index = 0;
    for (var i = 0; i < steps.length; i++) {
      if (steps[i].state == StepState.failed) {
        index = i;
        break;
      }
    }
    return index;
  }

  /// 取消:杀当前步骤进程树,置失败态,服务保持停止。
  void cancel() {
    if (phase != UpgradePhase.running) return;
    _cancelled = true;
    final proc = _currentProcess;
    if (proc != null) {
      unawaited(_killTree(proc.pid));
    }
  }

  Future<void> _runSteps(int startIndex) async {
    var exit = 0;
    for (var i = startIndex; i < steps.length; i++) {
      if (_cancelled) {
        _markFailed(i, '已取消');
        return;
      }
      final step = steps[i];
      step.state = StepState.running;
      notifyListeners();
      _append(LogLevel.info, '▶ ${step.label}:${step.detail}', LogSource.sys);
      exit = await _execStep(step, i);
      if (_cancelled) {
        _markFailed(i, '已取消');
        return;
      }
      if (exit != 0) {
        _markFailed(i, '退出码 $exit');
        return;
      }
      step.state = StepState.done;
      if (step.id == UpgradeStepId.pull) {
        _newHead = (await _run('git', ['rev-parse', '--short', 'HEAD'])).stdout.trim();
        step.note = _newHead;
      }
      notifyListeners();
    }
    // 全部成功
    _append(LogLevel.info, '升级完成:${_headLabel()} → ${_newHead ?? '?'}', LogSource.sys);
    phase = UpgradePhase.done;
    if (_wasRunningBefore) {
      await web.restart();
    } else {
      await web.openInBrowser();
    }
    web.setUpgradeLocked(false);
    notifyListeners();
  }

  void _markFailed(int index, String reason) {
    final step = steps[index];
    step.state = StepState.failed;
    step.note = reason;
    _failedIndex = index;
    phase = UpgradePhase.failed;
    _append(LogLevel.error, '「${step.label}」失败($reason),可重试或取消后手动启动服务', LogSource.sys);
    _currentProcess = null;
    web.setUpgradeLocked(false);
    notifyListeners();
  }

  Future<int> _execStep(UpgradeStepState step, int index) async {
    switch (step.id) {
      case UpgradeStepId.preflight:
        return _execPreflight();
      case UpgradeStepId.pull:
        return _execStreaming('git', ['pull', '--ff-only']);
      case UpgradeStepId.install:
        return _execPnpm(['install']);
      case UpgradeStepId.build:
        // 先清理残留产物,再完整构建(两条命令同属一步,任一失败即步骤失败)。
        final cleanExit = await _execPnpm(['run', 'clean']);
        if (cleanExit != 0) return cleanExit;
        return _execPnpm(['run', 'build']);
      case UpgradeStepId.restart:
        return 0; // 重启在 _runSteps 成功分支统一处理。
    }
  }

  Future<int> _execPreflight() async {
    final dirty = await _run('git', ['status', '--porcelain', '--untracked-files=no']);
    if (dirty.exitCode != 0) {
      _append(LogLevel.error, 'git status 失败(退出码 ${dirty.exitCode})', LogSource.sys);
      return dirty.exitCode;
    }
    if (dirty.stdout.trim().isNotEmpty) {
      final lines = dirty.stdout.trim().split('\n').take(10).join('\n  ');
      _append(LogLevel.error, '已跟踪树有未提交改动,阻止升级:\n  $lines', LogSource.sys);
      return 1;
    }
    // 预检通过:停服务(重启步按升级前状态恢复)。
    await web.stop();
    final stopped = web.status == WebStatus.stopped ||
        web.status == WebStatus.externalRunning;
    if (!stopped) {
      _append(LogLevel.error, '停止服务失败,中止升级', LogSource.sys);
      return 1;
    }
    _append(LogLevel.info, '预检通过:工作区干净,服务已停止', LogSource.sys);
    return 0;
  }

  Future<int> _execPnpm(List<String> args) async {
    final pnpm = WebService.resolvePnpm();
    if (pnpm == null) {
      _append(LogLevel.error, '找不到 pnpm,无法执行 pnpm ${args.join(' ')}', LogSource.sys);
      return 1;
    }
    return _execStreaming(pnpm, args);
  }

  Future<int> _execStreaming(String executable, List<String> args) async {
    final run = executor;
    if (run != null) {
      return run(executable, args, (line) => _append(LogLevel.info, line, LogSource.upg));
    }
    final env = Map<String, String>.from(Platform.environment);
    env['NO_COLOR'] = '1';
    env['TERM'] = 'dumb';
    env['GIT_TERMINAL_PROMPT'] = '0';
    try {
      final proc = await Process.start(
        executable,
        args,
        workingDirectory: settings.repoPath,
        environment: env,
        runInShell: false,
      );
      _currentProcess = proc;
      proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _append(LogLevel.info, line, LogSource.upg));
      proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _append(LogLevel.warn, line, LogSource.upg));
      final code = await proc.exitCode;
      _currentProcess = null;
      return code;
    } catch (e) {
      _append(LogLevel.error, '命令执行失败:$e', LogSource.sys);
      return 1;
    }
  }

  Future<ProcessResult> _run(String command, List<String> args) async {
    final injected = runner;
    if (injected != null) return injected(command, args, settings.repoPath);
    final env = Map<String, String>.from(Platform.environment);
    env['GIT_TERMINAL_PROMPT'] = '0';
    return Process.run(
      command,
      args,
      workingDirectory: settings.repoPath,
      environment: env,
      runInShell: false,
    );
  }

  String _headLabel() => currentHead ?? '?';

  String get headShort => currentHead ?? '';

  static Future<void> _killTree(int pid) async {
    try {
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/F', '/T', '/PID', '$pid']);
      } else {
        await Process.run('kill', ['-KILL', '$pid']);
      }
    } catch (_) {
      // 已退出等情况忽略。
    }
  }

  void _append(LogLevel level, String message, LogSource source) {
    logs.add(LogEntry(level, message, source: source));
    if (logs.length > 1000) logs.removeRange(0, logs.length - 1000);
    notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  String get logText =>
      logs.map((e) => '${e.timestamp} ${e.source.label} ${e.message}').join('\n');
}
