enum LogLevel { info, warn, error }

/// 日志来源:SYS=启动器自身,WEB=dsh web,DEV=dev:web 构建,UPG=升级流程。
enum LogSource { sys, web, dev, upg }

extension LogSourceLabel on LogSource {
  String get label => switch (this) {
        LogSource.sys => 'SYS',
        LogSource.web => 'WEB',
        LogSource.dev => 'DEV',
        LogSource.upg => 'UPG',
      };
}

class LogEntry {
  LogEntry(this.level, this.message, {this.source = LogSource.sys})
      : time = DateTime.now();

  final DateTime time;
  final LogLevel level;
  final String message;
  final LogSource source;

  String get timestamp {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}
