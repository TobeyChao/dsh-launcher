import 'package:flutter/material.dart';

import '../services/settings_store.dart';
import '../services/upgrade_service.dart';
import '../services/web_service.dart';
import '../theme.dart';
import 'pages/logs_page.dart';
import 'pages/overview_page.dart';
import 'pages/settings_page.dart';
import 'widgets/common.dart';

enum _Tab { overview, logs, settings }

/// 启动器主界面壳:左侧导航 + 右侧内容区,负责页签切换与侧栏状态。
class LauncherScreen extends StatefulWidget {
  const LauncherScreen({
    super.key,
    required this.settings,
    required this.web,
    required this.upgrade,
  });

  final SettingsStore settings;
  final WebService web;
  final UpgradeService upgrade;

  @override
  State<LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends State<LauncherScreen> {
  _Tab _tab = _Tab.overview;

  @override
  void initState() {
    super.initState();
    widget.web.addListener(_onChanged);
    widget.settings.addListener(_onChanged);
    widget.upgrade.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.web.removeListener(_onChanged);
    widget.settings.removeListener(_onChanged);
    widget.upgrade.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _buildSideNav(),
          const VerticalDivider(width: 1, thickness: 1, color: dshBorder),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: KeyedSubtree(
                key: ValueKey(_tab),
                child: _buildPage(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideNav() {
    final s = dshStatusPresentation(widget.web.status, widget.web.failureReason);
    return Container(
      width: 176,
      decoration: const BoxDecoration(
        color: dshSurface,
        border: Border(right: BorderSide(color: dshBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 44),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                DshBrandMark(),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'DSH Launcher',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          DshNavItem(
            icon: Icons.power_settings_new,
            label: '概览',
            selected: _tab == _Tab.overview,
            onTap: () => setState(() => _tab = _Tab.overview),
          ),
          DshNavItem(
            icon: Icons.terminal,
            label: '日志',
            selected: _tab == _Tab.logs,
            onTap: () => setState(() => _tab = _Tab.logs),
          ),
          DshNavItem(
            icon: Icons.tune,
            label: '设置',
            selected: _tab == _Tab.settings,
            onTap: () => setState(() => _tab = _Tab.settings),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: s.dot,
                    boxShadow: [
                      BoxShadow(
                        color: s.dot.withValues(alpha: 0.3),
                        blurRadius: 0,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: dshInk2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${widget.settings.port}',
                  style: dshMono.copyWith(fontSize: 11, color: dshInk3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage() {
    return switch (_tab) {
      _Tab.overview => OverviewPage(
          web: widget.web,
          settings: widget.settings,
          upgrade: widget.upgrade,
          onOpenLogs: () => setState(() => _tab = _Tab.logs),
        ),
      _Tab.logs => LogsPage(web: widget.web),
      _Tab.settings => SettingsPage(settings: widget.settings, web: widget.web),
    };
  }
}
