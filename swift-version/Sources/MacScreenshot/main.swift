import Cocoa

// 隐藏 Dock 图标，仅显示菜单栏托盘
NSApp.setActivationPolicy(.accessory)

let delegate = AppDelegate()
NSApp.delegate = delegate
NSApp.run()
