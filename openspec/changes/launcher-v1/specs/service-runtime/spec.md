## Purpose

编排 dsh web 服务生命周期:让用户通过启动器一键启动、停止、重启 Web UI,自动处理就绪检测、浏览器打开与端口冲突,减少手动开控制台的操作。

## ADDED Requirements

### Requirement: 启动 Web 服务

系统 SHALL 在用户触发启动(概览页按钮、托盘菜单或开机自启)时,以配置的 DSH checkout 目录为工作目录启动 `dsh web` 服务(`--no-open`,浏览器交由启动器打开),默认端口 3080。

#### Scenario: 启动成功
- **WHEN** 服务处于 stopped 状态且用户点击"启动"
- **THEN** 系统启动 `dsh web` 子进程,状态进入 starting,子进程输出实时进入日志页

#### Scenario: 重复触发忽略
- **WHEN** 状态为 starting 或 running 且用户再次触发启动
- **THEN** 系统不启动第二个进程

#### Scenario: 启动失败
- **WHEN** 子进程在就绪前以非零码退出
- **THEN** 状态进入 failed,日志中含退出码,界面显示失败原因

### Requirement: 就绪检测与打开界面

系统 SHALL 从 `dsh web` 子进程输出中识别 `dsh web:` 就绪行并提取其 token URL;就绪后状态进入 running。浏览器 SHALL 由 dsh 自行打开(openBrowser 默认,Loader settle 后以 token URL 打开),系统 SHALL NOT 重复打开浏览器。用户点击"打开界面"时 SHALL 使用最近一次有效的 token URL,不存在时回退到 `http://127.0.0.1:<端口>`。

#### Scenario: 就绪后状态就绪
- **WHEN** 子进程输出 `dsh web: http://127.0.0.1:3080/?token=…` 行
- **THEN** 状态进入 running,openUrl 记录该 token URL;浏览器由 dsh 自行打开,系统不额外打开

#### Scenario: 手动打开界面
- **WHEN** 状态为 running 且用户点击"打开界面"
- **THEN** 浏览器打开最近有效的 token URL

#### Scenario: 就绪行缺失
- **WHEN** 子进程输出没有出现 `dsh web:` 行但端口健康探测命中
- **THEN** 状态仍进入 running(仅状态兜底,不代开浏览器),就绪行到达后 openUrl 更新为 token URL

### Requirement: 端口占用处理

系统 SHALL 在启动前探测配置端口:该端口已有健康服务时标记为"外部已运行",不启动子进程,启动操作退化为直接打开界面;端口被无关服务占用时提示错误并阻止启动。

#### Scenario: 外部已运行
- **WHEN** 端口 3080 已有响应且服务未由本启动器启动
- **THEN** 概览页显示"已在运行(外部)",提供打开界面入口,不启动新进程

#### Scenario: 端口被占用
- **WHEN** 端口被其他程序占用且无有效健康响应
- **THEN** 启动被阻止,界面显示端口占用错误,不杀掉无关进程

### Requirement: 停止与重启

系统 SHALL 在用户触发停止/重启时结束 `dsh web` 进程树(Windows 下等效 `taskkill /T` 语义),5 秒未退出则强制结束;重启 SHALL 在同一次操作内先停止再启动。

#### Scenario: 停止服务
- **WHEN** 状态为 running 且用户点击"停止"
- **THEN** 整棵子进程树被结束,状态回到 stopped,日志记录停止原因

#### Scenario: 长时退出强制结束
- **WHEN** 停止请求发出 5 秒后子进程仍未退出
- **THEN** 系统强制结束进程树

#### Scenario: 重启服务
- **WHEN** 状态为 running 且用户点击"重启"
- **THEN** 系统先停止再重新启动,状态经 stopped 回到 starting

### Requirement: 开发模式

系统 SHALL 提供开发模式开关:开启时在启动 Web 服务的同时拉起 `pnpm run dev:web` 热更新构建,日志两路输出以 `[WEB]` / `[DEV]` 来源标记合并展示;关闭后重启服务不再拉起。

#### Scenario: 开启开发模式后启动
- **WHEN** 开发模式开启且服务启动
- **THEN** 两个子进程并发运行,日志页每条日志带来源标记

#### Scenario: 开发构建退出
- **WHEN** 开发模式运行中 `dev:web` 构建进程退出
- **THEN** 日志页提示产物链已过期,Web 服务继续运行

### Requirement: 日志视图

系统 SHALL 将子进程输出按行实时展示:剥离 ANSI 转义序列,保留最近 500 条,提供复制与清空操作,并按关键词(error/exception/traceback)标记错误行。

#### Scenario: 日志滚动
- **WHEN** 子进程持续输出超过 500 行
- **THEN** 日志页只保留最近 500 条,新日志自动跟随滚动

#### Scenario: 复制与清空
- **WHEN** 用户在日志页点击"复制"
- **THEN** 全部日志文本进入剪贴板;点击"清空"后日志列表为空
