import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Flutter's native surface defaults to black before the first Dart frame.
    let surfaceColor = NSColor(srgbRed: 245 / 255, green: 246 / 255, blue: 244 / 255, alpha: 1)
    backgroundColor = surfaceColor
    flutterViewController.backgroundColor = surfaceColor
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  // 窗口必须在 nib 加载时被 order(可见)一次:FlutterViewController 的 view
  // 才会加载、Flutter 引擎才会启动 Dart 入口。若 xib 里设 visibleAtLaunch="NO",
  // 窗口永不 order → 引擎不启动 → Dart main 不执行 → 谁也没机会调用 show(),
  // 窗口永远不出现。
  // 这里 order 完立刻隐藏,避免深色/空白原生窗口在首帧前闪现(对齐 ct-tool/FlClash),
  // 之后由 Dart 侧 windowManager.show() 正式显示。
  override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}
