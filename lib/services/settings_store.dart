import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 启动器配置:DSH 仓库路径 / 端口 / 开发模式 / 自启 / 托盘常驻。
class SettingsStore extends ChangeNotifier {
  static const kRepoPath = 'repo_path';
  static const kPort = 'port';
  static const kDevMode = 'dev_mode';
  static const kAutoStart = 'auto_start';
  static const kTrayResident = 'tray_resident';
  static const kDefaultPort = 3080;

  String repoPath = '';
  int port = kDefaultPort;
  bool devMode = false;
  bool autoStart = false;
  bool trayResident = true;
  bool _loaded = false;

  /// 开发期默认值探测:常见位置存在 .git 才采用,否则留空由用户配置。
  /// 依次尝试 `$DSH_HARNESS_PATH`,以及当前用户主目录下的常见 checkout 位置;
  /// 不写死任何机器的绝对路径。
  static String inferDefaultRepo() {
    final override = Platform.environment['DSH_HARNESS_PATH']?.trim();
    if (override != null && override.isNotEmpty) {
      if (Directory('$override/.git').existsSync()) return override;
    }
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    if (home.isEmpty) return '';
    final sep = Platform.pathSeparator;
    for (final candidate in [
      '$home${sep}Proj${sep}deepseek-harness',
      '$home${sep}deepseek-harness',
      '$home${sep}source${sep}deepseek-harness',
    ]) {
      if (Directory('$candidate/.git').existsSync()) return candidate;
    }
    return '';
  }

  /// 仓库路径有效:非空且目录含 .git。
  bool get repoValid {
    if (repoPath.isEmpty) return false;
    try {
      return Directory('$repoPath/.git').existsSync();
    } catch (_) {
      return false;
    }
  }

  String get baseUrl => 'http://127.0.0.1:$port';

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    repoPath = prefs.getString(kRepoPath) ?? inferDefaultRepo();
    port = prefs.getInt(kPort) ?? kDefaultPort;
    devMode = prefs.getBool(kDevMode) ?? false;
    autoStart = prefs.getBool(kAutoStart) ?? false;
    trayResident = prefs.getBool(kTrayResident) ?? true;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setRepoPath(String value) async {
    repoPath = value;
    await _save(kRepoPath, value);
  }

  Future<void> setPort(int value) async {
    port = value;
    await _save(kPort, value);
  }

  Future<void> setDevMode(bool value) async {
    devMode = value;
    await _save(kDevMode, value);
  }

  Future<void> setAutoStart(bool value) async {
    autoStart = value;
    await _save(kAutoStart, value);
  }

  Future<void> setTrayResident(bool value) async {
    trayResident = value;
    await _save(kTrayResident, value);
  }

  Future<void> _save(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    switch (value) {
      case final String v:
        await prefs.setString(key, v);
      case final int v:
        await prefs.setInt(key, v);
      case final bool v:
        await prefs.setBool(key, v);
    }
    notifyListeners();
  }
}
