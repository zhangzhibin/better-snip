import Cocoa

/// 满幅绘制。系统会裁成圆角，这里不留透明边。
/// 四角是选区括号，中间是和菜单栏相同的相机。
let canvas: CGFloat = 1024
let cameraConfig = NSImage.SymbolConfiguration(pointSize: 430, weight: .semibold)
let cameraSymbol = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(cameraConfig)
let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { rect in
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.28, green: 0.58, blue: 1.0, alpha: 1),
        NSColor(srgbRed: 0.06, green: 0.31, blue: 0.86, alpha: 1),
    ])
    gradient?.draw(in: rect, angle: 90)

    if let cameraSymbol {
        let whiteCamera = NSImage(size: cameraSymbol.size, flipped: false) { dest in
            NSColor.white.setFill()
            dest.fill()
            cameraSymbol.draw(in: dest, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        let origin = NSPoint(
            x: (canvas - whiteCamera.size.width) / 2,
            y: (canvas - whiteCamera.size.height) / 2 - 8
        )
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.28)
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.shadowBlurRadius = 16
        shadow.set()
        whiteCamera.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }

    let white = NSColor.white
    let arm: CGFloat = 150
    let thick: CGFloat = 62
    let margin: CGFloat = 108
    func bracket(x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat) {
        let path = NSBezierPath()
        path.lineWidth = thick
        path.lineCapStyle = .square
        path.lineJoinStyle = .miter
        path.move(to: NSPoint(x: x + dx * arm, y: y))
        path.line(to: NSPoint(x: x, y: y))
        path.line(to: NSPoint(x: x, y: y + dy * arm))
        white.setStroke()
        path.stroke()
    }
    bracket(x: margin, y: margin, dx: 1, dy: 1)
    bracket(x: canvas - margin, y: margin, dx: -1, dy: 1)
    bracket(x: margin, y: canvas - margin, dx: 1, dy: -1)
    bracket(x: canvas - margin, y: canvas - margin, dx: -1, dy: -1)
    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to encode icon\n", stderr)
    exit(1)
}
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
try png.write(to: URL(fileURLWithPath: output))
