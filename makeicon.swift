// makeicon — 生成「紫微斗数」应用图标
//
// 设计意图：一张命盘。四乘四的金线格子里，中宫浮着一个「紫」字。
// 深墨底 + 赭金线，一眼能认出是排盘软件。
//
// 编译运行：
//   swiftc -O makeicon.swift -o makeicon && ./makeicon && iconutil -c icns Ziwei.iconset -o Ziwei.icns

import AppKit
import CoreGraphics
import Foundation

let S: CGFloat = 1024
let outDir = "Ziwei.iconset"

let INSET: CGFloat = 100
let SIDE: CGFloat = 824
let RADIUS: CGFloat = 185

func render(_ px: Int) -> Data {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: px, height: px,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("no ctx")
    }
    let k = CGFloat(px) / S
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: k, y: k)

    let body = CGRect(x: INSET, y: INSET, width: SIDE, height: SIDE)
    let shape = CGPath(roundedRect: body, cornerWidth: RADIUS, cornerHeight: RADIUS, transform: nil)

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    // 底：中心暖褐，向外沉到近黑
    let bg = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0.145, green: 0.113, blue: 0.088, alpha: 1),
        CGColor(red: 0.078, green: 0.062, blue: 0.050, alpha: 1),
        CGColor(red: 0.030, green: 0.026, blue: 0.024, alpha: 1),
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawRadialGradient(bg,
                           startCenter: CGPoint(x: 512, y: 512), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 512), endRadius: 620,
                           options: [.drawsAfterEndLocation])

    let x0 = INSET, y0 = INSET
    let cell = SIDE / 4

    // 中宫：用渐变而不是纯色块，否则边界会硬得像贴上去的
    let centerRect = CGRect(x: x0 + cell, y: y0 + cell, width: cell * 2, height: cell * 2)
    let centerGrad = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0.205, green: 0.160, blue: 0.115, alpha: 1),
        CGColor(red: 0.140, green: 0.110, blue: 0.082, alpha: 1),
        CGColor(red: 0.090, green: 0.072, blue: 0.058, alpha: 1),
    ] as CFArray, locations: [0, 0.6, 1])!
    ctx.saveGState()
    ctx.addRect(centerRect)
    ctx.clip()
    ctx.drawRadialGradient(centerGrad,
                           startCenter: CGPoint(x: 512, y: 512), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 512), endRadius: cell * 1.45,
                           options: [])
    ctx.restoreGState()

    // 中宫辉光
    let glow = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0.86, green: 0.68, blue: 0.38, alpha: 0.30),
        CGColor(red: 0.86, green: 0.68, blue: 0.38, alpha: 0.06),
        CGColor(red: 0.86, green: 0.68, blue: 0.38, alpha: 0),
    ] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawRadialGradient(glow,
                           startCenter: CGPoint(x: 512, y: 512), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 512), endRadius: cell * 1.5,
                           options: [])

    // 格线
    ctx.setStrokeColor(CGColor(red: 0.80, green: 0.64, blue: 0.36, alpha: 0.42))
    ctx.setLineWidth(4)
    for i in 1...3 {
        let p = x0 + cell * CGFloat(i)
        ctx.move(to: CGPoint(x: p, y: y0)); ctx.addLine(to: CGPoint(x: p, y: y0 + SIDE))
        ctx.move(to: CGPoint(x: x0, y: p)); ctx.addLine(to: CGPoint(x: x0 + SIDE, y: p))
    }
    ctx.strokePath()

    // 外框
    ctx.setStrokeColor(CGColor(red: 0.80, green: 0.64, blue: 0.36, alpha: 0.75))
    ctx.setLineWidth(7)
    ctx.stroke(body.insetBy(dx: 3.5, dy: 3.5))

    // 中宫内的「紫」
    let font = NSFont(name: "STSongti-SC-Bold", size: 268)
        ?? NSFont(name: "Songti SC Bold", size: 268)
        ?? NSFont.systemFont(ofSize: 268, weight: .bold)

    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(red: 0.88, green: 0.72, blue: 0.42, alpha: 1.0),
    ]
    let str = NSAttributedString(string: "紫", attributes: attrs)
    let size = str.size()
    let origin = CGPoint(x: 512 - size.width / 2, y: 512 - size.height / 2 + size.height * 0.02)

    let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ns
    str.draw(at: origin)
    NSGraphicsContext.restoreGraphicsState()

    ctx.restoreGState()

    guard let img = ctx.makeImage() else { fatalError("no image") }
    let rep = NSBitmapImageRep(cgImage: img)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
    return data
}

let fm = FileManager.default
try? fm.removeItem(atPath: outDir)
try! fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

for s in [16, 32, 64, 128, 256, 512, 1024] {
    try! render(s).write(to: URL(fileURLWithPath: "\(outDir)/icon_\(s)x\(s).png"))
    if s <= 512 {
        try! render(s * 2).write(to: URL(fileURLWithPath: "\(outDir)/icon_\(s)x\(s)@2x.png"))
    }
    print("  icon_\(s)x\(s).png")
}
print("完成：\(outDir)")
