# Design: DSH 桌面启动器 (launcher-v1)

## Context

动机与范围见 proposal.md。本设计只回答 HOW。约束前提:

- 目标机器为一台 Windows 开发机:已有 Node 22 + pnpm 11 + Flutter SDK,DSH checkout 在本地(如 `<dsh-checkout>`),日常以源码方式(`pnpm dsh web`)跑 Web UI。
- 参考实现 `<参考 launcher 目录>` 已验证全部桌面依赖(tray_manager/launch_at_startup/window_manager/shared_preferences/file_selector/url_launcher/win32_registry)在 Windows 上可用,且已有"先 mockup 后实现"的协作流程与主题令牌。

## Goals / Non-Goals

**Goals:**

- 启动器只做一件事:把"两个控制台"(dsh web + 可选 dev:web)收进托盘,行为与手动启动**完全一致**(同一 checkout、同一 `~/.dsh`、同一 profile)。
- 升级零手工:检查更新 → 一键五步 → 服务自动回来。
- 复用 ct-tool 已验证的进程管理/设置/托盘骨架,降低失败面。

**Non-Goals:**

- 不捆绑任何运行时(不嵌 Node/pnpm/seed;desktop 的重构建路径已被排除)。
- 不做 npm 全局安装通道(`@deepseek-ai/dsh` 已发布但属于另一分发链路,须先验证 npm 端到端,另行探索)。
- 不做 macOS/Linux 支持(v1 仅 Windows;macOS 壳保留 ct-tool 的条件路径但不验证)。
- 不修改 deepseek-harness 仓库、不触碰 `~/.dsh` 内容(只读展示数据目录)。
- 端口"被占自动 +1"不做:自动换端口会改变 dsh web 的 canonical 语义,改为"外部已运行→直接打开 / 无关占用→报错"。

## Decisions

### D1. 技术栈: Flutter,照搬 ct-tool 依赖梯队

- 备选: Tauri(新工具链,Rust 主进程,骨架零复用)、Electron(正是要换掉的形态)。
- 采用: Flutter + 与 ct-tool 完全相同的依赖集,直接复用其 main/window/托盘/单实例/设置/主题骨架与构建脚本(`flutter build windows --release`)。

### D2. 依赖通道: 包住现有 checkout(方案 A)

见探索结论: A 与手动用法 100% 同构,升级=git pull+pnpm install+build; B(npm 全局安装)通道未验证; C(嵌入运行时)已被 desktop 重建周期否决。
启动器启动命令(在 checkout 根执行):

```
pnpm dsh web --no-open --port <设置端口>
pnpm run dev:web            # 仅开发模式;根脚本已带 --poll
```

`pnpm run build`(升级第 4 步)已核实包含 `build:web`(vite 前端产物),不必分两条。

### D3. 浏览器打开归 dsh,启动器永不重复打开

最初设计为"永远 `--no-open` + 启动器解析 token URL 后打开"。实测发现 dsh 的就绪行在 Loader settle 后打印(**`packages/bundle/web-app/src/index.ts`**,URL 行与浏览器交接都是就绪信号),早于或晚于 HTTP 健康响应并不确定——负载高时就绪行会晚数秒。自建"解析行→开浏览器"必然引入竞态与"先开 baseUrl 再补 token"的双开。
改为:生产路径**不带** `--no-open`(openBrowser 默认 true),dsh 在 settle 后自行用 token URL 打开浏览器(打开时机由其自身保证,零竞态)。启动器只做:
- 解析 `dsh web:` 行 → 状态 running + `openUrl` 记录 token URL("打开界面"按钮/托盘使用;token 行到达前用 baseUrl);
- 健康探测仅兜底**状态**判定(不开浏览器);
- 测试置 `suppressDshBrowser`(追加 `--no-open`)避免 e2e 弹出真浏览器;生产路径的打开行为由 dsh 自身测试保证,启动器不重复实现。

### D4. 进程管理: Process.start + Windows 进程树终结

Dart 的 `Process.kill` 只杀直接子进程;`pnpm`→`node` 是树。停止/重启/升级前/退出时统一走 `taskkill /F /T /PID <pid>`(记录各子进程 PID)。子进程 stdout/stderr 统一 UTF-8 解码 → 按行 → ANSI 剥离 → 日志模型(复用 ct-tool `PanelService` 的既有模式,扩展来源标记 `[WEB]`/`[DEV]`)。

环境注入: `NO_COLOR=1`、`TERM=dumb`(日志面板不解析控制字符)、`GIT_TERMINAL_PROMPT=0`(git 拉取失败快速返回,不在启动器里挂起等凭据输入——凭据由系统 credential manager 提供)。

### D5. 状态机: stopped → starting → running / failed / external-running

```
            start                 就绪行(或端口探测 200)
  stopped ──────► starting ───────────────────► running
     ▲              │                                 │
     └────── 停止/退出(含超时强杀) ── 失败 ◄──── 崩溃   │
                                                   │
  端口探测命中: external-running(不 spawn,启动=打开界面)
```

- 启动前先 TCP 探测端口: 有监听 → 尝试 HTTP GET `/`;200 → `external-running`;否则报"端口被占用"。
- 就绪判定: 解析到 `dsh web:` 行 → running;子进程意外退出 → failed(带退出码)。
- 重启 = 一次原子操作(先停后启);升级期间所有启动/停止入口禁用。

### D6. 升级引擎: 纯 Dart 五步 runner,零 ps1 依赖

```
UpgradeService(ChangeNotifier)
  checkForUpdates():  git fetch origin(fetch 完读 ahead/behind)
  升级: 步骤数组 [预检, 拉取, 安装, 构建, 重启]
  每步: label + spawn 命令 + 完成判据(退出码)
  失败: 停在当前步 → 重试从当前步重跑(已成功步不重跑)
  取消: 杀当前步进程树 → 置失败态
  禁止并发: 升级中 → 服务类按钮禁用(规格已定义)
```

- 预检: `git status --porcelain --untracked-files=no` 输出为空 + `git rev-parse --abbrev-ref HEAD` 取分支;先停服务(预检通过后)。
- 拉取: `git pull --ff-only`;安装: `pnpm install`;构建: `pnpm run clean && pnpm run build`(clean 先清 lib/tsbuildinfo/前端 dist 及已删除包的残留——dev:web 的 `--no-emptyOutDir` 会持续 serve 旧资产,不清理会在升级后出现"静默提供旧产物";桌面端已退役,无需保护任何缓存);重启: 恢复之前的运行状态(升级前在跑 → 重启并开界面;否则保持停止)。
- 启动时静默 `git fetch`(后台,fetch 失败不打扰,更新卡置不可用);版本卡显示 HEAD 短哈希。
- 目标 HEAD 比较基于 `origin/<分支>`。

### D7. 界面结构(对齐 ct-tool,DSH 品牌蓝)

- 窗口 720x460(min 同尺寸),左导航 176px + 右内容区;页签 概览/日志/设置。
- 主题令牌沿用 ct-tool 中性色与 8px 圆角,主色换 DSH 品牌蓝(与 Web UI 呼应);日志页沿用深色面板。
- 升级视图: 主窗口内 route(不是新窗口),内容 = 头部(旧→新 HEAD)+ 五步步骤条 + 每步实时日志区 + 重试/取消。
- 高保真稿先出文档(见 `design/launcher-mockup.html`),评审通过后再写 Flutter。

### D8. 设置与持久化

shared_preferences 键: `repo_path` / `port` / `dev_mode` / `auto_start` / `tray_resident`。
- 默认: repo 路径探索用户主目录下的常见位置(存在才生效;也可用 `DSH_HARNESS_PATH` 指定),port 3080,dev_mode 关,auto_start 关,tray_resident 开。
- 设置修改即时生效(下次启动服务时使用);repo 路径校验 `.git` 存在,无效时概览页提示且禁启动。

## Module Map

```
lib/
  main.dart                 窗口/单实例/全应用装配
  app.dart                  MaterialApp + 路由(主屏 / 升级视图)
  theme.dart                DSH 品牌蓝令牌(ct-tool 令牌改造)
  models/log_entry.dart     日志行(级别/来源/时间戳)
  services/
    settings_store.dart     D1/D8
    web_service.dart        D2/D3/D4/D5 服务状态机 + 子进程 + token URL
    upgrade_service.dart    D6 五步升级引擎 + fetch 检查
    tray_service.dart       托盘菜单联动(ct-tool 同款改造)
    single_instance_lock.dart  ct-tool 同款
    auto_launch.dart        ct-tool 同款
  ui/
    launcher_screen.dart    左导航壳(ct-tool 同款)
    pages/overview_page.dart  状态卡/URL/版本/运行时长/更新卡
    pages/logs_page.dart      双来源日志
    pages/settings_page.dart  仓库/端口/开发模式/自启/托盘常驻
    upgrade_view.dart         五步升级视图
  assets/icons/             托盘图标 + 应用图标(DSH 主题)
tool/build_windows.ps1      flutter build windows --release(无 runtime 嵌入)
docs/design/launcher-mockup.html  高保真稿(apply 时从 change 复制)
```

## Risks / Trade-offs

- [就绪行解析失败 → 打开界面兜底直开根路径撞认证围栏] → 兜底前先在日志缓冲全文重搜;再失败则打开根路径并提示 "认证失败请在浏览器手动打开 dsh web 打印的 URL";token URL 持久化在会话内。
- [taskkill 误伤] → 只对**自己 spawn 的 PID** 执行 `/T`(记录进程树根 PID);端口探测从不杀进程;升级前只停自己管理的服务。
- [启动时 git fetch 挂起等凭据] → `GIT_TERMINAL_PROMPT=0`,fetch 包 30s 超时,失败静默置更新卡不可用。
- [pnpm install/build 输出量大] → 升级日志区按行滚动,保留最近 1000 行;步骤内支持取消(杀树)。
- [pull 后 package 版本与 lockfile 漂移] → `pnpm install` 严格在 pull 之后执行,失败即停步,不继续构建。
- [用户机器中文 GBK 控制台导致子进程输出乱码] → pnpm/node/git 均输出 UTF-8;启动器以 UTF-8 解码,并注入 NO_COLOR/TERM=dumb;若有乱码样本再按行修复(不预先做转码层)。
- [升级中 git 冲突(本地已提交但被上游改)] → 预检只挡未提交改动;pull --ff-only 冲突时停步展示 git 输出,用户手工处理后从拉取步重试。

## Migration Plan

全新仓库,无迁移。首个可用版本 = `flutter build windows --release` 得到 `build\windows\x64\runner\Release\DSHLauncher.exe`,双击使用;回滚 = 换回两个控制台(启动器不改变 checkout 与 `~/.dsh` 任何状态)。

## Open Questions

- 无阻塞项。以下留待实现后回访: npm 全局安装通道(方案 B)作为 v2;macOS 支持;托盘图标与品牌素材的最终样式(mockup 阶段定稿)。
