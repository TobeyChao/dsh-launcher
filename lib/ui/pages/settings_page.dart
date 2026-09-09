import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/auto_launch.dart';
import '../../services/settings_store.dart';
import '../../services/web_service.dart';
import '../../theme.dart';
import '../widgets/common.dart';

/// 设置页:DSH 仓库 / 端口 / 开发模式 / 开机自启 / 托盘常驻。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings, required this.web});

  final SettingsStore settings;
  final WebService web;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _autostartBusy = false;
  bool _autostartSwitch = false;
  late final TextEditingController _repoController;
  late final TextEditingController _portController;

  @override
  void initState() {
    super.initState();
    _repoController = TextEditingController(text: widget.settings.repoPath);
    _portController = TextEditingController(text: '${widget.settings.port}');
    widget.web.addListener(_onChanged);
    _syncAutostart();
  }

  @override
  void dispose() {
    widget.web.removeListener(_onChanged);
    _repoController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// 服务运行中(含正在启动):仓库/端口不可修改,需先停止。
  bool get _serviceActive =>
      widget.web.status == WebStatus.running ||
      widget.web.status == WebStatus.starting;

  Future<void> _syncAutostart() async {
    try {
      final enabled = await AutoLaunch.instance.isEnabled;
      if (mounted) setState(() => _autostartSwitch = enabled);
    } catch (_) {
      // 平台插件不可用时保持默认关闭,不影响其他设置。
    }
  }

  Future<void> _pickRepo() async {
    final path = await getDirectoryPath(
      confirmButtonText: '选择',
      initialDirectory: widget.settings.repoPath.isNotEmpty
          ? widget.settings.repoPath
          : null,
    );
    if (path == null || path.isEmpty) return;
    _repoController.text = path;
    await widget.settings.setRepoPath(path);
  }

  Future<void> _toggleAutostart(bool value) async {
    if (_autostartBusy) return;
    setState(() => _autostartBusy = true);
    if (kDebugMode) {
      if (!mounted) return;
      setState(() => _autostartBusy = false);
      showDshToast(context, '调试模式不启用开机自启,正式构建下生效');
      return;
    }
    await AutoLaunch.instance.updateStatus(value);
    await widget.settings.setAutoStart(value);
    if (mounted) {
      setState(() {
        _autostartBusy = false;
        _autostartSwitch = value;
      });
      showDshToast(context, value ? '已开启开机自启' : '已关闭开机自启');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('设置', style: dshPageTitleStyle),
          const SizedBox(height: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSettingsCard(),
                const Spacer(),
              ],
            ),
          ),
          const SizedBox(height: 8),
          DshFooterHint(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '仓库与端口需在服务停止时修改;其他设置即时生效',
                  style: TextStyle(fontSize: 12, color: dshInk3),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: dshInk3),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.settings.trayResident
                            ? '关闭窗口不会退出应用:点击系统托盘的 DS 图标可快速启动 / 停止 / 退出'
                            : '开启「托盘常驻」后,关闭窗口不会退出应用,可从系统托盘图标恢复',
                        style: const TextStyle(fontSize: 12, color: dshInk3),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Container(
      decoration: BoxDecoration(
        color: dshSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: dshBorder),
      ),
      child: Column(
        children: [
          DshSettingRow(
            label: 'dsh 仓库',
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _repoController,
                    style: dshMono.copyWith(fontSize: 12),
                    decoration: dshInputDecoration(),
                    enabled: !_serviceActive,
                    onChanged: (v) {
                      widget.settings.setRepoPath(v.trim());
                    },
                  ),
                ),
                const SizedBox(width: 8),
                DshButton.ghost(
                  '浏览…',
                  onPressed: _serviceActive ? null : _pickRepo,
                ),
              ],
            ),
          ),
          if (!widget.settings.repoValid)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                '仓库路径无效:需选择包含 .git 的 dsh checkout',
                style: TextStyle(fontSize: 12, color: dshDanger),
              ),
            )
          else if (_serviceActive)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                '服务运行中:请先停止服务再修改仓库 / 端口',
                style: TextStyle(fontSize: 12, color: dshInk3),
              ),
            ),
          DshSettingRow(
            label: '端口',
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _portController,
                    style: dshMono.copyWith(fontSize: 12),
                    decoration: dshInputDecoration(),
                    enabled: !_serviceActive,
                    onChanged: (v) {
                      final p = int.tryParse(v.trim());
                      if (p != null && p > 0 && p < 65536) {
                        widget.settings.setPort(p);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '冲突时提示;dsh 已在运行则直接打开',
                    style: TextStyle(fontSize: 12, color: dshInk3),
                  ),
                ),
              ],
            ),
          ),
          DshSettingRow(
            label: '开发模式',
            child: Row(
              children: [
                Switch(
                  value: widget.settings.devMode,
                  onChanged: widget.settings.setDevMode,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '拉起 dev:web 热更新客户端插件(平时建议关闭)',
                    style: TextStyle(fontSize: 12, color: dshInk3),
                  ),
                ),
              ],
            ),
          ),
          DshSettingRow(
            label: '开机自启',
            child: Row(
              children: [
                Switch(
                  value: _autostartSwitch,
                  onChanged: _autostartBusy ? null : _toggleAutostart,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '登录系统后自动启动并运行',
                    style: TextStyle(fontSize: 12, color: dshInk3),
                  ),
                ),
              ],
            ),
          ),
          DshSettingRow(
            label: '托盘常驻',
            child: Row(
              children: [
                Switch(
                  value: widget.settings.trayResident,
                  onChanged: widget.settings.setTrayResident,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '关闭窗口时最小化到托盘,服务不中断',
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
}
