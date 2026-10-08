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

    /// 从已有 CGImage 中裁剪区域，返回裁剪后的 CGImage
    static func cropImage(_ image: CGImage, rect: CGRect, scale: CGFloat) -> CGImage? {
        let pixelRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral
        guard pixelRect.width >= 2, pixelRect.height >= 2 else { return nil }
        return image.cropping(to: pixelRect)
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

    /// 把 flipped 视图里的选区（左上角原点、单位 point）转成该屏幕的 AppKit 矩形。
    static func appKitRect(fromFlippedLocal rect: NSRect, on screen: NSScreen) -> NSRect {
        NSRect(
            x: screen.frame.minX + rect.minX,
            y: screen.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// 按偏好设置的格式写入文件。同一秒内重名时追加序号。失败返回 nil。
    static func saveImage(_ cgImage: CGImage, to directory: URL) -> URL? {
        let format = AppPreferences.imageFormat
        guard let data = ImageFileWriter.data(for: cgImage, format: format, quality: AppPreferences.imageQuality) else {
            NSLog("[ScreenCapture] encode failed")
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stamp = formatter.string(from: Date())
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            NSLog("[ScreenCapture] create directory failed: \(error.localizedDescription)")
            return nil
        }
        let ext = format.fileExtension
        var url = directory.appendingPathComponent("Screenshot \(stamp).\(ext)")
        var index = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("Screenshot \(stamp) \(index).\(ext)")
            index += 1
        }
        do {
            try data.write(to: url)
            return url
        } catch {
            NSLog("[ScreenCapture] write image failed: \(error.localizedDescription)")
            return nil
        }
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
        if let pngData = ImageFileWriter.losslessPNG(cgImage) {
            pasteboard.setData(pngData, forType: .png)
        }
        return true
    }
}
