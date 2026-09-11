import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/web_service.dart';
import '../../theme.dart';

/// Stable layers keep the button opaque while its service state changes.
class ServiceToggleButton extends StatefulWidget {
  const ServiceToggleButton({
    super.key,
    required this.status,
    required this.locked,
    required this.onTap,
  });

  final WebStatus status;
  final bool locked;
  final VoidCallback? onTap;

  @override
  State<ServiceToggleButton> createState() => _ServiceToggleButtonState();
}

class _ServiceToggleButtonState extends State<ServiceToggleButton>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 240);
  static const _curve = Curves.easeInOutCubic;
  bool _hovered = false;
  bool _pressed = false;
  late final AnimationController _spin;

  bool get _starting => widget.status == WebStatus.starting;
  bool get _enabled => !_starting && !widget.locked && widget.onTap != null;
  bool get _active =>
      widget.status == WebStatus.running ||
      widget.status == WebStatus.externalRunning ||
      _starting;
  bool get _failed => widget.status == WebStatus.failed;
  bool get _external => widget.status == WebStatus.externalRunning;
  bool get _hover => _hovered && _enabled;

  static Color _lighten(Color c, double t) => Color.lerp(c, Colors.white, t)!;
  static Color _darken(Color c, double t) => Color.lerp(c, Colors.black, t)!;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (_active) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant ServiceToggleButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status != oldWidget.status || !_enabled) _pressed = false;
    if (_active && !_spin.isAnimating) _spin.repeat();
    // Keep the rotation alive until the outgoing ring has faded away.
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (widget.status) {
      WebStatus.starting => '正在启动服务',
      WebStatus.running => '停止服务',
      WebStatus.externalRunning => '打开界面',
      WebStatus.failed => '重试启动服务',
      WebStatus.stopped => '启动服务',
    };
    return Semantics(
      button: true,
      enabled: _enabled,
      label: label,
      child: MouseRegion(
        cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: () => setState(() => _pressed = false),
          onTap: _enabled ? widget.onTap : null,
          child: SizedBox(
            width: 104,
            height: 104,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: -6,
                  top: -6,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      duration: _duration,
                      curve: _curve,
                      opacity: _active ? 1 : 0,
                      onEnd: () {
                        if (!_active) _spin.stop();
                      },
                      child: SizedBox(
                        width: 116,
                        height: 116,
                        child: RepaintBoundary(
                          child: TweenAnimationBuilder<Color?>(
                            tween: ColorTween(
                              end: _external
                                  ? const Color(0xFF2FA37C)
                                  : dshAccent,
                            ),
                            duration: _duration,
                            curve: _curve,
                            builder: (_, color, _) => AnimatedBuilder(
                              animation: _spin,
                              builder: (_, _) => CustomPaint(
                                painter: _GlowRingPainter(
                                  progress: _spin.value,
                                  color: color!,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: _duration,
                  curve: _curve,
                  width: 104,
                  height: 104,
                  decoration: _decoration(),
                  child: TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: _iconColor),
                    duration: _duration,
                    curve: _curve,
                    builder: (_, color, _) => AnimatedSwitcher(
                      duration: _duration,
                      switchInCurve: _curve,
                      switchOutCurve: _curve,
                      child: Icon(
                        _external
                            ? Icons.open_in_new
                            : Icons.power_settings_new,
                        key: ValueKey(_external),
                        size: 42,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color get _iconColor =>
      _active ? Colors.white : (_failed ? dshDanger : dshInk3);

  BoxDecoration _decoration() {
    final Color fill;
    final Color border;
    if (_failed) {
      fill = _pressed
          ? _darken(dshDangerSoft, 0.06)
          : (_hover ? _lighten(dshDangerSoft, 0.10) : dshDangerSoft);
      border = _pressed
          ? _darken(dshDanger, 0.12)
          : (_hover ? _lighten(dshDanger, 0.08) : dshDanger);
    } else {
      fill = _pressed ? _darken(dshSurface, 0.035) : dshSurface;
      border = _pressed
          ? _darken(dshBorderStrong, 0.10)
          : (_hover ? _lighten(dshBorderStrong, 0.10) : dshBorderStrong);
    }
    // Never interpolate a solid color into a nullable gradient: both layers
    // otherwise fade independently, briefly exposing the background beneath.
    return BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _active ? _gradientColors() : [fill, fill],
      ),
      border: Border.all(
        color: _active ? Colors.transparent : border,
        width: 2.5,
      ),
      boxShadow: [
        BoxShadow(
          color: _active
              ? (_external ? const Color(0x552FA37C) : const Color(0x593B5BE0))
              : Colors.transparent,
          blurRadius: _hover ? 42 : 30,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  List<Color> _gradientColors() {
    final baseA = _external ? const Color(0xFF2FA37C) : dshAccent;
    final baseB = _external ? const Color(0xFF1F7A5C) : dshPrimary;
    if (_pressed) return [_darken(baseA, 0.12), _darken(baseB, 0.12)];
    if (_hover) return [_lighten(baseA, 0.06), _lighten(baseB, 0.04)];
    return [baseA, baseB];
  }
}

/// One continuous orbit for starting and running, including their transition.
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
