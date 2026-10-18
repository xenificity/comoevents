// Renders the CoMo Events app icon at 1024x1024.
// Style: glossy 3D. Black glass map pin with a yellow glass lens, on lit yellow.
// Usage: swift Design/make-icon.swift Design/icon-1024.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let cs = CGColorSpaceCreateDeviceRGB()
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    NSColor(red: r, green: g, blue: b, alpha: a).cgColor
}
func gradient(_ colors: [CGColor], _ locs: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locs)!
}

let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no context") }

// ---------- Background: yellow with a light source top-left and darker corners
ctx.drawRadialGradient(gradient([rgb(1.00, 0.95, 0.35), rgb(1.00, 0.86, 0.00), rgb(0.93, 0.66, 0.00)], [0, 0.55, 1]),
                       startCenter: CGPoint(x: 330, y: 760), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 512), endRadius: 760, options: [.drawsAfterEndLocation])
// Glass sheen across the top half
ctx.saveGState()
let sheen = CGMutablePath()
sheen.move(to: CGPoint(x: 0, y: size))
sheen.addLine(to: CGPoint(x: size, y: size))
sheen.addLine(to: CGPoint(x: size, y: 600))
sheen.addQuadCurve(to: CGPoint(x: 0, y: 520), control: CGPoint(x: 512, y: 420))
sheen.closeSubpath()
ctx.addPath(sheen); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(1, 1, 1, 0.20), rgb(1, 1, 1, 0.03)], [0, 1]),
                       start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 480), options: [])
ctx.restoreGState()

// ---------- Geometry
let tip = CGPoint(x: 512, y: 165)
let head = CGPoint(x: 512, y: 600)
let R: CGFloat = 262
let half = acos(R / (head.y - tip.y))
func pinPath(inset: CGFloat = 0) -> CGPath {
    let r = R - inset
    let t = CGPoint(x: tip.x, y: tip.y + inset * 1.6)
    let h = acos(r / (head.y - t.y))
    let p = CGMutablePath()
    p.move(to: t)
    p.addLine(to: CGPoint(x: head.x + r * cos(1.5 * .pi - h), y: head.y + r * sin(1.5 * .pi - h)))
    p.addArc(center: head, radius: r, startAngle: 1.5 * .pi - h, endAngle: 1.5 * .pi + h, clockwise: true)
    p.closeSubpath()
    return p
}
let pin = pinPath()

// ---------- Ground shadow + contact glow
ctx.saveGState()
ctx.setFillColor(rgb(0, 0, 0, 0.32))
ctx.setShadow(offset: .zero, blur: 50, color: rgb(0, 0, 0, 0.5))
ctx.fillEllipse(in: CGRect(x: 512 - 230, y: 95, width: 460, height: 110))
ctx.restoreGState()
ctx.saveGState()
ctx.setFillColor(rgb(0, 0, 0, 0.22))
ctx.setShadow(offset: .zero, blur: 22, color: rgb(0, 0, 0, 0.6))
ctx.fillEllipse(in: CGRect(x: 512 - 110, y: 128, width: 220, height: 50))
ctx.restoreGState()

// ---------- Pin body: dark glass with a drop shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 48, color: rgb(0, 0, 0, 0.45))
ctx.setFillColor(rgb(0.08, 0.08, 0.09))
ctx.addPath(pin); ctx.fillPath()
ctx.restoreGState()

// Body shading: lighter top-left, deep bottom
ctx.saveGState()
ctx.addPath(pin); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0.36, 0.36, 0.40), rgb(0.15, 0.15, 0.17), rgb(0.04, 0.04, 0.05)], [0, 0.45, 1]),
                       start: CGPoint(x: 300, y: 870), end: CGPoint(x: 650, y: 170), options: [])
// Rim light along the top edge
ctx.drawRadialGradient(gradient([rgb(1, 1, 1, 0.55), rgb(1, 1, 1, 0.0)], [0, 1]),
                       startCenter: CGPoint(x: 400, y: 790), startRadius: 0,
                       endCenter: CGPoint(x: 400, y: 790), endRadius: 260, options: [])
// Broad specular reflection (glass window shape)
let spec = CGMutablePath()
spec.addEllipse(in: CGRect(x: 320, y: 640, width: 250, height: 190))
ctx.addPath(spec); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(1, 1, 1, 0.50), rgb(1, 1, 1, 0.05)], [0, 1]),
                       start: CGPoint(x: 0, y: 830), end: CGPoint(x: 0, y: 640), options: [])
ctx.restoreGState()

// Bottom bounce light on the point (yellow reflected from the ground)
ctx.saveGState()
ctx.addPath(pin); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(1.0, 0.85, 0.1, 0.28), rgb(1.0, 0.85, 0.1, 0.0)], [0, 1]),
                       start: CGPoint(x: 0, y: 165), end: CGPoint(x: 0, y: 260), options: [])
ctx.restoreGState()

// Thin bright edge (glass rim)
ctx.saveGState()
ctx.addPath(pin); ctx.clip()
ctx.setLineWidth(10)
ctx.setStrokeColor(rgb(1, 1, 1, 0.22))
ctx.addPath(pinPath(inset: 4)); ctx.strokePath()
ctx.restoreGState()

// ---------- Yellow glass lens in the head
let lensR: CGFloat = 150
let lens = CGRect(x: head.x - lensR, y: head.y - lensR, width: lensR * 2, height: lensR * 2)
// Recess shadow (inner shadow look): dark ring behind the lens
ctx.saveGState()
ctx.setFillColor(rgb(0, 0, 0, 0.6))
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: rgb(0, 0, 0, 0.8))
ctx.fillEllipse(in: lens.insetBy(dx: -8, dy: -8))
ctx.restoreGState()
// Lens body: radial yellow sphere, bright at upper-left
ctx.saveGState()
ctx.addEllipse(in: lens); ctx.clip()
ctx.drawRadialGradient(gradient([rgb(1.0, 0.98, 0.55), rgb(1.0, 0.85, 0.0), rgb(0.85, 0.55, 0.0)], [0, 0.55, 1]),
                       startCenter: CGPoint(x: head.x - 55, y: head.y + 60), startRadius: 0,
                       endCenter: head, endRadius: lensR * 1.15, options: [.drawsAfterEndLocation])
// Inner shadow at the top rim of the lens
ctx.drawLinearGradient(gradient([rgb(0, 0, 0, 0.35), rgb(0, 0, 0, 0.0)], [0, 1]),
                       start: CGPoint(x: 0, y: head.y + lensR), end: CGPoint(x: 0, y: head.y + lensR * 0.3), options: [])
// Black event dot in the lens
ctx.setFillColor(rgb(0.05, 0.05, 0.06))
ctx.fillEllipse(in: CGRect(x: head.x - 48, y: head.y - 48, width: 96, height: 96))
ctx.drawRadialGradient(gradient([rgb(1, 1, 1, 0.9), rgb(1, 1, 1, 0.0)], [0, 1]),
                       startCenter: CGPoint(x: head.x - 20, y: head.y + 22), startRadius: 0,
                       endCenter: CGPoint(x: head.x - 20, y: head.y + 22), endRadius: 30, options: [])
// Specular highlight on the lens glass
let hl = CGRect(x: head.x - 105, y: head.y + 28, width: 150, height: 92)
ctx.addEllipse(in: hl); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(1, 1, 1, 0.85), rgb(1, 1, 1, 0.05)], [0, 1]),
                       start: CGPoint(x: 0, y: hl.maxY), end: CGPoint(x: 0, y: hl.minY), options: [])
ctx.restoreGState()
// Lens rim
ctx.setLineWidth(5)
ctx.setStrokeColor(rgb(1, 1, 1, 0.35))
ctx.strokeEllipse(in: lens.insetBy(dx: 2, dy: 2))

// ---------- Small floating event sparks around the pin (depth)
for (x, y, r, a) in [(215.0, 700.0, 22.0, 0.9), (800.0, 640.0, 16.0, 0.8), (760.0, 300.0, 12.0, 0.7), (250.0, 360.0, 10.0, 0.6)] {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: rgb(0, 0, 0, 0.35))
    ctx.setFillColor(rgb(0.08, 0.08, 0.09, a))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    ctx.restoreGState()
    ctx.setFillColor(rgb(1, 1, 1, 0.7))
    ctx.fillEllipse(in: CGRect(x: x - r * 0.45, y: y + r * 0.1, width: r * 0.6, height: r * 0.6))
}

img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
