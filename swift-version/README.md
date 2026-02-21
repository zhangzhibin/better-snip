# Mac Screenshot — Swift 原生版本

使用 Swift + AppKit 重写的 macOS 原生截图工具。

## 技术方案

- **语言**：Swift 5.9+
- **框架**：AppKit（精确控制 NSWindow 层级和透明度）
- **截屏**：`CGDisplayCreateImageForRect`（macOS 10.15+）或 `ScreenCaptureKit`（macOS 12.3+）
- **剪贴板**：`NSPasteboard`
- **托盘**：`NSStatusBar` / `NSStatusItem`
- **隐藏 Dock**：`NSApplication.ActivationPolicy.accessory`

## 功能目标

与 Tauri 版本功能对齐，参见 `docs/spec.md`：

- 系统托盘菜单（全屏截图 / 区域截图 / 退出）
- 全屏截图 → 剪贴板
- 区域截图（透明覆盖窗口 + 拖拽选区）→ 剪贴板
- 截图成功闪屏反馈
- 无 Dock 图标、无主窗口

## 开发

无需 Xcode，使用 Swift Package Manager + 命令行即可：

```bash
# 编译并运行（会包装成 .app，自动获取屏幕录制权限）
./run.sh

# 仅编译（debug 模式）
swift build

# 仅编译（release 模式）
swift build -c release
```

## 项目结构

```
swift-version/
├── Package.swift               # SPM 配置
├── Sources/MacScreenshot/
│   ├── main.swift              # 入口：NSApplication 启动 + 隐藏 Dock
│   ├── AppDelegate.swift       # 托盘图标 + 菜单
│   ├── ScreenCapture.swift     # 截屏 + 写剪贴板
│   ├── OverlayWindow.swift     # 全屏透明窗口（区域选区用）
│   ├── OverlayView.swift       # 选区绘制（蒙版 + 拖拽 + 尺寸信息）
│   └── FlashWindow.swift       # 截图成功闪屏
├── run.sh                      # 编译 + 打包 .app + 运行
└── README.md
```

## 注意事项

- 首次使用需在系统设置中授予屏幕录制权限
- 开发阶段通过 `run.sh` 打包为 `.app` 运行，以保证权限正常生效
- `LSUIElement = true` 在 Info.plist 中设置，确保不显示 Dock 图标
