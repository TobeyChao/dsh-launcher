# DSH Launcher

DeepSeek Harness Web UI 桌面启动器(Windows):把 `pnpm dsh web`(可选 `dev:web` 热更新)收进一个托盘应用,双击即用,不用再开两个控制台。

特性:

- 一键启动/停止/重启 dsh web(生产模式),就绪后自动打开浏览器(token URL);
- 端口探测:服务已在外部运行时直接「打开界面」,被无关进程占用时明确报错;
- 开发模式开关:同时拉起 `pnpm run dev:web`(客户端插件热更新),日志以 DEV/WEB 区分;
- 系统托盘常驻、单实例、开机自启;
- 检查更新 + 一键升级(预检 → git pull → pnpm install → clean+build → 重启,纯 Dart 实现);
- 概览页显示 版本(HEAD)/运行时长/更新状态。

## 构建

```powershell
.\tool\build_windows.ps1
```

产物:`build\windows\x64\runner\Release\`(`dsh_launcher.exe`,无运行时嵌入)。需要 Flutter SDK + Visual Studio 桌面开发工作负载。未签名,仅本地使用,勿分发。

## 使用

双击 `dsh_launcher.exe`。首次使用在「设置」页选择 dsh checkout 路径(含 `.git`,默认自动探测 `D:\projects\deepseek-harness`),端口默认 3080。

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

图标与品牌:改 `tool\gen-icons.ps1` 后重新生成。

## 说明

- 升级流程与 deepseek-harness 无关:启动器管理的只是 checkout(git pull + pnpm install + pnpm run clean && pnpm run build),不触碰仓库跟踪文件之外的东西;
- 桌面端(Electron)已退役,记录见 [docs/desktop-retirement.md](docs/desktop-retirement.md);
- 界面设计稿:`docs/design/launcher-mockup.html`。
