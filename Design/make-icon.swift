// Renders the CoMo Events app icon at 1024x1024.
// Usage: swift Design/make-icon.swift Design/icon-1024.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"

let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no context") }

// Background: warm sunset gradient (top-left orange -> bottom-right deep violet)
let cs = CGColorSpaceCreateDeviceRGB()
let bg = CGGradient(colorsSpace: cs, colors: [
    NSColor(red: 1.00, green: 0.55, blue: 0.20, alpha: 1).cgColor,
    NSColor(red: 0.93, green: 0.29, blue: 0.45, alpha: 1).cgColor,
    NSColor(red: 0.36, green: 0.20, blue: 0.70, alpha: 1).cgColor,
] as CFArray, locations: [0, 0.5, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// Faint street grid, like a map
ctx.saveGState()
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.10).cgColor)
ctx.setLineWidth(6)
for i in stride(from: -size, through: size * 2, by: 128) {
    ctx.move(to: CGPoint(x: i, y: 0)); ctx.addLine(to: CGPoint(x: i + size * 0.35, y: size))
    ctx.move(to: CGPoint(x: 0, y: i)); ctx.addLine(to: CGPoint(x: size, y: i - size * 0.35))
}
ctx.strokePath()
ctx.restoreGState()

// Busy-area halo rings around the pin tip
let tip = CGPoint(x: size / 2, y: 215)
for (r, a) in [(300.0, 0.10), (210.0, 0.16), (120.0, 0.26)] {
    ctx.setFillColor(NSColor.white.withAlphaComponent(a).cgColor)
    ctx.fillEllipse(in: CGRect(x: tip.x - r, y: tip.y - r * 0.45, width: r * 2, height: r * 0.9))
}

// Pin: circle head + pointed base, with soft shadow
let head = CGPoint(x: size / 2, y: 600)
let R: CGFloat = 235
let pin = CGMutablePath()
// Tangent points so the point blends into the circle without a notch
let half = acos(R / (head.y - tip.y))
let a1 = 1.5 * .pi - half, a2 = 1.5 * .pi + half
pin.move(to: tip)
pin.addLine(to: CGPoint(x: head.x + R * cos(a1), y: head.y + R * sin(a1)))
pin.addArc(center: head, radius: R, startAngle: a1, endAngle: a2, clockwise: true)
pin.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: NSColor.black.withAlphaComponent(0.35).cgColor)
ctx.setFillColor(NSColor.white.cgColor)
ctx.addPath(pin)
ctx.fillPath()
ctx.restoreGState()

// Inner window of the pin showing the gradient, with three event dots (a cluster)
let hole: CGFloat = 150
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: head.x - hole, y: head.y - hole, width: hole * 2, height: hole * 2))
ctx.clip()
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
ctx.restoreGState()

let dots: [(CGFloat, CGFloat, CGFloat, NSColor)] = [
    (head.x - 48, head.y + 30, 44, NSColor(red: 1.0, green: 0.85, blue: 0.25, alpha: 1)),
    (head.x + 55, head.y + 45, 34, NSColor.white),
    (head.x + 20, head.y - 58, 38, NSColor(red: 0.55, green: 0.95, blue: 0.80, alpha: 1)),
]
for (x, y, r, c) in dots {
    ctx.setShadow(offset: .zero, blur: 18, color: c.withAlphaComponent(0.8).cgColor)
    ctx.setFillColor(c.cgColor)
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
