# Proposal: DSH 桌面启动器 (launcher-v1)

## Why

每天使用 DSH Web UI 需要先开两个控制台(`pnpm run dev:web` + `pnpm dsh web`)。Electron 桌面端可以做到双击启动,但它是独立产品形态(独立 profile、独立窗口、重构建周期),不合适常用入口。需要一个像 VSCode 一样双击即用的托盘启动器,把 dsh web 服务收进去:一键启动、托盘常驻、开机自启、一键升级。

## What Changes

- 新 Flutter Windows 桌面应用(模型: ct-tool launcher),窗口 720x460,左侧导航 + 概览/日志/设置三页,DSH 品牌蓝主题。
- **服务编排**: 启动/停止/重启 `dsh web`(生产模式默认),日志实时流式进日志页;浏览器由 dsh 在就绪后自行打开(openBrowser 默认),启动器解析 `dsh web:` 就绪行仅维护状态与「打开界面」入口(token URL),不重复打开;启动前探测端口,服务已在运行时直接提供"打开界面"。
- **开发模式开关**: 勾选时额外拉起 `pnpm run dev:web`(客户端插件热更新),日志以 `[DEV]` 前缀与 `[WEB]` 区分。
- **检查更新 + 一键升级**: `git fetch` 比较 HEAD 与远端;升级视图五步(预检 → `git pull --ff-only` → `pnpm install` → `pnpm run build`(含前端 vite)→ 重启服务),逐步状态 + 实时日志,失败可查可重试。纯 Dart 实现,不依赖任何 PowerShell 脚本。
- **桌面壳**: 系统托盘(打开界面/重启/停止/显示/退出)、单实例锁、开机自启、关闭窗口行为(最小化到托盘或退出)。
- 仓库 `tool/build_windows.ps1` 构建脚本(`flutter build windows --release`,无运行时嵌入)。
- 依赖关系: 引用现有 DSH checkout(默认探测用户主目录下的常见位置),需要机器上 node + pnpm;不修改 DSH 仓库任何文件。

## Capabilities

### New Capabilities

- `service-runtime`: dsh web 服务编排——启动/停止/重启、就绪检测与 token URL 提取、端口探测防重复、开发模式、日志流与错误识别。
- `upgrade`: 检查更新与一键升级——预检、git 拉取、依赖安装、构建、重启的流程状态与失败恢复。
- `desktop-shell`: 桌面壳行为——托盘菜单、单实例、开机自启、窗口与关闭行为、设置持久化、概览/日志/设置页交互。

### Modified Capabilities

- 无(新仓库,无既有 spec)。

## Impact

- 新仓库 `<本仓库>`(本地 git)。
- Flutter 依赖与 ct-tool launcher 相同梯队:`tray_manager`、`launch_at_startup`、`window_manager`、`shared_preferences`、`file_selector`、`url_launcher`、`win32_registry`。
- 外部依赖: 现有 dsh checkout、系统 node/pnpm、网络(git fetch、pnpm install)。
- 不触碰:`deepseek-harness` 仓库跟踪文件与 `~/.dsh` 共享数据(启动器只读展示数据目录)。桌面端(Electron)本地产物已退役删除,恢复方式见 `docs/desktop-retirement.md`。
