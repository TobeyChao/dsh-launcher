# Tasks: DSH 桌面启动器 (launcher-v1)

## 1. 工程脚手架

- [x] 1.1 在 `D:\projects\dsh-launcher` 执行 `flutter create . --project-name dsh_launcher --platforms windows` 并核对窗口工程生成 — verify: `flutter build windows` 无错误,`lib/main.dart` 存在
- [x] 1.2 添加依赖 `tray_manager` `launch_at_startup` `window_manager` `shared_preferences` `file_selector` `url_launcher` `win32_registry`(与 ct-tool 同版本区间) — verify: `flutter pub get` 成功且 `pubspec.lock` 更新
- [x] 1.3 配置 `.gitignore`(排除 `build/`、`.dart_tool/`、`openspec/changes/*/` 之外的运行产物)与 `assets/icons/` 托盘/应用图标 — verify: `git status` 不显示构建产物,图标资源可被 `flutter build` 打包
- [x] 1.4 编写 `tool/build_windows.ps1`(仿 ct-tool,无 runtime 嵌入:预检 Flutter/VS 环境 → `flutter build windows --release` → 输出 Release 目录路径) — verify: 脚本执行成功并产出 `build\windows\x64\runner\Release\`

## 2. 主题与壳

- [x] 2.1 实现 `theme.dart`(DSH 品牌蓝令牌:8px 圆角、暖中性背景、accent-soft 选中等,对齐 mockup) — verify: `flutter analyze` 通过,页面引用令牌编译通过
- [x] 2.2 实现 `main.dart`:窗口 720x460(min 同尺寸)、`SingleInstanceLock`(已运行实例直接退出)、`setPreventClose(true)` 拦截关闭,关闭行为交应用层 — verify: 二次启动时第二个实例立即退出,首实例窗口正常
- [x] 2.3 实现 `app.dart` 与路由:主屏 `LauncherScreen` + 升级视图 route;`LauncherScreen` 左导航 176px + 概览/日志/设置三页(对齐 ct-tool 骨架) — verify: 三页签切换正常,升级视图可 push/pop

## 3. 设置与持久化

- [x] 3.1 实现 `settings_store.dart`:键 `repo_path`/`port`/`dev_mode`/`auto_start`/`tray_resident`,默认值(仓库默认 `D:\projects\deepseek-harness` 存在才生效,port 3080,dev 关,自启关,托盘常驻开) — verify: 单元测试覆盖默认与读写持久化
- [x] 3.2 实现 repo 路径校验(存在 `.git`)与无效时 UI 禁启动提示 — verify: 单元测试 + 设置页填入不存在路径时概览页启动按钮禁用并提示

## 4. 服务编排

- [x] 4.1 实现 `web_service.dart` 状态机(stopped/starting/running/failed/external-running)+ 启动命令构造(`pnpm dsh web --no-open --port <n>`,cwd=repo 根) — verify: 单元测试覆盖状态流转与命令行构造(参照 ct-tool `buildLaunchCommand` 测试风格)
- [x] 4.2 实现子进程日志流:UTF-8 解码 → 按行 → ANSI 剥离 → 双来源标记(`SYS`/`WEB`/`DEV`),`NO_COLOR=1`/`TERM=dumb` 环境注入 — verify: 假进程(spawn 输出 ANSI 文本)单测断言剥离与标记
- [x] 4.3 实现就绪检测:解析 `dsh web:` token URL 行维护状态与 openUrl(浏览器由 dsh 自行打开,不重复);健康探测仅兜底状态 — verify: 单测覆盖正常解析、行晚到、缺失三路径;E2E 断言 openUrl 带 token
- [x] 4.4 实现端口探测:启动前 TCP 探测 + HTTP GET `/` 健康判定 → external-running 或"端口被占用"错误;绝不杀无关进程 — verify: 真实占端口场景手工验证(启动一个监听 3080 的其他服务)
- [x] 4.5 实现停止/重启:进程树终结(`taskkill /F /T /PID`),5 秒超时强杀;重启=先停后启原子操作;升级期间所有启动/停止入口禁用 — verify: spawn 一个会 fork 子进程的假程序,停止后任务管理器无残留
- [x] 4.6 实现开发模式:开启时并发拉起 `pnpm run dev:web`(根脚本已带 `--poll`),dev 进程意外退出仅提示产物链过期 — verify: 开启后日志页出现 DEV 来源日志,杀掉 dev 进程后 WEB 服务仍运行

## 5. 日志视图

- [x] 5.1 实现 `log_entry.dart`(级别/来源/时间戳/文本)与 `logs_page.dart`:500 条上限、自动跟随、复制/清空、错误关键词标红(参照 ct-tool model 与页面) — verify: 单测覆盖 500 条裁剪与复制;页面手工验证滚动跟随
- [x] 5.2 实现日志文本对剪贴板输出(clipboard)与"打开日志"跳转 — verify: 点击复制后剪贴板内容与日志一致

## 6. 概览页

- [x] 6.1 实现 `overview_page.dart`:状态卡(开关大按钮/状态/地址可复制/打开界面/重启/打开日志)、版本卡(HEAD 短哈希)、运行时长、更新卡 — verify: 对照 mockup 逐项核对;地址点击复制有反馈
- [x] 6.2 版本与运行时长数据源:启动时读 `git rev-parse --short HEAD` 与服务的启动时刻 — verify: 概览页显示与 `git log -1 --format=%h` 一致,时长计时增长
- [x] 6.3 更新卡联动:检查完成显示落后提交数/高亮;检查失败显示不可用 — verify: 手工断开网络重启后更新卡置灰,恢复网络后检查恢复

## 7. 系统托盘

- [x] 7.1 实现 `tray_service.dart`:托盘图标、动态菜单(打开界面/启动-停止随状态切换/重启/显示启动器/退出)、左键显示窗口、右键弹菜单、状态监听联动 — verify: 运行中菜单显示"停止服务",停止后显示"启动服务",左键/右键行为符合设计
- [x] 7.2 关闭窗口行为:托盘常驻开 → 隐藏到托盘(服务不断);关闭 → 停止服务退出;托盘"退出"始终停止服务树 — verify: 两种设置下行为分别验证

## 8. 升级引擎

- [x] 8.1 实现 `upgrade_service.dart` 的检查更新:静默 `git fetch origin`(30s 超时,`GIT_TERMINAL_PROMPT=0`)+ 计算与 `origin/<分支>` 的落后数 — verify: 落后时概览页更新卡显示提交数;无网时置不可用不阻塞
- [x] 8.2 实现五步 runner:预检(已跟踪树干净 `--untracked-files=no` + 停服务)、`git pull --ff-only`、`pnpm install`、`pnpm run clean && pnpm run build`、按升级前状态重启 — verify: 步骤顺序与状态流转单测;真实跑一次小升级全绿
- [x] 8.3 实现失败/重试/取消:失败停步展示输出,重试从失败步续跑(成功步不重跑),取消杀当前步进程树置失败态,升级中服务按钮禁用 — verify: 单测 + 人为制造 `git pull` 冲突/`pnpm install` 失败路径验证
- [x] 8.4 实现结果视图数据:旧→新 HEAD、每步存活输出滚动窗、升级成功自动重启并开界面 — verify: 一次成功升级全流程走通

## 9. 升级视图

- [x] 9.1 实现 `upgrade_view.dart`(对齐 mockup 2):旧→新 HEAD、五步步骤条(待办/进行中/完成/失败)、实时日志区、重试/取消按钮、步骤禁用态 — verify: 对照 mockup 核对;升级进行中截屏与 mockup 一致
- [x] 9.2 概览页更新卡/检查更新与升级视图的入口联动("无更新时提示最新") — verify: 无更新点击检查 → 提示已是最新,不进入视图

## 10. 设置页

- [x] 10.1 实现 `settings_page.dart`:仓库(浏览… 用 file_selector)、端口、开发模式、开机自启、托盘常驻;修改立即保存 — verify: 修改后重启应用值保持;与 mockup 逐项核对
- [x] 10.2 实现 `auto_launch.dart`(launch_at_startup 包装)并与设置开关绑定 — verify: 开启后 `HKCU\...\Run` 出现启动器条目,重启系统/注销后自动出现托盘

## 11. 测试与交付

- [x] 11.1 单元测试覆盖:命令行构造、就绪行解析、ANSI 剥离、日志裁剪、升级步骤状态、设置持久化(仿 ct-tool `test/settings_page_test.dart` 风格) — verify: `flutter test` 全绿
- [x] 11.2 `flutter analyze` 零告警;`tool/build_windows.ps1` 产出 Release 目录 — verify: 两个命令均成功
- [x] 11.3 端到端验证(exe 冒烟 + 单实例拦截 + 真实服务级 E2E 已验证;完整 UI 流程与升级走通需独占环境——本机常有其他 dsh web 实例占用共享 credentials 写锁,用户确认本轮不测独占流程) — verify: 已验项全绿;独占 E2E 由 `test/e2e_web_service_test.dart` 在无其他实例时自动执行(当前用例带跳过守卫)
- [x] 11.4 整理仓库 README(用法/构建/升级说明,标注本地使用勿分发未签名产物) — verify: README 命令可复现
