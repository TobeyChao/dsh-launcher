# DeepSeek Harness Launcher 图标

应用图标以 DeepSeek 蓝鲸鱼为主体，白色圆角底板搭配 `>_` 终端提示符，表达 Harness 本地开发工具的用途。Windows、macOS、应用内侧栏使用同一母版；macOS 菜单栏使用同一鲸鱼的单色轮廓，保证小尺寸和系统深浅色下清晰可辨。

鲸鱼轮廓参考 [DeepSeek Harness 官网 favicon](https://www.deepseek.com/harness/favicon.svg)，原始 SVG 保存为 `assets/branding/deepseek-whale.svg`。应用图标使用内置 imagegen 生成；菜单栏模板从官方 SVG 保留路径、去除媒体样式并设置黑色填充后导出，系统使用其 alpha 蒙版着色。

## 母版和导出

- `assets/branding/app_icon_source.png`：最终应用图标母版。
- `assets/branding/tray_icon_template.svg`、`tray_icon_source.png`：菜单栏矢量模板与 1024px PNG 母版。
- `python3 tool/gen_icons.py`：需要 Pillow，导出两平台应用图标、托盘和侧栏资源。
- 修改菜单栏 SVG 后，可用 `rsvg-convert -w 1024 -h 1024 assets/branding/tray_icon_template.svg -o assets/branding/tray_icon_source.png` 更新其 PNG 母版，再执行统一导出。

## 生成提示词

最终输出另外执行背景提取以确保真实 alpha 通道：

> Use case: background-extraction. Remove the gray checkerboard background from this image entirely. Return the white rounded-square DeepSeek whale app icon with a REAL alpha transparency channel outside its perimeter. The checkerboard is an unwanted background that must be removed, NOT drawn or simulated. Keep the entire white tile, blue whale, navy terminal symbol and all interior white pixels exactly intact. Clean continuous edge, no stray fragments, no halos, no checkerboard pixels, no shadow. Do not change or redraw the design. Deliver a transparent PNG cutout with equal margin.

内置 imagegen，参考图片为官方鲸鱼 SVG 的 PNG 渲染：

> Use case: logo-brand. Reference image: official DeepSeek whale brand silhouette; preserve this instantly recognizable whale profile, open mouth, eye and lifted tail rather than inventing a different whale. Create ONE beautiful production desktop icon for DeepSeek Harness Launcher, an app that launches the DeepSeek Harness local agent terminal/web service. A refined native macOS/Windows app icon: soft off-white porcelain rounded square tile, subtle restrained edge depth, front-facing, transparent outside the tile. Center a large DeepSeek brand-blue (#4D6BFE) whale from the reference, recognizable at small sizes. Integrate a small bold navy terminal prompt >_ tucked below the whale toward the lower right, visually subordinate to the whale, to clearly indicate Harness developer tooling. Intentional clean composition, the whale is the hero with plenty of breathing room, no busy background. Flat precise emblem with only very gentle dimensional treatment on the tile; polished and calm, NOT glossy plastic. Tile occupies 86% of a square 1024x1024 canvas, equal transparent margins. No letters, no words, no power button, no up arrow, no rockets, no badges, no unrelated motifs, no watermark, no scene, no mockup. Genuinely transparent background.

透明边缘清理：

> undefined
