import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Dock 图标不做运行时替换:actool 已按 ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon
  // 生成 Assets.car + AppIcon.icns,Xcode 也会把 CFBundleIconFile/CFBundleIconName
  // 写进 Info.plist,图标由 bundle 静态提供。
  // 不要再加 applicationDidFinishLaunching 覆写:FlutterAppDelegate 只声明了
  // NSApplicationDelegate 的 @objc optional 方法、并未实现它,写 super 会在
  // objc_msgSendSuper 找不到实现时抛 NSInvalidArgumentException,被 AppKit 吞掉后
  // 引擎不再启动(Dart main 不执行),窗口永远不出现。

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 窗口关闭后应用不退出,托盘常驻由 Dart 侧决策。
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    // 隐藏到托盘后,Dock 图标要能把窗口找回来(对齐 ct-tool/FlClash)。
    if !flag {
      for window in NSApp.windows where !window.isVisible {
        window.setIsVisible(true)
        window.makeKeyAndOrderFront(self)
      }
      NSApp.activate(ignoringOtherApps: true)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
