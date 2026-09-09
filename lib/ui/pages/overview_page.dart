import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/settings_store.dart';
import '../../services/upgrade_service.dart';
import '../../services/web_service.dart';
import '../../theme.dart';
import '../upgrade_view.dart';
import '../widgets/common.dart';

/// 概览页:启停状态 + 版本/运行时长/更新卡 + 仓库提示。
class OverviewPage extends StatefulWidget {
  const OverviewPage({
    super.key,
    required this.web,
    required this.settings,
    required this.upgrade,
    required this.onOpenLogs,
  });

  final WebService web;
  final SettingsStore settings;
  final UpgradeService upgrade;
  final VoidCallback onOpenLogs;

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  Timer? _uptimeTimer;
  Duration _uptime = Duration.zero;
  bool _checking = false;

  WebStatus get _status => widget.web.status;

  @override
  void initState() {
    super.initState();
    widget.web.addListener(_onChanged);
    widget.upgrade.addListener(_onChanged);
    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _tick();
  }

  @override
  void dispose() {
    widget.web.removeListener(_onChanged);
    widget.upgrade.removeListener(_onChanged);
    _uptimeTimer?.cancel();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _tick() {
    final started = widget.web.startedAt;
    if (started == null) {
      if (_uptime != Duration.zero && mounted) setState(() => _uptime = Duration.zero);
      return;
    }
    final now = DateTime.now().difference(started);
    if (mounted && now != _uptime) setState(() => _uptime = now);
  }

  Future<void> _copyAddress() async {
    await Clipboard.setData(ClipboardData(text: widget.web.openUrl));
    if (!mounted) return;
    showDshToast(context, '地址已复制');
  }

  Future<void> _openUi() async {
    await widget.web.openInBrowser();
  }

  Future<void> _checkUpdates() async {
    if (_checking) return;
    setState(() => _checking = true);
    final hasUpdate = await widget.upgrade.refreshAndHasUpdate();
    if (!mounted) return;
    setState(() => _checking = false);
    if (hasUpdate) {
      _openUpgradeView();
    } else {
      showDshToast(context, widget.upgrade.checkState == CheckState.unavailable
          ? '检查更新失败:离线或仓库异常'
          : '已是最新版本');
    }
  }

  void _openUpgradeView() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => UpgradeView(upgrade: widget.upgrade)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('概览', style: dshPageTitleStyle),
          const SizedBox(height: 12),
          Expanded(
            child: Column(
              children: [
                _buildHero(),
                const SizedBox(height: 20),
                _buildStats(),
              ],
            ),
          ),
          const SizedBox(height: 8),
          DshFooterHint(child: _buildRepoLine()),
        ],
      ),
    );
  }

  Widget _buildHero() {
    final s = dshStatusPresentation(_status, widget.web.failureReason);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [dshSurface, Color(0xFFF4F7FF)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dshBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x101B241F),
            blurRadius: 28,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _ToggleButton(
            status: _status,
            locked: widget.web.upgradeLocked,
            onTap: widget.web.upgradeLocked || _status == WebStatus.starting
                ? null
                : (_status == WebStatus.running
                    ? widget.web.stop
                    : (_status == WebStatus.externalRunning
                        ? _openUi
                        : widget.web.start)),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: s.dot,
                        boxShadow: [
                          BoxShadow(
                            color: s.dot.withValues(alpha: 0.25),
                            blurRadius: 0,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      s.title,
                      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  s.sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: dshInk2),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildAddr(s.hint),
                    const SizedBox(width: 10),
                    Text(s.hint, style: const TextStyle(fontSize: 12, color: dshInk3)),
                  ],
                ),
                const SizedBox(height: 12),
                _buildActions(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddr(String hint) {
    final running = _status == WebStatus.running ||
        _status == WebStatus.externalRunning;
    return Flexible(
      child: InkWell(
        onTap: running ? _copyAddress : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: running ? dshAccentSofter : dshSurface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: running ? dshAccent : dshBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.web.openUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: dshMono.copyWith(
                    fontSize: 13,
                    color: running ? dshAccentHover : dshInk2,
                  ),
                ),
              ),
              if (running) ...[
                const SizedBox(width: 6),
                Icon(Icons.copy_rounded, size: 13, color: dshAccent),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActions() {
    final running = _status == WebStatus.running ||
        _status == WebStatus.externalRunning;
    final failed = _status == WebStatus.failed;
    final locked = widget.web.upgradeLocked;
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        if (running) ...[
          DshButton.accent('打开界面', onPressed: locked ? null : _openUi),
          DshButton.ghost('重启服务', onPressed: locked ? null : widget.web.restart),
          DshButton.ghost('打开日志', onPressed: widget.onOpenLogs),
        ] else if (failed) ...[
          DshButton.accent('重试', onPressed: locked ? null : widget.web.start),
          DshButton.ghost('打开日志', onPressed: widget.onOpenLogs),
        ] else ...[
          DshButton.ghost('打开日志', onPressed: widget.onOpenLogs),
        ],
      ],
    );
  }

  Widget _buildStats() {
    final head = widget.upgrade.headShort;
    final version = head.isEmpty ? '—' : head;
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 122,
            child: DshStatCard(
              number: version,
              label: 'dsh 版本',
              sub: 'git HEAD',
              icon: Icons.rocket_launch_outlined,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 122,
            child: DshStatCard(
              number: _formatUptime(_uptime),
              label: '运行时长',
              sub: widget.web.startedAt == null ? '未运行' : '本次启动',
              icon: Icons.schedule,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 122,
            child: _buildUpdateCard(),
          ),
        ),
      ],
    );
  }

  Widget _buildUpdateCard() {
    final state = widget.upgrade.checkState;
    if (state == CheckState.unavailable) {
      return DshStatCard(
        number: '不可用',
        label: '更新',
        sub: '离线或仓库异常,检查更新',
        icon: Icons.cloud_off_outlined,
        onTap: _checking ? null : _checkUpdates,
      );
    }
    if (widget.upgrade.updateAvailable) {
      return DshStatCard(
        number: '可用 ${widget.upgrade.aheadCount} 个提交',
        label: '更新',
        sub: '查看更新 →',
        icon: Icons.system_update_alt,
        highlighted: true,
        onTap: _checking ? null : _openUpgradeView,
      );
    }
    return DshStatCard(
      number: _checking ? '检查中…' : '已是最新',
      label: '更新',
      sub: state == CheckState.none ? '启动时自动检查' : '点击重新检查',
      icon: Icons.system_update_alt,
      onTap: _checking ? null : _checkUpdates,
    );
  }

  String _formatUptime(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  Widget _buildRepoLine() {
    final repo = widget.settings.repoPath;
    return Row(
      children: [
        const Icon(Icons.folder_outlined, size: 14, color: dshInk3),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            repo.isEmpty ? '仓库未配置,请到设置中选择 dsh checkout' : repo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: dshMono.copyWith(fontSize: 12, color: dshInk3),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '数据目录 ~/.dsh(只读)',
          style: const TextStyle(fontSize: 12, color: dshInk3),
        ),
      ],
    );
  }
}

/// 概览页大圆形启停按钮:按状态区分造型;运行中带旋转辉光环;不缩放。
class _ToggleButton extends StatefulWidget {
  const _ToggleButton({
    required this.status,
    required this.locked,
    required this.onTap,
  });

  final WebStatus status;
  final bool locked;
  final VoidCallback? onTap;

  @override
  State<_ToggleButton> createState() => _ToggleButtonState();
}

class _ToggleButtonState extends State<_ToggleButton>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  bool _pressed = false;
  late final AnimationController _spin;

  bool get _starting => widget.status == WebStatus.starting;
  bool get _enabled => !_starting && !widget.locked;
  bool get _active =>
      widget.status == WebStatus.running ||
      widget.status == WebStatus.externalRunning ||
      _starting;
  bool get _failed => widget.status == WebStatus.failed;
  bool get _external => widget.status == WebStatus.externalRunning;
  bool get _showRing => _active && !_starting;

  static Color _lighten(Color c, double t) => Color.lerp(c, Colors.white, t)!;
  static Color _darken(Color c, double t) => Color.lerp(c, Colors.black, t)!;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _syncSpin();
  }

  @override
  void didUpdateWidget(covariant _ToggleButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSpin();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  void _syncSpin() {
    if (_showRing && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!_showRing && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: _enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: _enabled ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        child: SizedBox(
          width: 104,
          height: 104,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (_showRing)
                Positioned(
                  left: -6,
                  top: -6,
                  child: SizedBox(
                    width: 116,
                    height: 116,
                    child: AnimatedBuilder(
                      animation: _spin,
                      builder: (_, _) => CustomPaint(
                        painter: _GlowRingPainter(
                          progress: _spin.value,
                          color: _external ? const Color(0xFF2FA37C) : dshAccent,
                        ),
                      ),
                    ),
                  ),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: 104,
                height: 104,
                decoration: _decoration(),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_starting)
                      const SizedBox(
                        width: 104,
                        height: 104,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Color(0x8CE3EAFF),
                        ),
                      ),
                    Icon(_icon, size: 42, color: _iconColor),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData get _icon => _external ? Icons.open_in_new : Icons.power_settings_new;

  Color get _iconColor {
    if (_active) return Colors.white;
    if (_failed) return dshDanger;
    return dshInk3;
  }

  BoxDecoration _decoration() {
    if (_active) {
      final glowColor =
          _external ? const Color(0x552FA37C) : const Color(0x593B5BE0);
      return BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradientColors(),
        ),
        boxShadow: [
          BoxShadow(
            color: glowColor,
            blurRadius: _hovered ? 42 : 30,
            offset: const Offset(0, 10),
          ),
        ],
      );
    }
    // 非激活(已停止 / 启动失败):只做亮度变化(hover 变亮、press 变暗),不改变色相。
    final Color fill;
    final Color border;
    if (_failed) {
      fill = _hovered
          ? _lighten(dshDangerSoft, 0.10)
          : (_pressed ? _darken(dshDangerSoft, 0.06) : dshDangerSoft);
      border = _pressed
          ? _darken(dshDanger, 0.12)
          : (_hovered ? _lighten(dshDanger, 0.08) : dshDanger);
    } else {
      fill = _pressed ? _darken(dshSurface, 0.035) : dshSurface;
      border = _pressed
          ? _darken(dshBorderStrong, 0.10)
          : (_hovered ? _lighten(dshBorderStrong, 0.10) : dshBorderStrong);
    }
    return BoxDecoration(
      shape: BoxShape.circle,
      color: fill,
      border: Border.all(color: border, width: 2.5),
    );
  }

  List<Color> _gradientColors() {
    final baseA = _external ? const Color(0xFF2FA37C) : const Color(0xFF3B5BE0);
    final baseB = _external ? const Color(0xFF1F7A5C) : dshPrimary;
    if (_pressed) return [_darken(baseA, 0.12), _darken(baseB, 0.12)];
    if (_hovered) return [_lighten(baseA, 0.06), _lighten(baseB, 0.04)];
    return [baseA, baseB];
  }
}

/// 围绕按钮旋转的辉光短弧(运行 / 外部运行态)。
class _GlowRingPainter extends CustomPainter {
  _GlowRingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(progress * 2 * math.pi);
    canvas.translate(-center.dx, -center.dy);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: 0.9),
          color.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.12, 0.25],
      ).createShader(rect);
    canvas.drawCircle(center, radius, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlowRingPainter old) =>
      old.progress != progress || old.color != color;
}
