# Mac Screenshot

极简 macOS 截图工具：全局快捷键或菜单栏调起 → 拖选区域或点选窗口 → 标注 → 剪贴板或文件。

## 版本

| 目录 | 技术栈 | 状态 |
|------|--------|------|
| `tauri-version/` | Tauri 2 + Rust + Core Graphics | 已完成基础功能 |
| `swift-version/` | Swift + AppKit + Core Graphics | 活跃开发 |

## 文档

- `docs/spec.md` — 产品与技术规格
- `docs/region-capture-coordinates.md` — macOS 坐标系说明

## 各版本运行方式

### Tauri 版本

```bash
cd tauri-version
npm install
npx tauri dev
```

### Swift 版本

```bash
cd swift-version
./run.sh
```
