// Renders the CoMo Events app icon at 1024x1024.
// Style: flat, Snapchat-like. Solid yellow, one white map-pin silhouette with a thick black outline.
// Usage: swift Design/make-icon.swift Design/icon-1024.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let yellow = NSColor(red: 1.00, green: 0.99, blue: 0.00, alpha: 1)   // #FFFC00
let black = NSColor.black
let white = NSColor.white

let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no context") }

ctx.setFillColor(yellow.cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Pin silhouette: circle head + point, tangents so the sides are straight into the circle
let tip = CGPoint(x: size / 2, y: 150)
let head = CGPoint(x: size / 2, y: 585)
let R: CGFloat = 268
let half = acos(R / (head.y - tip.y))
let pin = CGMutablePath()
pin.move(to: tip)
pin.addLine(to: CGPoint(x: head.x + R * cos(1.5 * .pi - half), y: head.y + R * sin(1.5 * .pi - half)))
pin.addArc(center: head, radius: R, startAngle: 1.5 * .pi - half, endAngle: 1.5 * .pi + half, clockwise: true)
pin.closeSubpath()

let stroke: CGFloat = 46
ctx.setLineJoin(.round)
ctx.setLineWidth(stroke)
ctx.setStrokeColor(black.cgColor)
ctx.setFillColor(white.cgColor)
ctx.addPath(pin); ctx.drawPath(using: .fillStroke)

// Black dot in the head (classic pin), with a tiny white highlight for life
let dot: CGFloat = 118
ctx.setFillColor(black.cgColor)
ctx.fillEllipse(in: CGRect(x: head.x - dot, y: head.y - dot, width: dot * 2, height: dot * 2))
ctx.setFillColor(white.cgColor)
ctx.fillEllipse(in: CGRect(x: head.x - 62, y: head.y + 18, width: 46, height: 46))

// Ground mark under the tip, same outline weight, keeps the pin from floating
ctx.setStrokeColor(black.cgColor)
ctx.setLineWidth(34)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: size / 2 - 120, y: 96)); ctx.addLine(to: CGPoint(x: size / 2 + 120, y: 96))
ctx.strokePath()

img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
