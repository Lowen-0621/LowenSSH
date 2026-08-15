import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var defaultTrafficLightY: CGFloat?

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
    // 不让原生窗口把 Flutter 内容区当作拖动区域，否则按钮会收到 hover 却收不到点击。
    // 原生标题栏本身仍可正常拖动窗口。
    self.isMovableByWindowBackground = false

    // 使用紧凑统一工具栏，让红绿灯与 64px Flutter 顶栏保持接近的视觉中线，
    // 同时避免普通 unified toolbar 把标题栏撑得过高。
    let toolbar = NSToolbar(identifier: "MainToolbar")
    toolbar.showsBaselineSeparator = false
    self.toolbar = toolbar
    if #available(macOS 11.0, *) {
      self.toolbarStyle = .unifiedCompact
    }

    // 记忆窗口大小/位置：用户调整后自动存到系统偏好，重启按上次尺寸打开
    self.setFrameAutosaveName("LowenSSHMainWindow")

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // fullSizeContentView 下系统按钮仍按原生标题栏上沿排布，会比 Flutter
    // 64px 顶栏中线偏高。记录系统基准位置后统一下移，避免重复布局时累积偏移。
    DispatchQueue.main.async { [weak self] in
      self?.alignTrafficLights()
    }
  }

  private func alignTrafficLights() {
    guard let close = standardWindowButton(.closeButton) else { return }
    if defaultTrafficLightY == nil {
      defaultTrafficLightY = close.frame.origin.y
    }
    guard let baseY = defaultTrafficLightY else { return }
    let centeredY = max(0, baseY - 11)
    for type in [
      NSWindow.ButtonType.closeButton,
      .miniaturizeButton,
      .zoomButton,
    ] {
      guard let button = standardWindowButton(type) else { continue }
      button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: centeredY))
    }
  }
}
