import Cocoa
import CoreGraphics

struct WindowInfo {
    let windowID: CGWindowID
    /// Quartz 坐标（左上角原点）
    let bounds: CGRect
    let ownerName: String
    let windowName: String
    let ownerPID: pid_t
}

enum WindowPicker {
    private static let myPID = ProcessInfo.processInfo.processIdentifier

    /// 将 AppKit 屏幕坐标（左下角原点）转为 Quartz 坐标（左上角原点）
    static func appKitToQuartz(point: NSPoint) -> CGPoint {
        guard let mainScreen = NSScreen.screens.first else { return CGPoint(x: point.x, y: point.y) }
        return CGPoint(x: point.x, y: mainScreen.frame.height - point.y)
    }

    /// 将 Quartz 坐标的 rect 转为 AppKit 屏幕坐标
    static func quartzToAppKit(rect: CGRect) -> NSRect {
        guard let mainScreen = NSScreen.screens.first else { return rect }
        let y = mainScreen.frame.height - rect.origin.y - rect.height
        return NSRect(x: rect.origin.x, y: y, width: rect.width, height: rect.height)
    }

    /// 查找鼠标下最前面的窗口（排除自己的窗口）
    static func windowUnderMouse() -> WindowInfo? {
        let mouseAppKit = NSEvent.mouseLocation
        let mouseQuartz = appKitToQuartz(point: mouseAppKit)

        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for entry in list {
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  pid != myPID,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let wid = entry[kCGWindowNumber as String] as? CGWindowID else { continue }

            // kCGWindowLayer 0 = 普通窗口
            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }

            let x = boundsDict["X"] ?? 0
            let y = boundsDict["Y"] ?? 0
            let w = boundsDict["Width"] ?? 0
            let h = boundsDict["Height"] ?? 0
            let bounds = CGRect(x: x, y: y, width: w, height: h)

            guard bounds.width > 1, bounds.height > 1 else { continue }

            if bounds.contains(mouseQuartz) {
                let ownerName = entry[kCGWindowOwnerName as String] as? String ?? ""
                let windowName = entry[kCGWindowName as String] as? String ?? ""
                return WindowInfo(windowID: wid, bounds: bounds, ownerName: ownerName, windowName: windowName, ownerPID: pid)
            }
        }
        return nil
    }

    /// 截取指定窗口（含阴影）
    static func captureWindow(windowID: CGWindowID) -> CGImage? {
        CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.bestResolution]
        )
    }
}
