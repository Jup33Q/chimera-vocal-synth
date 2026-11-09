import AppKit
import Foundation

struct IconSpec {
    let name: String
    let folder: String
    let lines: [String]
    let accent: NSColor
}

func rgb(_ red: Double, _ green: Double, _ blue: Double) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
}

let specs = [
    IconSpec(name: "Chimera", folder: "", lines: ["kaɪ", "ˈmɪrə"], accent: rgb(0.12, 0.58, 1)),
    IconSpec(name: "Play", folder: "Play", lines: ["pleɪ"], accent: rgb(0.22, 1, 0.58)),
    IconSpec(name: "Speak", folder: "Speak", lines: ["spiːk"], accent: rgb(0.12, 0.58, 1)),
    IconSpec(name: "Sing", folder: "Sing", lines: ["sɪŋ"], accent: rgb(1, 0.32, 0.68)),
    IconSpec(name: "Beatbox", folder: "Beatbox", lines: ["biːt", "bɑks"], accent: rgb(1, 0.56, 0.12)),
    IconSpec(name: "Head", folder: "Head", lines: ["hɛd"], accent: rgb(0.12, 0.58, 1)),
    IconSpec(name: "Gender Age", folder: "GenderAge", lines: ["eɪdʒ", "♂ ♀"], accent: rgb(1, 0.32, 0.68)),
    IconSpec(name: "Viewer", folder: "Viewer", lines: ["vjuːə"], accent: rgb(0.85, 0.92, 1))
]

func bitmap(width: Int, height: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
}

func withContext<T>(_ rep: NSBitmapImageRep, draw: () -> T) -> T {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let result = draw()
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return result
}

func attributedText(_ text: String, fontSize: Double, color: NSColor, genderSymbols: Bool) -> NSAttributedString {
    let font = NSFont(name: "Helvetica Neue", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: .light)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .kern: fontSize * 0.025
    ]
    let result = NSMutableAttributedString(string: text, attributes: attributes)
    if genderSymbols {
        result.addAttribute(.foregroundColor, value: rgb(0.12, 0.58, 1), range: NSRange(location: 0, length: 1))
        result.addAttribute(.foregroundColor, value: rgb(1, 0.32, 0.68), range: NSRange(location: 2, length: 1))
    }
    return result
}

func drawText(_ text: String, centerY: Double, size: Double, scale: Double, color: NSColor, genderSymbols: Bool = false) {
    var fontSize = size * scale
    var value = attributedText(text, fontSize: fontSize, color: color, genderSymbols: genderSymbols)
    while value.size().width > size * 0.82 {
        fontSize *= 0.92
        value = attributedText(text, fontSize: fontSize, color: color, genderSymbols: genderSymbols)
    }
    let bounds = value.size()
    value.draw(at: NSPoint(x: (size - bounds.width) / 2, y: centerY - bounds.height / 2))
}

func drawIcon(_ spec: IconSpec, size: Double) {
    let outer = NSRect(x: size * 0.025, y: size * 0.025, width: size * 0.95, height: size * 0.95)
    let shape = NSBezierPath(roundedRect: outer, xRadius: size * 0.22, yRadius: size * 0.22)
    NSGradient(colors: [rgb(0.015, 0.032, 0.052), rgb(0.001, 0.003, 0.007)])?.draw(in: shape, angle: 90)
    spec.accent.withAlphaComponent(0.85).setStroke()
    shape.lineWidth = max(1.5, size * 0.012)
    shape.stroke()

    NSColor(calibratedWhite: 0.2, alpha: 0.16).setStroke()
    for index in 1...3 {
        let x = size * (0.18 + Double(index) * 0.16)
        let line = NSBezierPath()
        line.move(to: NSPoint(x: x, y: size * 0.17))
        line.line(to: NSPoint(x: x, y: size * 0.83))
        line.lineWidth = max(0.5, size * 0.002)
        line.stroke()
    }

    if spec.lines.count == 1 {
        drawText(spec.lines[0], centerY: size * 0.56, size: size, scale: 0.29, color: PhosphorWhite)
    } else {
        for (index, line) in spec.lines.enumerated() {
            let isGender = spec.name == "Gender Age" && index == 1
            drawText(
                line,
                centerY: size * (index == 0 ? 0.66 : 0.37),
                size: size,
                scale: isGender ? 0.23 : 0.22,
                color: isGender ? spec.accent : PhosphorWhite,
                genderSymbols: isGender
            )
        }
    }

    let heights = [0.018, 0.036, 0.06, 0.028, 0.052, 0.034, 0.018]
    spec.accent.setFill()
    for (index, height) in heights.enumerated() {
        let x = size * 0.34 + Double(index) * size * 0.046
        let bar = NSRect(x: x, y: size * 0.16, width: max(1, size * 0.012), height: size * height)
        NSBezierPath(roundedRect: bar, xRadius: size * 0.006, yRadius: size * 0.006).fill()
    }
}

let PhosphorWhite = rgb(0.85, 0.92, 1)
let native = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let sizes = [(16, 1, 16), (16, 2, 32), (32, 1, 32), (32, 2, 64), (128, 1, 128), (128, 2, 256), (256, 1, 256), (256, 2, 512), (512, 1, 512), (512, 2, 1024)]

for spec in specs {
    let catalog = native
        .appendingPathComponent("ChimeraMac")
        .appendingPathComponent(spec.folder.isEmpty ? "" : "Apps/\(spec.folder)")
        .appendingPathComponent("Assets.xcassets")
    let set = catalog.appendingPathComponent("AppIcon.appiconset")
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    var images: [[String: Any]] = []
    for (points, scale, pixels) in sizes {
        let rep = bitmap(width: pixels, height: pixels)
        withContext(rep) { drawIcon(spec, size: Double(pixels)) }
        let filename = "icon-\(points)-\(scale)x.png"
        let data = rep.representation(using: .png, properties: [:])!
        try data.write(to: set.appendingPathComponent(filename))
        images.append([
            "idiom": "mac",
            "size": "\(points)x\(points)",
            "scale": "\(scale)x",
            "filename": filename
        ])
    }
    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: set.appendingPathComponent("Contents.json"))
    let catalogContents = ["info": ["author": "xcode", "version": 1]]
    try JSONSerialization.data(withJSONObject: catalogContents, options: [.prettyPrinted, .sortedKeys]).write(to: catalog.appendingPathComponent("Contents.json"))
    print("Generated \(spec.name): \(set.path)")
}

let preview = bitmap(width: 1024, height: 512)
withContext(preview) {
    rgb(0.008, 0.012, 0.02).setFill()
    NSRect(x: 0, y: 0, width: 1024, height: 512).fill()
    for (index, spec) in specs.enumerated() {
        let column = index % 4
        let row = 1 - index / 4
        let x = Double(column) * 256
        let y = Double(row) * 256
        let rep = bitmap(width: 256, height: 256)
        withContext(rep) { drawIcon(spec, size: 256) }
        let data = rep.representation(using: .png, properties: [:])!
        let image = NSImage(data: data)!
        image.draw(in: NSRect(x: x + 44, y: y + 48, width: 168, height: 168))
        let label = NSAttributedString(string: spec.name.uppercased(), attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: spec.accent
        ])
        label.draw(at: NSPoint(x: x + (256 - label.size().width) / 2, y: y + 22))
    }
}
let previewURL = native.appendingPathComponent("build/ChimeraIcons-preview.png")
try FileManager.default.createDirectory(at: previewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try preview.representation(using: .png, properties: [:])!.write(to: previewURL)
print("Preview: \(previewURL.path)")
