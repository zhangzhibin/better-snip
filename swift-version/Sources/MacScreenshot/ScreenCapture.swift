import Cocoa
import CoreGraphics

enum ScreenCapture {
    /// 全屏截图 → 写入剪贴板，返回是否成功
    @discardableResult
    static func captureFullScreen() -> Bool {
        guard let cgImage = CGDisplayCreateImage(CGMainDisplayID()) else {
            NSLog("[ScreenCapture] CGDisplayCreateImage failed (need Screen Recording permission)")
            return false
        }
        return writeToClipboard(cgImage)
    }

    /// 区域截图（左上角原点，points）→ 写入剪贴板
    @discardableResult
    static func captureRegion(rect: CGRect) -> Bool {
        guard rect.width >= 2, rect.height >= 2 else { return false }
        guard let cgImage = CGDisplayCreateImage(CGMainDisplayID(), rect: rect) else {
            NSLog("[ScreenCapture] CGDisplayCreateImage(rect:) failed")
            return false
        }
        return writeToClipboard(cgImage)
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
        // 同时写入 PNG 格式，兼容更多应用
        if let pngData = rep.representation(using: .png, properties: [:]) {
            pasteboard.setData(pngData, forType: .png)
        }
        return true
    }
}
