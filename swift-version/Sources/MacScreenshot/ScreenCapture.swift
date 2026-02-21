import Cocoa
import CoreGraphics

enum ScreenCapture {
    /// 全屏截图指定屏幕 → 写入剪贴板
    @discardableResult
    static func captureFullScreen(displayID: CGDirectDisplayID) -> Bool {
        guard let cgImage = CGDisplayCreateImage(displayID) else {
            NSLog("[ScreenCapture] CGDisplayCreateImage failed for display %u", displayID)
            return false
        }
        return writeToClipboard(cgImage)
    }

    /// 区域截图指定屏幕（左上角原点，points）→ 写入剪贴板
    @discardableResult
    static func captureRegion(displayID: CGDirectDisplayID, rect: CGRect) -> Bool {
        guard rect.width >= 2, rect.height >= 2 else { return false }
        guard let cgImage = CGDisplayCreateImage(displayID, rect: rect) else {
            NSLog("[ScreenCapture] CGDisplayCreateImage(rect:) failed for display %u", displayID)
            return false
        }
        return writeToClipboard(cgImage)
    }

    /// 从 NSScreen 获取 CGDirectDisplayID
    static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
    }

    private static func writeToClipboard(_ cgImage: CGImage) -> Bool {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let tiffData = rep.tiffRepresentation else {
            NSLog("[ScreenCapture] tiffRepresentation failed")
            return false
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(tiffData, forType: .tiff)
        if let pngData = rep.representation(using: .png, properties: [:]) {
            pasteboard.setData(pngData, forType: .png)
        }
        return true
    }
}
