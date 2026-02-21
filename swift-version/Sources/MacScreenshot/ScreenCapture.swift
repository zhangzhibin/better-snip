import Cocoa
import CoreGraphics

enum ScreenCapture {
    /// 截取指定屏幕全屏，仅返回 CGImage，不写剪贴板
    static func captureFullImage(displayID: CGDirectDisplayID) -> CGImage? {
        guard let cgImage = CGDisplayCreateImage(displayID) else {
            NSLog("[ScreenCapture] CGDisplayCreateImage failed for display %u", displayID)
            return nil
        }
        return cgImage
    }

    /// 全屏截图 → 写入剪贴板
    @discardableResult
    static func captureFullScreen(displayID: CGDirectDisplayID) -> Bool {
        guard let cgImage = captureFullImage(displayID: displayID) else { return false }
        return writeToClipboard(cgImage)
    }

    /// 从已有 CGImage 中裁剪区域并写入剪贴板
    /// rect 为 points 坐标，内部乘以 scale 转为像素坐标
    @discardableResult
    static func cropAndWrite(image: CGImage, rect: CGRect, scale: CGFloat) -> Bool {
        let pixelRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral
        guard pixelRect.width >= 2, pixelRect.height >= 2,
              let cropped = image.cropping(to: pixelRect) else {
            NSLog("[ScreenCapture] cropping failed")
            return false
        }
        return writeToClipboard(cropped)
    }

    /// 从 NSScreen 获取 CGDirectDisplayID
    static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
    }

    static func writeToClipboard(_ cgImage: CGImage) -> Bool {
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
