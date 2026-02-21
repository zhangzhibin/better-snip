# Mac Screenshot — Swift 原生版本

使用 Swift + AppKit 重写的 macOS 原生截图工具。

## 技术方案

- **语言**：Swift 5.9+
- **框架**：AppKit（精确控制 NSWindow 层级和透明度）
- **截屏**：`CGDisplayCreateImage`（Core Graphics）
- **剪贴板**：`NSPasteboard`（TIFF + PNG 双格式）
- **托盘**：`NSStatusBar` / `NSStatusItem`
- **隐藏 Dock**：`NSApplication.ActivationPolicy.accessory` + `LSUIElement`

## 功能

- 系统托盘菜单（全屏截图 / 区域截图 / 退出）
- 多屏幕支持：鼠标移动选屏（红色边框），点击确认
- 全屏截图 → 剪贴板
- 区域截图：选屏后立即截取全屏，在静态截图上拖选裁剪 → 剪贴板
- 截图成功闪屏反馈（目标屏幕）
- 不改变当前活跃窗口状态

## 开发

无需 Xcode，使用 Swift Package Manager + 命令行：

```bash
# 编译并运行（包装成 .app，自动获取屏幕录制权限）
./run.sh

# 仅编译
swift build            # debug
swift build -c release # release
```

## 项目结构

```
swift-version/
├── Package.swift                   # SPM 配置
├── Sources/MacScreenshot/
│   ├── main.swift                  # 入口：NSApplication 启动 + 隐藏 Dock
│   ├── AppDelegate.swift           # 托盘菜单 + 选屏/截图流程编排
│   ├── ScreenCapture.swift         # 截屏 + 裁剪 + 写剪贴板
│   ├── ScreenPickerWindow.swift    # 选屏透明窗口
│   ├── ScreenPickerView.swift      # 选屏红色边框 + 鼠标交互
│   ├── OverlayWindow.swift         # 区域选区窗口（背景为已截图片）
│   ├── OverlayView.swift           # 选区绘制（蒙版 + 拖拽 + 尺寸信息）
│   └── FlashWindow.swift           # 截图成功闪屏
├── run.sh                          # 编译 + 打包 .app + 运行
└── README.md
```

## 注意事项

- 首次使用需在系统设置中手动添加 app 并授予屏幕录制权限
- 开发阶段通过 `run.sh` 打包为 `.app` 运行，以保证权限正常生效
- `LSUIElement = true` 在 Info.plist 中设置，确保不显示 Dock 图标
- 详细规格参见 `docs/spec.md`
