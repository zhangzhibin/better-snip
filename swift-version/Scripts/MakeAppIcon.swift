import Cocoa

/// 画一张满幅截图图标。系统会自己裁成圆角，这里不预留透明边。
let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { rect in
    NSColor(calibratedRed: 0.11, green: 0.39, blue: 0.95, alpha: 1).setFill()
    rect.fill()

    let white = NSColor.white
    let frame = rect.insetBy(dx: 250, dy: 270)
    let screen = NSBezierPath(roundedRect: frame, xRadius: 28, yRadius: 28)
    screen.lineWidth = 36
    white.setStroke()
    screen.stroke()

    let arm: CGFloat = 168
    let thick: CGFloat = 58
    let margin: CGFloat = 132
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
