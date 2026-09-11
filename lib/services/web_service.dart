import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/log_entry.dart';
import 'settings_store.dart';
import 'desktop_process.dart';

enum WebStatus { stopped, starting, running, failed, externalRunning }

/// 端口探测结果:空闲 / 已在运行(HTTP 有健康响应)/ 被无关进程占用。
enum _PortProbe { free, healthy, occupied }

/// 管理 dsh web(及可选 dev:web)子进程:启动/停止/重启、就绪检测、
/// 端口探测、日志流。进程树终结走 taskkill /T(Windows)。
class WebService extends ChangeNotifier {
  WebService({required this.settings, Future<void> Function(Uri uri)? openBrowser})
      : _openBrowser = openBrowser ?? _defaultOpenBrowser;

  final SettingsStore settings;

  /// 浏览器打开注入点(测试替换用);默认 url_launcher。
  final Future<void> Function(Uri uri) _openBrowser;

  WebStatus status = WebStatus.stopped;
  String? failureReason;
  final List<LogEntry> logs = [];

  /// 生产模式必须为 false:浏览器由 dsh 在 Loader settle 后自行打开(token URL),
  /// 启动器不重复打开(避免竞态与双开)。仅 e2e 测试置 true(追加 --no-open,
  /// 防止测试弹出真浏览器),此时启动器也不打开,只解析行维护 openUrl。
  bool suppressDshBrowser = false;

  Process? _webProcess;
  Process? _devProcess;
  bool _stopping = false;
  bool _upgradeLocked = false;
  DateTime? _startedAt;
  int? _webPid;
  String? _lastReadyUrl;
  Timer? _readyProbe;

  static final RegExp _ansiRe = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');
  static final RegExp _cmdEchoRe = RegExp(r'^\$\s');
  static const String _readyLinePrefix = 'dsh web:';

  DateTime? get startedAt => _startedAt;
  int? get webPid => _webPid;
  bool get upgradeLocked => _upgradeLocked;

  /// 打开界面用的地址:最近就绪的 token URL,没有则回退 baseUrl。
  String get openUrl => _lastReadyUrl ?? settings.baseUrl;

  static Future<void> _defaultOpenBrowser(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('无法打开 $uri');
    }
  }

  void init() {
    _append(LogLevel.info, 'DSH Launcher 就绪,点击开关启动 Web 服务', LogSource.sys);
  }

  /// 从 PATH 中解析 pnpm 可执行文件(Windows 为 `pnpm.cmd`);找不到返回 null。
  static String? resolvePnpm({String? envPath}) {
    final path = envPath ?? DesktopProcess.environment['PATH'] ?? '';
    final sep = Platform.isWindows ? ';' : ':';
    final names = Platform.isWindows
        ? const ['pnpm.cmd', 'pnpm.exe', 'pnpm']
        : const ['pnpm'];
    for (final dir in path.split(sep)) {
      if (dir.isEmpty) continue;
      for (final name in names) {
        final candidate = '$dir${Platform.pathSeparator}$name';
        if (File(candidate).existsSync()) return candidate;
      }
    }
    return null;
  }

  /// 解析 dsh 主目录:优先 `$DSH_HOME`,否则 `~/.dsh`,与 `@deepseek-ai/dsh-home-paths`
  /// 的优先级一致;无法解析返回 null。仅用于定位残留写锁所在目录,不读取数据。
  @visibleForTesting
  static String? resolveDshHome({Map<String, String>? env}) {
    final e = env ?? Platform.environment;
    final configured = e['DSH_HOME'];
    if (configured != null && configured.trim().isNotEmpty) {
      return _expandDshHome(configured.trim(), e);
    }
    final home = e['USERPROFILE'] ?? e['HOME'];
    if (home == null || home.isEmpty) return null;
    return '$home${Platform.pathSeparator}.dsh';
  }

  /// 展开 `~`/`~/`/`~\` 前缀(与 dsh-home-paths 的 expandHomePath 对齐)。
  static String _expandDshHome(String path, Map<String, String> env) {
    final home = env['USERPROFILE'] ?? env['HOME'];
    if (path == '~') return home ?? path;
    if (path.startsWith('~/') || path.startsWith('~\\')) {
      if (home == null || home.isEmpty) return path;
      return '$home${Platform.pathSeparator}${path.substring(2)}';
    }
    return path;
  }

  /// 清理 dsh home 根目录下已无持有者的 atomic-write 写锁(`*.lock`),返回清理数。
  ///
  /// dsh 的 `withFileLock` 有意不回收既有锁(注释:孤儿恢复是操作员动作),但本启动器
  /// 用 `taskkill /F` 强杀进程树;若恰逢 dsh 处于取锁窗口(已用 `wx` 建空 `.lock` 未写 PID)
  /// 或取锁后被强杀,会遗留空锁或死 PID 锁,导致下一次 boot 在写锁上等待超时、整树加载失败。
  /// 这里只删「确实无持有者」的锁:
  /// - 空 `.lock` 且已存续超过 [emptyLockGrace](活进程创建后立即写 PID,空文件只可能是被杀瞬间
  ///   遗留;宽限期避免与「刚创建尚未写入」的活锁竞态);
  /// - 内容为单个数字 PID 且该进程已退出。
  /// 含活 PID 的锁(如本机其他端口的 dsh 实例)一律保留。
  /// [pidAlive] 为进程存活探测(测试注入);默认按平台探测。
  @visibleForTesting
  static Future<int> cleanStaleDshLocks(
    Directory root, {
    Duration emptyLockGrace = const Duration(seconds: 5),
    Future<bool> Function(int pid)? pidAlive,
  }) async {
    if (!await root.exists()) return 0;
    var removed = 0;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.lock')) continue;
      if (await _isOrphanedLock(entity, emptyLockGrace, pidAlive)) {
        try {
          await entity.delete();
          removed++;
        } catch (_) {
          // 已被并发移除等,忽略。
        }
      }
    }
    return removed;
  }

  static Future<bool> _isOrphanedLock(
    File lock,
    Duration emptyLockGrace,
    Future<bool> Function(int pid)? pidAlive,
  ) async {
    try {
      final content = (await lock.readAsString()).trim();
      if (content.isEmpty) {
        final age = DateTime.now().difference((await lock.stat()).modified);
        return age > emptyLockGrace;
      }
      final pid = int.tryParse(content);
      if (pid == null) return false; // 非 atomic-write 锁(如 yarn.lock)
      final alive = pidAlive != null ? await pidAlive(pid) : await _pidAlive(pid);
      return !alive;
    } catch (_) {
      return false;
    }
  }

  /// 平台进程存活探测;无法确认时保守视为存活,避免误删活锁。
  static Future<bool> _pidAlive(int pid) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run(
          'tasklist',
          ['/FI', 'PID eq $pid', '/FO', 'CSV', '/NH'],
        );
        // 命中时输出含 `,"pid",` 字段;无匹配时是 INFO:... 不含该字段。
        return result.exitCode == 0 && result.stdout.toString().contains(',"$pid",');
      }
      final result = await Process.run('kill', ['-0', '$pid']);
      return result.exitCode == 0;
    } catch (_) {
      return true;
    }
  }

  /// 启动命令构造:``pnpm dsh web --port <port>``(dsh 默认自行打开浏览器;
  /// `suppressDshBrowser` 为 true 时追加 `--no-open`,测试用,避免弹出真浏览器)。
  /// 仓库无效返回 null。
  @visibleForTesting
  static ({String executable, List<String> args})? buildLaunchCommand({
    required String repoPath,
    required int port,
    required String pnpmPath,
    bool suppressDshBrowser = false,
  }) {
    if (repoPath.isEmpty || !Directory('$repoPath/.git').existsSync()) {
      return null;
    }
    return (
      executable: pnpmPath,
      args: [
        'dsh',
        'web',
        if (suppressDshBrowser) '--no-open',
        '--port',
        '$port',
      ],
    );
  }

  /// 解析就绪行 `dsh web: http://127.0.0.1:3080/?token=...` 中的 token URL。
  @visibleForTesting
  static Uri? parseReadyUrl(String line) {
    if (!line.contains(_readyLinePrefix)) return null;
    final match = RegExp(r'dsh web:\s*(https?://\S+)').firstMatch(line);
    if (match == null) return null;
    try {
      return Uri.parse(match.group(1)!);
    } catch (_) {
      return null;
    }
  }

  /// 剥离 ANSI 转义序列。
  @visibleForTesting
  static String stripAnsi(String input) => input.replaceAll(_ansiRe, '');

  /// 判定一行子进程输出的日志级别。
  ///
  /// - 命令回显行(以 `$ ` 开头,如 pnpm 回显的 `$ node ...`)一律视为 info,即使走 stderr:
  ///   命令回显只是「将要执行什么」,不是错误;
  /// - 其余:来自 stderr,或含 error/exception/traceback 关键字 → error;
  /// - 其余 → info。
  @visibleForTesting
  static LogLevel classifyLine(String line, {required bool stderr}) {
    if (_cmdEchoRe.hasMatch(line)) return LogLevel.info;
    final lower = line.toLowerCase();
    return stderr ||
            lower.contains('error') ||
            lower.contains('exception') ||
            lower.contains('traceback')
        ? LogLevel.error
        : LogLevel.info;
  }

  Future<void> start() async {
    if (_webProcess != null || status == WebStatus.starting) return;
    if (_upgradeLocked) return;
    if (!settings.repoValid) {
      _fail(
        'DSH 仓库无效:${settings.repoPath.isEmpty ? '未配置仓库路径' : settings.repoPath}\n'
        '请在设置中选择包含 .git 的 dsh checkout。',
      );
      return;
    }
    final probe = await _probePort(settings.port);
    if (probe == _PortProbe.healthy) {
      status = WebStatus.externalRunning;
      _append(
        LogLevel.warn,
        '端口 ${settings.port} 已有运行中的服务,切换为「外部已运行」;「打开界面」可直接访问',
        LogSource.sys,
      );
      notifyListeners();
      return;
    }
    if (probe == _PortProbe.occupied) {
      _fail('端口 ${settings.port} 被其他程序占用,请先释放端口或修改设置');
      return;
    }

    _setStatus(WebStatus.starting);
    _append(LogLevel.info, '启动 Web 服务…', LogSource.sys);
    await _cleanStaleDshLocks();
    final pnpm = resolvePnpm();
    if (pnpm == null) {
      _fail('未在 PATH 中找到 pnpm,请安装 pnpm 后重试');
      return;
    }
    final launch = buildLaunchCommand(
      repoPath: settings.repoPath,
      port: settings.port,
      pnpmPath: pnpm,
      suppressDshBrowser: suppressDshBrowser,
    );
    if (launch == null) {
      _fail('仓库路径无效,无法构造启动命令');
      return;
    }

    try {
      final proc = await Process.start(
        launch.executable,
        launch.args,
        workingDirectory: settings.repoPath,
        environment: _childEnvironment(),
        runInShell: false,
      );
      _webProcess = proc;
      _webPid = proc.pid;
      _startedAt = DateTime.now();
      _lastReadyUrl = null;
      _append(LogLevel.info, 'dsh web 已启动 (PID ${proc.pid}),等待就绪…', LogSource.sys);
      _pipeStream(proc.stdout, LogSource.web);
      _pipeStream(proc.stderr, LogSource.web, stderr: true);
      unawaited(proc.exitCode.then(_onWebExit));
      if (settings.devMode) {
        await _startDev();
      } else {
        _devProcess = null;
      }
    } catch (e) {
      _fail('无法启动 dsh web 进程:$e');
      return;
    }
    // 兜底:就绪行未捕获时,端口探测到健康响应也判定 running。
    _startReadyProbe();
  }

  Map<String, String> _childEnvironment() {
    final env = Map<String, String>.from(DesktopProcess.environment);
    // 日志面板不解析控制字符,gits/pnpm 挂起时快速返回。
    env['NO_COLOR'] = '1';
    env['TERM'] = 'dumb';
    env['GIT_TERMINAL_PROMPT'] = '0';
    return env;
  }

  /// 启动前回收 dsh home 的孤儿写锁,防止上次强杀遗留的 `.lock` 阻塞本次 boot。
  Future<void> _cleanStaleDshLocks() async {
    final home = resolveDshHome();
    if (home == null) return;
    final root = Directory(home);
    if (!await root.exists()) return;
    final removed = await cleanStaleDshLocks(root);
    if (removed > 0) {
      _append(
        LogLevel.warn,
        '已清理 $removed 个 dsh 残留写锁(上次进程强杀遗留),避免本次启动被写锁阻塞',
        LogSource.sys,
      );
    }
  }

  void _pipeStream(Stream<List<int>> stream, LogSource source, {bool stderr = false}) {
    stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _onOutput(line, source, stderr: stderr));
  }

  Future<void> _startDev() async {
    final pnpm = resolvePnpm();
    if (pnpm == null) {
      _append(LogLevel.error, '找不到 pnpm,无法启动 dev:web(热更新不可用)', LogSource.sys);
      return;
    }
    try {
      final proc = await Process.start(
        pnpm,
        ['run', 'dev:web'],
        workingDirectory: settings.repoPath,
        environment: _childEnvironment(),
        runInShell: false,
      );
      _devProcess = proc;
      _append(LogLevel.info, '开发模式:dev:web 构建已启动 (PID ${proc.pid})', LogSource.sys);
      _pipeStream(proc.stdout, LogSource.dev);
      _pipeStream(proc.stderr, LogSource.dev, stderr: true);
      unawaited(proc.exitCode.then(_onDevExit));
    } catch (e) {
      _append(LogLevel.error, 'dev:web 启动失败:$e', LogSource.sys);
    }
  }

  void _onOutput(String line, LogSource source, {bool stderr = false}) {
    final text = stripAnsi(line.trim());
    if (text.isEmpty) return;
    _append(classifyLine(text, stderr: stderr), text, source);

    final url = parseReadyUrl(text);
    if (url != null && source == LogSource.web) {
      // 只维护状态与 openUrl:浏览器由 dsh 自行打开(Loader settle 后,token URL),
      // 启动器不重复打开。行可能晚于健康探测几秒,状态等到再判。
      _lastReadyUrl = url.toString();
      if (status == WebStatus.starting) {
        _setStatus(WebStatus.running);
        _append(LogLevel.info, 'Web 服务已就绪(认证 URL):$_lastReadyUrl', LogSource.sys);
      }
    }
  }

  /// 打开界面(用最近 token URL,无则 baseUrl);失败仅记日志。
  Future<void> openInBrowser() async {
    await _openBrowserSafe(Uri.parse(openUrl));
  }

  Future<void> _openBrowserSafe(Uri uri) async {
    try {
      await _openBrowser(uri);
    } catch (e) {
      _append(LogLevel.error, '打开浏览器失败:$e(可手动访问 $uri)', LogSource.sys);
    }
  }

  void _startReadyProbe() {
    _stopReadyProbe();
    var attempts = 0;
    _readyProbe = Timer.periodic(const Duration(seconds: 1), (timer) {
      attempts++;
      if (status != WebStatus.starting) {
        _stopReadyProbe();
        return;
      }
      if (attempts > 60) {
        _stopReadyProbe();
        _append(
          LogLevel.warn,
          '等待就绪超时(60s),服务可能异常,请查看日志;可手动访问 ${settings.baseUrl}',
          LogSource.sys,
        );
        return;
      }
      unawaited(_checkHealth().then((healthy) {
        if (!healthy || status != WebStatus.starting) return;
        _stopReadyProbe();
        // 健康探测只兜底状态显示(浏览器打开由 dsh 负责);认证 URL 行仍会
        // 随后到达并更新 openUrl("打开界面"按钮使用)。
        _setStatus(WebStatus.running);
        _append(LogLevel.info, 'Web 服务已就绪:${settings.baseUrl}', LogSource.sys);
      }));
    });
  }

  Future<bool> _checkHealth() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final request = await client
          .getUrl(Uri.parse('http://127.0.0.1:${settings.port}/'))
          .timeout(const Duration(seconds: 1));
      final response = await request.close().timeout(const Duration(seconds: 1));
      await response.drain<void>();
      return response.statusCode < 500;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  void _stopReadyProbe() {
    _readyProbe?.cancel();
    _readyProbe = null;
  }

  Future<void> stop() async {
    _stopping = true;
    final procs = <Process>[?_webProcess, ?_devProcess];
    if (procs.isEmpty) {
      _stopping = false;
      if (status != WebStatus.stopped && status != WebStatus.externalRunning) {
        _setStatus(WebStatus.stopped);
      }
      return;
    }
    _append(LogLevel.warn, '正在停止 Web 服务…', LogSource.sys);
    for (final proc in procs) {
      await _killTree(proc.pid);
    }
    for (final proc in procs) {
      try {
        await proc.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        await _killTree(proc.pid);
      }
    }
    _stopping = false;
    _stopReadyProbe();
    _startedAt = null;
    _webPid = null;
    // 兜底保证:进程树杀完后端口仍被监听(残留子进程)时,找到监听者并终结。
    await _ensurePortReleased();
    // 退出处理器通常已把状态置停;兜底一次,外部模式不覆盖。
    if (status != WebStatus.stopped && status != WebStatus.externalRunning) {
      _setStatus(WebStatus.stopped);
    }
  }

  /// 确保服务端口不再被监听。仅在本启动器刚停止自己管理的服务后调用;
  /// 端口上的残留监听必然来自本次子进程树,清理是安全的。
  Future<void> _ensurePortReleased() async {
    for (var attempt = 0; attempt < 10; attempt++) {
      if (!await _portListening(settings.port)) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final pid = await _listenerPid(settings.port);
    if (pid != null) {
      _append(
        LogLevel.warn,
        '端口 ${settings.port} 仍有残留监听(PID $pid),已强制清理',
        LogSource.sys,
      );
      await _killTree(pid);
    }
  }

  Future<bool> _portListening(int port) async {
    try {
      final socket = await Socket.connect('127.0.0.1', port,
          timeout: const Duration(milliseconds: 300));
      socket.destroy();
      return true;
    } on SocketException {
      return false;
    } catch (_) {
      return true;
    }
  }

  /// 找到监听本端口的进程 PID(netstat 解析);未找到返回 null。
  Future<int?> _listenerPid(int port) async {
    try {
      if (!Platform.isWindows) return null;
      final result = await Process.run('netstat', ['-ano', '-p', 'tcp']);
      final pattern =
          RegExp('127\\.0\\.0\\.1:$port\\s+\\S+\\s+LISTENING\\s+(\\d+)');
      for (final line in result.stdout.toString().split('\n')) {
        final match = pattern.firstMatch(line);
        if (match != null) return int.tryParse(match.group(1)!);
      }
    } catch (_) {
      // netstat 不可用时放弃兜底,保留 WARN 出现前的主清理路径。
    }
    return null;
  }

  Future<void> restart() async {
    if (_upgradeLocked) return;
    await stop();
    await start();
  }

  /// 升级期间锁定服务操作(启动/停止/重启一律拒绝)。
  void setUpgradeLocked(bool value) {
    _upgradeLocked = value;
    notifyListeners();
  }

  Future<void> _onWebExit(int code) async {
    _webProcess = null;
    _stopReadyProbe();
    if (_stopping) {
      _append(LogLevel.info, 'dsh web 已退出,端口 ${settings.port} 已释放', LogSource.sys);
      if (status != WebStatus.stopped && status != WebStatus.externalRunning) {
        _setStatus(WebStatus.stopped);
      }
      return;
    }
    if (status == WebStatus.starting) {
      _fail('dsh web 启动失败(退出码 $code),请查看日志');
    } else if (status == WebStatus.running) {
      _fail('dsh web 意外退出(退出码 $code)');
    }
  }

  Future<void> _onDevExit(int code) async {
    _devProcess = null;
    if (_stopping) return;
    _append(
      LogLevel.warn,
      'dev:web 构建已退出(退出码 $code),产物链已过期,客户端插件热更新停止;Web 服务继续运行',
      LogSource.sys,
    );
  }

  /// 按平台终结完整进程树。
  static Future<void> _killTree(int pid) => DesktopProcess.killTree(pid);

  void _fail(String reason) {
    failureReason = reason;
    _append(LogLevel.error, reason, LogSource.sys);
    _setStatus(WebStatus.failed);
  }

  void _setStatus(WebStatus next) {
    status = next;
    notifyListeners();
  }

  void _append(LogLevel level, String message, LogSource source) {
    logs.add(LogEntry(level, message, source: source));
    if (logs.length > 500) logs.removeRange(0, logs.length - 500);
    notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  String get logText =>
      logs.map((e) => '${e.timestamp} [${e.level.name}] ${e.source.label} ${e.message}').join('\n');

  Future<_PortProbe> _probePort(int port) async {
    try {
      final socket = await Socket.connect(
        '127.0.0.1',
        port,
        timeout: const Duration(milliseconds: 600),
      );
      socket.destroy();
    } on SocketException {
      return _PortProbe.free;
    } catch (_) {
      return _PortProbe.free;
    }
    // 有监听:试 HTTP 健康判定,不再区分 2xx/4xx——能响应即视为已在运行,
    // 只有监听但无法完成 HTTP 交换才判为被无关进程占用。
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final request =
          await client.getUrl(Uri.parse('http://127.0.0.1:$port/')).timeout(const Duration(seconds: 1));
      await request.close().timeout(const Duration(seconds: 1));
      return _PortProbe.healthy;
    } catch (_) {
      return _PortProbe.occupied;
    } finally {
      client.close(force: true);
    }
  }

  @override
  void dispose() {
    _stopReadyProbe();
    _webProcess?.kill();
    _devProcess?.kill();
    super.dispose();
  }
}
