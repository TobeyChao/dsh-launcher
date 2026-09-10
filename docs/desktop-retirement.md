# 桌面端(Electron)退役记录

## 结论

DSH 桌面端(Electron,`deepseek-harness/apps/desktop`)停用。用户决定:Web UI 是主力入口,由本仓库的 dsh-launcher(Flutter 托盘启动器)接管启动;桌面端相关的本地产物已全部删除。本文档记录删了什么、何时能恢复、以及恢复的代价。

## 已删除清单(2026-09,本机)

| 路径 | 大小 | 说明 |
|---|---|---|
| `<dsh-checkout>\apps\desktop\.desktop-build` | 1.1 GB | prepare 产物:离线 seed、desktop-host、win-unpacked(`DeepSeek Harness.exe`) |
| `<dsh-checkout>\apps\desktop\electron-builder.local.config.mjs` | - | 本地免签 electron-builder 配置(未跟踪) |
| `<dsh-checkout>\upgrade-dsh-desktop.ps1` | - | 桌面端一键升级脚本(未跟踪) |
| `%USERPROFILE%\.dsh\profiles\desktop` | ~565 MB | 桌面端 profile(npm project + node_modules) |
| `%USERPROFILE%\.dsh\desktop` | - | 桌面端 pnpm store |
| `apps\desktop\node_modules\electron` | 367 MB | 手动经 `ELECTRON_MIRROR` 下载的 electron 二进制 |

## 保留未动

- `deepseek-harness` 仓库本身跟踪文件:`git status` 无任何修改;`.gitignore` 第 31 行的 `apps/desktop/.desktop-build/` 是**上游自带**,未回退(它继续为未来的桌面构建服务)。
- `~/.dsh` 共享数据:sessions / settings.yaml / .credentials.yaml / workspaces 等——与 Web、CLI 共用,不能删。
- `~/.dsh/profiles/web`:Web profile 完好,启动器继续使用。
- 注册表:无 `dsh-app` 协议残留(本地未运行安装器);无桌面进程在运行后删除(删除前已确认)。

## 验证状态

- `git status --porcelain` 仅剩上游已有的未跟踪项(`.agents/skills/*`、`openspec/`),与本决定无关。
- 该 checkout 约释放 2 GB 以上空间。

## 恢复桌面端的路径(若将来改变主意)

**官方管道**(要求签名环境,否则 `electron-builder.config.mjs` 构造即抛错):
`DSH_DESKTOP_APP_ID` + `DOWNLOAD_TEST_ORIGIN` + Windows EV 签名四要素(证书文件 / SignTool / KeyContainer / TokenPIN),`forceCodeSigning: true` 拒未签名产物。

**本地免签重建**(仅自用,勿分发):
1. `pnpm install`(会重新拉 electron);
2. 在 `apps/desktop` 重建 `electron-builder.local.config.mjs`:复制官方 `electron-builder.config.mjs`,删除 signer 构造与 `forceCodeSigning`、`publish`、`mac`、`linux`、`afterSign`,设 `appId: com.local.dsh-desktop`、`electronDist: node_modules/electron/dist`、`win.target: ['dir']`;
3. `pnpm run prepare:desktop`(重建 seed 等,约 30–60 分钟,无旧缓存可复用);
4. `pnpm exec electron-builder --config electron-builder.local.config.mjs --win --x64 --dir --publish never`;
5. 产物在 `apps/desktop/.desktop-build/targets/win-x64/artifacts/win-unpacked/`;桌面 profile 在首次运行时自动重建。

完整前置条件与 npm 依赖同官方 `apps/desktop/package.json` 的 `package:desktop:*` 脚本;上游源码完全保留,未做任何改动。

## 注意

- 对该 checkout 不要执行 `git clean -fdx`(会删除 `.agents/skills/*`、`openspec/` 等未跟踪项)。
- launcher-v1 升级流程第 4 步 `pnpm run clean && pnpm run build`:现在无桌面缓存需要保护,已是最终形态。
