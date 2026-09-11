import 'dart:convert';
import 'dart:io';

import 'package:dsh_launcher/services/desktop_process.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Finder PATH includes pnpm and both Homebrew locations', () {
    final env = DesktopProcess.buildEnvironment(
      source: {
        'HOME': '/Users/test user',
        'PATH': '/usr/bin:/bin',
        'PNPM_HOME': '/custom/pnpm',
      },
      macOS: true,
    );
    final paths = env['PATH']!.split(':');
    expect(paths.first, '/usr/bin');
    expect(
      paths,
      containsAll([
        '/custom/pnpm',
        '/Users/test user/Library/pnpm',
        '/opt/homebrew/bin',
        '/usr/local/bin',
      ]),
    );
    expect(paths.toSet().length, paths.length);
  });

  test('Windows environment is preserved', () {
    const source = {'PATH': r'C:\Windows;C:\pnpm'};
    expect(
      DesktopProcess.buildEnvironment(source: source, macOS: false),
      source,
    );
  });

  test('stopping a Unix tree closes descendant output and exits parent', () async {
    final process = await Process.start('/bin/sh', [
      '-c',
      'sleep 120 & echo \$!; wait',
    ]);
    final lines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final output = <String>[];
    final finished = lines.forEach(output.add);
    try {
      for (var i = 0; i < 100 && output.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(output, isNotEmpty);
      await DesktopProcess.killTree(process.pid);
      await process.exitCode.timeout(const Duration(seconds: 5));
      // sleep inherits stdout; closing it verifies descendants were killed too.
      await finished.timeout(const Duration(seconds: 5));
    } finally {
      process.kill(ProcessSignal.sigkill);
      if (output.isNotEmpty) {
        Process.killPid(int.parse(output.first), ProcessSignal.sigkill);
      }
    }
  }, skip: Platform.isWindows);
}
