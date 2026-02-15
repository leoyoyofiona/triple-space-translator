import AppKit

let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let fm = FileManager.default

let iconsetDir = outputDir.appendingPathComponent("TripleSpaceTranslator.iconset", isDirectory: true)
let masterPNG = outputDir.appendingPathComponent("TripleSpaceTranslator-1024.png")
let icnsPath = outputDir.appendingPathComponent("TripleSpaceTranslator.icns")

try? fm.removeItem(at: iconsetDir)
try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: size, height: size)
let corner: CGFloat = 220
let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: 12, dy: 12), xRadius: corner, yRadius: corner)

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.08, green: 0.53, blue: 0.95, alpha: 1.0),
    NSColor(calibratedRed: 0.10, green: 0.78, blue: 0.70, alpha: 1.0)
])!
gradient.draw(in: bgPath, angle: -35)

NSGraphicsContext.current?.saveGraphicsState()
bgPath.addClip()

// subtle grid arcs
NSColor.white.withAlphaComponent(0.14).setStroke()
for i in 0..<8 {
    let inset = CGFloat(40 + i * 65)
    let p = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), xRadius: 140, yRadius: 140)
    p.lineWidth = 2
    p.stroke()
}

// diagonal glow band
let glowRect = NSRect(x: -120, y: 420, width: 1320, height: 210)
let glow = NSBezierPath(roundedRect: glowRect, xRadius: 100, yRadius: 100)
NSColor.white.withAlphaComponent(0.20).setFill()
glow.fill()

NSGraphicsContext.current?.restoreGraphicsState()

// central label "中 → EN"
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center

let title = NSAttributedString(
    string: "中  →  EN",
    attributes: [
        .font: NSFont.systemFont(ofSize: 184, weight: .black),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph,
        .kern: 1.5
    ]
)
let titleRect = NSRect(x: 0, y: 430, width: size, height: 200)
title.draw(in: titleRect)

// triple-space dots
let dotColor = NSColor.white.withAlphaComponent(0.95)
dotColor.setFill()
let dotY: CGFloat = 260
let radius: CGFloat = 28
let startX: CGFloat = 425
let gap: CGFloat = 90
for i in 0..<3 {
    let x = startX + CGFloat(i) * gap
    let dot = NSBezierPath(ovalIn: NSRect(x: x, y: dotY, width: radius * 2, height: radius * 2))
    dot.fill()
}

// bottom caption
let caption = NSAttributedString(
    string: "TRIPLE SPACE TRANSLATOR",
    attributes: [
        .font: NSFont.systemFont(ofSize: 40, weight: .semibold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.9),
        .paragraphStyle: paragraph,
        .kern: 3
    ]
)
caption.draw(in: NSRect(x: 0, y: 145, width: size, height: 60))

image.unlockFocus()

func pngData(from image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
}

guard let masterData = pngData(from: image) else {
    fputs("failed to render icon png\n", stderr)
    exit(1)
}
try masterData.write(to: masterPNG)

let fileMap: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (px, name) in fileMap {
    let targetSize = NSSize(width: px, height: px)
    let scaled = NSImage(size: targetSize)
    scaled.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1.0)
    scaled.unlockFocus()

    guard let data = pngData(from: scaled) else {
        fputs("failed create \(name)\n", stderr)
        exit(1)
    }
    try data.write(to: iconsetDir.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsPath.path]
try process.run()
process.waitUntilExit()
if process.terminationStatus != 0 {
    fputs("iconutil failed\n", stderr)
    exit(1)
}

print("Generated:")
print("- \(masterPNG.path)")
print("- \(icnsPath.path)")
print("- \(iconsetDir.path)")
