import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    // 窗口最小尺寸：再小会触发多处布局溢出，设下限根治
    self.minSize = NSSize(width: 960, height: 600)

    // 标题栏融入应用：透明标题栏 + 隐藏标题文字 + 内容延伸到顶部，
    // 让 Flutter 侧深色 TopBar 顶到最上方，与红绿灯同一行，风格统一。
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.title = ""
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true

    // 红绿灯垂直居中：挂一个 unified toolbar 让标题栏区域加高，
    // AppKit 会自动把红绿灯按钮在加高后的标题栏内垂直居中（原生可靠）。
    let toolbar = NSToolbar(identifier: "MainToolbar")
    toolbar.showsBaselineSeparator = false
    self.toolbar = toolbar
    if #available(macOS 11.0, *) {
      self.toolbarStyle = .unified
    }

    // 记忆窗口大小/位置：用户调整后自动存到系统偏好，重启按上次尺寸打开
    self.setFrameAutosaveName("LowenSSHMainWindow")

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
