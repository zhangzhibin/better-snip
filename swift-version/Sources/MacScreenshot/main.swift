import Cocoa

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate

// 直接初始化托盘（不依赖 delegate 回调）
appDelegate.setupTray()
app.setActivationPolicy(.accessory)

app.run()
