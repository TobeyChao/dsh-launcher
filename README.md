# DSH Launcher

DeepSeek Harness Web UI 桌面启动器(Windows / macOS):把 `pnpm dsh web`(可选 `dev:web` 热更新)收进一个托盘应用,双击即用,不用再开两个控制台。

特性:

- 一键启动/停止/重启 dsh web(生产模式),就绪后自动打开浏览器(token URL);
- 端口探测:服务已在外部运行时直接「打开界面」,被无关进程占用时明确报错;
- 开发模式开关:同时拉起 `pnpm run dev:web`(客户端插件热更新),日志以 DEV/WEB 区分;
- 系统托盘常驻、单实例、开机自启;
- 检查更新 + 一键升级(预检 → git pull → pnpm install → clean+build → 重启,纯 Dart 实现);
- 概览页显示 版本(HEAD)/运行时长/更新状态。

## 构建

### Windows

```powershell
.\tool\build_windows.ps1
```

产物:`build\windows\x64\runner\Release\`(`dsh_launcher.exe`,无运行时嵌入)。需要 Flutter SDK + Visual Studio 桌面开发工作负载。Flutter 自动探测(`FLUTTER` 环境变量优先,其次 PATH,再试 `%USERPROFILE%\development\flutter` 等常见位置)。未签名,仅本地使用,勿分发。

### macOS

需要 Flutter SDK（Dart 3.13+）、完整 Xcode，以及本机安装的 Git、Node.js 和 pnpm。

```bash
./tool/build_macos.sh
# Flutter 自动探测(FLUTTER 环境变量优先，其次 PATH，再试 ~/development/flutter 等常见位置)；
# 需要指定时，FLUTTER 可写 SDK 根目录或 bin/flutter：
FLUTTER=~/development/flutter ./tool/build_macos.sh
```

产物：`build/macos/Build/Products/Release/dsh_launcher.app`。可复制到 `/Applications` 后双击运行，再启用登录时自启，避免登录项指向临时构建目录。当前构建用于本机使用，未配置 Developer ID 签名和公证。

Finder 启动时会读取登录交互 shell 的 PATH（最多等待 5 秒），并补充 Apple Silicon / Intel Homebrew、pnpm 和 Volta 的常见目录。Node/pnpm 使用其他安装位置时，请在 shell 配置中加入 PATH。

macOS 构建关闭 App Sandbox，因为启动器需要执行 checkout 中的 Git/pnpm/Node、访问共享 `~/.dsh` 并管理子进程。关闭窗口可常驻菜单栏，右键菜单栏图标可退出；停止服务或取消升级会终结子进程树。

## 使用

Windows 双击 `dsh_launcher.exe`，macOS 双击 `dsh_launcher.app`。首次使用在「设置」页选择 dsh checkout 路径(含 `.git`,默认自动探测用户主目录下的常见位置,也可用环境变量 `DSH_HARNESS_PATH` 指定),端口默认 3080。

- 概览页大开关启动服务;就绪后浏览器自动打开;
- 「升级」:概览页更新卡 → 检查更新 → 升级视图确认;流程失败可停在步骤查看输出并重试;
- 数据目录 `~/.dsh` 与 dsh web/CLI 共享;启动器只读展示,并在启动服务前回收上次强杀进程遗留的孤儿写锁(`.lock`),避免 dsh 的上游写锁超时阻塞启动。

## 开发

```powershell
flutter pub get
flutter test           # 单元/组件测试
flutter analyze        # 零告警
flutter run            # 调试运行(debug 构建不写开机自启)
```

图标由同一份 PNG 母版导出，覆盖 Windows ICO、macOS AppIcon、侧栏和托盘。替换 `assets/branding/` 中的母版后，安装 Pillow 并运行 `python3 tool/gen_icons.py`（Windows 可运行 `tool\gen-icons.ps1`）。macOS 菜单栏使用独立的透明单色模板，自动适应深浅色模式。设计和生成提示词见 [图标设计记录](docs/icon-design.md)。

## 说明

- 升级流程与 deepseek-harness 无关:启动器管理的只是 checkout(git pull + pnpm install + pnpm run clean && pnpm run build),不触碰仓库跟踪文件之外的东西;
- 桌面端(Electron)已退役,记录见 [docs/desktop-retirement.md](docs/desktop-retirement.md);
- 界面设计稿:`docs/design/launcher-mockup.html`。
