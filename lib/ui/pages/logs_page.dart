import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/log_entry.dart';
import '../../services/web_service.dart';
import '../../theme.dart';
import '../widgets/common.dart';

/// 日志页:实时滚动日志(带来源标记)+ 复制 / 清空 / 回到底部。
class LogsPage extends StatefulWidget {
  const LogsPage({super.key, required this.web});

  final WebService web;

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final _logController = ScrollController();
  bool _pinBottom = true;

  @override
  void initState() {
    super.initState();
    widget.web.addListener(_onWebChanged);
    _logController.addListener(_onLogScroll);
  }

  @override
  void dispose() {
    widget.web.removeListener(_onWebChanged);
    _logController.dispose();
    super.dispose();
  }

  void _onWebChanged() {
    if (mounted) setState(() {});
    if (_pinBottom) _jumpToBottom();
  }

  void _onLogScroll() {
    final pos = _logController.position;
    if (!pos.hasContentDimensions) return;
    final nearBottom = pos.pixels >= pos.maxScrollExtent - 24;
    if (nearBottom != _pinBottom) setState(() => _pinBottom = nearBottom);
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logController.hasClients) {
        _logController.jumpTo(_logController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _copyLogs() async {
    await Clipboard.setData(ClipboardData(text: widget.web.logText));
    if (!mounted) return;
    showDshToast(context, '日志已复制到剪贴板');
  }

  @override
  Widget build(BuildContext context) {
    final logs = widget.web.logs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('运行日志', style: dshPageTitleStyle),
              const Spacer(),
              DshButton.ghost('复制', onPressed: _copyLogs),
              const SizedBox(width: 6),
              DshButton.ghost('清空', onPressed: widget.web.clearLogs),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: dshLogBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: dshLogBorder),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22121A16),
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: logs.isEmpty
                      ? const Center(
                          child: Text(
                            '暂无日志,启动服务后这里会显示运行记录',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF5E7368),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _logController,
                          itemCount: logs.length,
                          itemBuilder: (_, i) => _logLine(logs[i]),
                        ),
                ),
                if (!_pinBottom)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: FloatingActionButton.small(
                      heroTag: 'log-back-to-bottom',
                      backgroundColor: dshPrimary,
                      foregroundColor: Colors.white,
                      tooltip: '回到底部',
                      onPressed: () {
                        setState(() => _pinBottom = true);
                        _jumpToBottom();
                      },
                      child: const Icon(Icons.arrow_downward, size: 18),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const DshFooterHint(
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: dshInk3),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '日志保留最近 500 条;开发模式开启时以 DEV/WEB 区分来源',
                    style: TextStyle(fontSize: 12, color: dshInk3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _logLine(LogEntry e) {
    final (tag, color) = switch (e.level) {
      LogLevel.info => ('[INFO]', const Color(0xFF7FD6A8)),
      LogLevel.warn => ('[WARN]', const Color(0xFFE5C078)),
      LogLevel.error => ('[ERROR]', const Color(0xFFE8837F)),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 142,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${e.timestamp} ',
                    style: dshMono.copyWith(
                      fontSize: 12,
                      color: const Color(0xFF6E8277),
                    ),
                  ),
                  TextSpan(
                    text: '$tag ',
                    style: dshMono.copyWith(fontSize: 12, color: color),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              e.source.label,
              style: dshMono.copyWith(
                fontSize: 11,
                color: const Color(0xFF5E7A8C),
              ),
            ),
          ),
          Expanded(
            child: Text(
              e.message,
              style: dshMono.copyWith(fontSize: 12, color: dshLogText),
            ),
          ),
        ],
      ),
    );
  }
}
