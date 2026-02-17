# 区域截图坐标与参考实现

## 1. Apple Core Graphics 约定

- **`CGDisplay::bounds()`**：主显示器在「全局显示坐标系」中的范围，单位是 **points**（逻辑坐标），不是物理像素。Retina 下例如 1440×900 points。
- **坐标系**：Quartz 2D 默认 **左下角为原点、Y 轴向上**。因此「屏幕顶部」对应较大的 y，「屏幕底部」对应 y=0。
- **`image_for_rect(CGRect)`**：参数必须是**同一全局显示坐标系**下的 rect，即 **points、左下角原点**。
- **`CGDisplay`** 另有 `pixels_wide()` / `pixels_high()`：物理像素（如 Retina 2880×1800）。截图 API 用的是 **points**，不是 pixels。

因此：我们传给 `capture_region_png` 的 rect 必须是 **points、左上角语义**（再在内部转成 CG 的左下角 y）。

---

## 2. 本项目的坐标流

```
[前端] 全屏透明窗口内拖拽
  → clientX, clientY, width, height (选区，左上角为原点)
  → 后端 capture_region(region)
  → 后端按 scale_factor 换算（当前：region / scale → points）
  → capture_region_png(rect) 内：rect 转 CG 左下角 y_bottom = bounds.height - rect.y - rect.height
  → CGDisplay::image_for_rect(cg_rect) → PNG
```

关键分歧：**前端传来的 (x, y, w, h) 是「物理像素」还是「逻辑像素（points / CSS 像素）」？**

- 若窗口用 **PhysicalSize** 全屏，WebView 的 `clientX/clientY` 在多数实现里与**设备像素**一致（即物理像素），需要 **÷ scale_factor** 得到 points。
- 若 WebView/布局使用逻辑尺寸（例如 1440×900），则前端已是 points，**不应再除 scale**，否则会缩小且偏上。

当前实现按「前端是物理像素」做了 **÷ scale**。若实际是逻辑像素，就会出现往左下偏、宽高偏小。

---

## 3. 参考：其他项目

### Flameshot (Qt)

- 使用 Qt 的 **逻辑坐标**（device-independent），与系统 DPI 缩放一致。
- 抓屏通过 Qt 或平台抽象拿到「屏幕」图像，选区也是同一套逻辑坐标，**不混用物理像素**。
- 启示：**整条链路统一用一种单位**（我们应统一用 points）。

### 常见做法小结

| 项目 / 系统 | 选区坐标单位 | 截屏 API 单位 | 处理方式 |
|-------------|--------------|----------------|----------|
| Apple CG    | -            | points，左下角 | 传 points，y 转左下角 |
| Qt/Flameshot| 逻辑像素     | 逻辑/平台抽象  | 不乘除 scale，统一逻辑 |
| 本项（假设 A）| 物理像素    | points         | 后端 ÷ scale_factor |
| 本项（假设 B）| 逻辑像素    | points         | 后端不除 scale |

---

## 4. 我们与「标准」的差异点

1. **Y 轴与原点**  
   - 我们：前端左上角 (0,0)，后端用 `y_bottom = bounds.height - rect.y - rect.height` 转 CG。  
   - 与 Apple「左下角原点」一致，**这一块逻辑是对的**。

2. **单位（points vs pixels）**  
   - 我们：用 Tauri 的 **PhysicalSize** 设全屏，再用 **scale_factor** 把前端坐标当物理像素除成 points。  
   - 若 Tauri/WebView 在前端给的其实是**逻辑像素**（与 bounds 同系），就会**重复缩小** → 往左下偏、宽高偏小。

3. **窗口与屏幕的对应关系**  
   - 我们：`primary_monitor()` 的 size/position 设窗口，认为窗口 (0,0) 对应主屏左上角。  
   - 若 macOS 在**多屏或菜单栏**下给的不是「主屏左上角 = 窗口 (0,0)」，可能还有**整体偏移**（例如菜单栏高度）。需用诊断图确认。

---

## 5. 通用做法：窗口位置转屏幕坐标

**winit** 文档：`inner_position()` 返回窗口**内容区**左上角相对于「桌面左上角」的坐标（物理像素）。  
因此：**屏幕上的选区 = 窗口内容区位置 + 选区在窗口内的坐标**。  
在「不除 scale」的前提下（前端坐标已是逻辑像素），将 `inner_position()` 转为逻辑坐标（÷ scale）后加到 `rect.x`、`rect.y`，即可得到正确的屏幕 rect，无需手调固定 Y 偏移。  
实现上在 `region_to_rect` 中：当使用默认或 NoScale 方案时，读取主窗口 `inner_position()` 与 `scale_factor()`，计算 `(ox, oy) = (pos.x/scale, pos.y/scale)`，令 `rect.x += ox`, `rect.y += oy`。

## 6. 建议的下一步（可选）

1. **跑诊断**  
   用菜单「Test: 不除scale+诊断图」做一次区域截图，看桌面上的 overlay / crop 是否与选区一致。

2. **文档**  
   - 在代码里注明：`capture_region_png` 的 `CaptureRect` 为 **points、左上角为原点**；CG 内部再转左下角。

---

## 7. 参考资料

- [core-graphics 0.24 CGDisplay](https://docs.rs/core-graphics/0.24.0/core_graphics/display/struct.CGDisplay.html)：`bounds()` 为 global display coordinate space；`image_for_rect(bounds)` 为同一坐标系。
- Flameshot：Qt 逻辑坐标 + 平台抓屏抽象，不混用物理像素。
- Tauri：`PhysicalSize` / `LogicalSize`、`scale_factor()`，用于在前端与后端之间统一单位。
