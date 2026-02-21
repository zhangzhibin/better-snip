# Mac Screenshot

极简 macOS 截图工具：系统托盘调起 → 全屏/区域截图 → 剪贴板。

## 版本

| 目录 | 技术栈 | 状态 |
|------|--------|------|
| `tauri-version/` | Tauri 2 + Rust + Core Graphics | 已完成基础功能 |
| `swift-version/` | Swift + AppKit + Core Graphics | 开发中 |

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
# 待补充
```
