import 'dart:io';

/// Shared environment for GUI launches and managed command trees.
class DesktopProcess {
  static Map<String, String> environment = buildEnvironment();

  static Map<String, String> buildEnvironment({
    Map<String, String>? source,
    bool? macOS,
  }) {
    final env = Map<String, String>.from(source ?? Platform.environment);
    if (macOS ?? Platform.isMacOS) {
      final home = env['HOME'];
      env['PATH'] = <String>{
        ...?env['PATH']?.split(':').where((entry) => entry.isNotEmpty),
        if (env['PNPM_HOME'] case final String path) path,
        if (home != null) '$home/Library/pnpm',
        if (home != null) '$home/.local/share/pnpm',
        if (home != null) '$home/.volta/bin',
        '/opt/homebrew/bin',
        '/usr/local/bin',
        '/usr/bin',
        '/bin',
        '/usr/sbin',
        '/sbin',
      }.join(':');
    }
    return env;
  }

  /// Finder does not inherit shell setup (nvm, fnm, asdf, etc.).
  static Future<void> initialize() async {
    if (!Platform.isMacOS) return;
    try {
      final result = await Process.run(
        Platform.environment['SHELL'] ?? '/bin/zsh',
        ['-ilc', 'printf "\\0%s\\0" "\$PATH"'],
      ).timeout(const Duration(seconds: 5));
      final parts = result.stdout.toString().split('\x00');
      if (result.exitCode == 0 && parts.length >= 3) {
        environment = buildEnvironment(
          source: {...Platform.environment, 'PATH': parts[parts.length - 2]},
        );
      }
    } catch (_) {
      // Common installation directories remain available if shell setup fails.
    }
  }

  static Future<void> killTree(int rootPid) async {
    if (rootPid <= 1 || rootPid == pid) return;
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/F', '/T', '/PID', '$rootPid']);
      return;
    }
    // Freeze parents before enumerating children so they cannot spawn more or
    // exit and reparent descendants while the tree is being collected.
    final stopped = <int>[];
    void signal(int target, ProcessSignal signal) {
      try {
        Process.killPid(target, signal);
      } on ProcessException {
        /* Gone. */
      }
    }

    Future<void> collect(int target) async {
      if (target <= 1 || target == pid || stopped.contains(target)) return;
      signal(target, ProcessSignal.sigstop);
      stopped.add(target);
      final result = await Process.run('/bin/ps', ['-axo', 'pid=,ppid=']);
      if (result.exitCode != 0) {
        throw StateError('Cannot enumerate process tree');
      }
      for (final line in result.stdout.toString().split('\n')) {
        final fields = line.trim().split(RegExp(r'\s+'));
        if (fields.length == 2 && int.tryParse(fields[1]) == target) {
          final child = int.tryParse(fields[0]);
          if (child != null) await collect(child);
        }
      }
    }

    try {
      await collect(rootPid);
      for (final target in stopped.reversed) {
        signal(target, ProcessSignal.sigkill);
      }
    } finally {
      for (final target in stopped) {
        signal(target, ProcessSignal.sigcont);
      }
    }
  }
}
