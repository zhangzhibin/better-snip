# Mac Screenshot

极简 Mac 截图工具：菜单调起 → 选区 → 原生截屏 → 剪贴板（可选保存文件待加）。

- **技术栈**: Tauri 2 + Rust + 原生 Core Graphics 截屏
- **平台**: 仅 macOS

## 运行

```bash
# 安装依赖
npm install

# 开发（需先授权「屏幕录制」）
npm run dev

# 打包
npm run build
```

## 使用

1. 启动应用后，菜单栏会出现 **Screenshot**。
2. 选择 **Capture Region**，进入全屏选区。
3. 拖拽鼠标画出矩形，松开即截屏并写入剪贴板，选区窗口自动关闭。
4. 按 **Esc** 取消截屏。

首次截屏时，系统会请求 **屏幕录制** 权限，需在「系统设置 → 隐私与安全性 → 屏幕录制」中允许本应用。

## 可选保存到文件

当前版本仅写入剪贴板。保存到文件可在后续版本中通过菜单或选区完成后的「保存」按钮实现（由 `capture_region` 的 `save_to_file` 参数支持）。

## 调试

- **Mac 打开开发者工具**：在应用窗口聚焦时按 **⌘ Command + Option + I**（不是 F12）。
- 选区截屏若失败，会在**选区窗口顶部**显示红色错误信息约 8 秒；同时可看**运行 `npm run dev` 的终端**里是否有 `[capture_region]` 相关输出。
- **调试日志文件**：所有关键步骤（打开选区窗口、前端 finish、invoke、Rust 侧 capture_region 调用与错误）会追加写入到系统临时目录下的 **`mac-screenshot-debug.log`**。  
  - 用终端运行一次应用即可在启动时看到日志路径，例如：`[mac-screenshot] debug log: /var/folders/.../T/mac-screenshot-debug.log`。  
  - 或在主窗口通过开发者工具执行 `await window.__TAURI__.core.invoke('get_debug_log_path')` 得到路径后，在 Finder 中「前往 → 前往文件夹」粘贴打开。  
  - 若日志里没有 `[frontend] finish(...)`，说明选区结束时代码未执行到 invoke；若没有 `capture_region called`，说明前端 invoke 未到达 Rust（权限或窗口未匹配能力集）。

## 项目结构

- `capture.html` / `capture.js`：全屏选区页面
- `src-tauri/src/lib.rs`：菜单、选区窗口、`capture_region` / `close_capture_window` 命令
- `src-tauri/src/capture_macos.rs`：macOS 下 Core Graphics 区域截屏与 PNG 输出
