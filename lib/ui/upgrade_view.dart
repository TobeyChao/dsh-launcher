import 'package:flutter/material.dart' hide StepState;

import '../models/log_entry.dart';
import '../services/upgrade_service.dart';
import '../theme.dart';
import 'widgets/common.dart';

/// 升级视图:当前 HEAD → 目标 HEAD、五步步骤条、实时日志、重试/取消。
class UpgradeView extends StatefulWidget {
  const UpgradeView({super.key, required this.upgrade});

  final UpgradeService upgrade;

  @override
  State<UpgradeView> createState() => _UpgradeViewState();
}

class _UpgradeViewState extends State<UpgradeView> {
  final _logController = ScrollController();
  bool _pinBottom = true;

  @override
  void initState() {
    super.initState();
    widget.upgrade.addListener(_onChanged);
    _logController.addListener(_onLogScroll);
  }

  @override
  void dispose() {
    widget.upgrade.removeListener(_onChanged);
    _logController.dispose();
    super.dispose();
  }

  void _onChanged() {
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

  @override
  Widget build(BuildContext context) {
    final upg = widget.upgrade;
    return Scaffold(
      appBar: AppBar(
        title: const Text('升级 dsh', style: dshPageTitleStyle),
        backgroundColor: dshSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Row(
                children: [
                  _hashChip(upg.headShort.isEmpty ? '—' : upg.headShort, target: false),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('→', style: TextStyle(color: dshInk3)),
                  ),
                  _hashChip(_targetLabel(upg), target: true),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(26, 16, 26, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSteps(upg),
            const SizedBox(height: 14),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: dshLogBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: dshLogBorder),
                ),
                child: upg.logs.isEmpty
                    ? const Center(
                        child: Text(
                          '步骤输出将在这里实时显示',
                          style: TextStyle(fontSize: 12, color: Color(0xFF5E7368)),
                        ),
                      )
                    : ListView.builder(
                        controller: _logController,
                        itemCount: upg.logs.length,
                        itemBuilder: (_, i) => _logLine(upg.logs[i]),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            _buildFooter(upg),
          ],
        ),
      ),
    );
  }

  String _targetLabel(UpgradeService upg) {
    if (upg.targetHead != null && upg.targetHead!.isNotEmpty) return upg.targetHead!;
    if (upg.isRunning || upg.phase == UpgradePhase.done) return upg.currentHead ?? '—';
    return '未知';
  }

  Widget _hashChip(String text, {required bool target}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: target ? dshAccentSofter : dshSurface2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: target ? dshAccent : dshBorder),
      ),
      child: Text(
        text,
        style: dshMono.copyWith(
          fontSize: 12,
          color: target ? dshAccentHover : dshInk2,
        ),
      ),
    );
  }

  Widget _buildSteps(UpgradeService upg) {
    return Column(
      children: [
        for (final step in upg.steps) _stepRow(step, upg),
      ],
    );
  }

  Widget _stepRow(UpgradeStepState step, UpgradeService upg) {
    final (icon, color) = switch (step.state) {
      StepState.pending => (step.id.index + 1, dshInk3),
      StepState.running => (null, dshAccent),
      StepState.done => ('✓', dshAccent),
      StepState.failed => ('✕', dshDanger),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: step.state == StepState.running ? dshAccentSofter : dshSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: step.state == StepState.running ? dshAccent : dshBorder,
          width: step.state == StepState.running ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
            child: icon is int
                ? Text(
                    '$icon',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Text(
            step.label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Text(
            step.note ?? step.detail,
            style: dshMono.copyWith(
              fontSize: 12,
              color: step.state == StepState.failed ? dshDanger : dshInk3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(UpgradeService upg) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (upg.phase == UpgradePhase.idle && upg.updateAvailable) ...[
          DshButton.ghost('取消', onPressed: () => Navigator.of(context).pop()),
          const SizedBox(width: 10),
          DshButton.accent('开始升级', onPressed: upg.beginUpgrade),
        ] else if (upg.phase == UpgradePhase.running) ...[
          DshButton.ghost('取消', onPressed: upg.cancel),
          const SizedBox(width: 10),
          const DshButton.accent('升级中…', onPressed: null),
        ] else if (upg.phase == UpgradePhase.failed) ...[
          DshButton.ghost('关闭', onPressed: () => Navigator.of(context).pop()),
          const SizedBox(width: 10),
          DshButton.accent('重试', onPressed: upg.retry),
        ] else if (upg.phase == UpgradePhase.done) ...[
          DshButton.ghost('关闭', onPressed: () => Navigator.of(context).pop()),
          const SizedBox(width: 10),
          const DshButton.accent('升级完成', onPressed: null),
        ] else ...[
          DshButton.ghost('关闭', onPressed: () => Navigator.of(context).pop()),
        ],
      ],
    );
  }

  Widget _logLine(LogEntry e) {
    final color = switch (e.level) {
      LogLevel.info => dshLogText,
      LogLevel.warn => const Color(0xFFE5C078),
      LogLevel.error => const Color(0xFFE8837F),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${e.timestamp} ',
              style: dshMono.copyWith(fontSize: 11.5, color: const Color(0xFF6E8277)),
            ),
            TextSpan(
              text: e.message,
              style: dshMono.copyWith(fontSize: 11.5, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
