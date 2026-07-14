import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift render_icon.swift OUTPUT.png\n", stderr)
    exit(2)
}

let size = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let canvas = NSRect(x: 0, y: 0, width: size, height: size)
NSColor.clear.setFill(); canvas.fill()

let background = NSGradient(colors: [NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.16, alpha: 1), NSColor(calibratedRed: 0.38, green: 0.22, blue: 0.75, alpha: 1)])!
background.draw(in: NSBezierPath(roundedRect: canvas.insetBy(dx: 32, dy: 32), xRadius: 220, yRadius: 220), angle: -45)

NSColor.white.withAlphaComponent(0.96).setFill()
NSBezierPath(roundedRect: NSRect(x: 150, y: 180, width: 724, height: 500), xRadius: 58, yRadius: 58).fill()

NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
let clapper = NSBezierPath()
clapper.move(to: NSPoint(x: 160, y: 650)); clapper.line(to: NSPoint(x: 838, y: 748)); clapper.line(to: NSPoint(x: 856, y: 850)); clapper.line(to: NSPoint(x: 178, y: 752)); clapper.close(); clapper.fill()

NSColor(calibratedRed: 0.31, green: 0.28, blue: 0.88, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 235, y: 310, width: 220, height: 220)).fill()
NSColor.white.setFill()
let play = NSBezierPath(); play.move(to: NSPoint(x: 325, y: 365)); play.line(to: NSPoint(x: 325, y: 475)); play.line(to: NSPoint(x: 418, y: 420)); play.close(); play.fill()

NSColor(calibratedRed: 0.12, green: 0.69, blue: 0.35, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 650, y: 220, width: 150, height: 150)).fill()
NSColor.white.setStroke()
let check = NSBezierPath(); check.lineWidth = 24; check.lineCapStyle = .round; check.lineJoinStyle = .round
check.move(to: NSPoint(x: 684, y: 292)); check.line(to: NSPoint(x: 716, y: 260)); check.line(to: NSPoint(x: 769, y: 326)); check.stroke()

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
