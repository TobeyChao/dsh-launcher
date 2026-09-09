import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/web_service.dart';
import '../../theme.dart';

/// 页面共享的排版常量。
const TextStyle dshMono = TextStyle(
  fontFamily: 'Cascadia Mono',
  fontFamilyFallback: ['Consolas', 'Menlo', 'SF Mono'],
);

const TextStyle dshPageTitleStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);

/// 服务状态的展示信息(唯一 switch 来源,侧栏与概览页共用)。
({Color dot, String title, String sub, String hint}) dshStatusPresentation(
  WebStatus status,
  String? failureReason,
) {
  return switch (status) {
    WebStatus.stopped => (
        dot: dshInk3,
        title: '已停止',
        sub: '点击开关启动 Web 服务,就绪后自动打开',
        hint: '未运行',
      ),
    WebStatus.starting => (
        dot: dshGold,
        title: '正在启动',
        sub: '正在拉起 dsh web,稍候…',
        hint: '连接中',
      ),
    WebStatus.running => (
        dot: dshAccent,
        title: '运行中',
        sub: 'Web 服务运行中 · 点击开关可停止',
        hint: '点击地址可复制',
      ),
    WebStatus.failed => (
        dot: dshDanger,
        title: '启动失败',
        sub: failureReason ?? '请查看下方日志后重试',
        hint: '服务未启动',
      ),
    WebStatus.externalRunning => (
        dot: dshGold,
        title: '已在运行',
        sub: '端口上的服务不由本启动器管理 · 可直接打开界面',
        hint: '外部服务',
      ),
  };
}

/// 全局轻提示(蓝色浮层)。
void showDshToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: dshPrimary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
}

/// 用系统默认浏览器打开地址(概览页与托盘共用)。
Future<void> openInBrowser(String url) async {
  if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
    throw StateError('无法打开 $url');
  }
}

/// 输入框统一样式。
InputDecoration dshInputDecoration() {
  return InputDecoration(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    filled: true,
    fillColor: dshSurface,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: dshBorderStrong),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: dshAccent, width: 1.5),
    ),
  );
}

/// 品牌标志(深蓝圆角方块 + DS 字标)。
class DshBrandMark extends StatelessWidget {
  const DshBrandMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: dshPrimary,
        borderRadius: BorderRadius.circular(5),
      ),
      alignment: Alignment.center,
      child: const Text(
        'DS',
        style: TextStyle(
          fontFamily: 'Cascadia Mono',
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 左侧导航项。
class DshNavItem extends StatelessWidget {
  const DshNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? dshAccentSofter : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(icon, size: 16, color: selected ? dshPrimary : dshInk3),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? dshPrimary : dshInk2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 页面底部提示条:细分割线 + 提示内容。
class DshFooterHint extends StatelessWidget {
  const DshFooterHint({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, thickness: 1, color: dshBorder),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

/// 通用按钮:accent 主按钮 / ghost 次级按钮。
enum _DshButtonKind { accent, ghost }

class DshButton extends StatelessWidget {
  const DshButton.accent(this.label, {super.key, required this.onPressed})
      : _kind = _DshButtonKind.accent;
  const DshButton.ghost(this.label, {super.key, required this.onPressed})
      : _kind = _DshButtonKind.ghost;

  final String label;
  final VoidCallback? onPressed;
  final _DshButtonKind _kind;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      visualDensity: VisualDensity.compact,
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      side: _kind == _DshButtonKind.accent
          ? const WidgetStatePropertyAll(BorderSide(color: dshAccent))
          : const WidgetStatePropertyAll(BorderSide(color: dshBorderStrong)),
      backgroundColor: switch (_kind) {
        _DshButtonKind.accent => const WidgetStatePropertyAll(dshAccent),
        _DshButtonKind.ghost => const WidgetStatePropertyAll(Colors.transparent),
      },
      foregroundColor: switch (_kind) {
        _DshButtonKind.accent => const WidgetStatePropertyAll(Colors.white),
        _DshButtonKind.ghost => const WidgetStatePropertyAll(dshInk2),
      },
      overlayColor: switch (_kind) {
        _DshButtonKind.accent => const WidgetStatePropertyAll(dshAccentHover),
        _DshButtonKind.ghost => const WidgetStatePropertyAll(dshSurface2),
      },
    );
    return TextButton(style: style, onPressed: onPressed, child: Text(label));
  }
}

/// 设置页行:标签 + 控件。
class DshSettingRow extends StatelessWidget {
  const DshSettingRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: dshBorder)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: const TextStyle(fontSize: 13, color: dshInk2)),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 概览页统计卡:图标 + 标签 + 大数字 + 副行。
class DshStatCard extends StatelessWidget {
  const DshStatCard({
    super.key,
    required this.number,
    required this.label,
    required this.sub,
    required this.icon,
    this.highlighted = false,
    this.onTap,
  });

  final String number;
  final String label;
  final String sub;
  final IconData icon;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: highlighted ? dshAccentSofter : dshSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: highlighted ? dshAccent : dshBorder),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 15, color: highlighted ? dshAccent : dshInk3),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: dshInk2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    number,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 22,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                      color: highlighted ? dshAccent : dshPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: dshInk3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
