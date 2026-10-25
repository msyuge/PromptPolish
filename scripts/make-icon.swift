// Рисует иконку приложения и раскладывает её по размерам в Assets.xcassets/AppIcon.appiconset.
// Запуск: swift scripts/make-icon.swift
import AppKit

let iconSet = URL(fileURLWithPath: "PromptPolish/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

/// Иконка по сетке macOS: скруглённый квадрат 824×824 на холсте 1024×1024, градиент и символ строки меню.
func drawIcon(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: 1024, height: 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.42, green: 0.30, blue: 0.95, alpha: 1),
        NSColor(calibratedRed: 0.16, green: 0.50, blue: 0.98, alpha: 1),
    ])!
    gradient.draw(in: shape, angle: -55)

    let configuration = NSImage.SymbolConfiguration(pointSize: 460, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) {
        let size = symbol.size
        symbol.draw(in: NSRect(x: 512 - size.width / 2, y: 512 - size.height / 2, width: size.width, height: size.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let entries: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

var images: [[String: String]] = []
for entry in entries {
    let name = "icon_\(entry.points)x\(entry.points)\(entry.scale == 2 ? "@2x" : "").png"
    try drawIcon(pixels: entry.points * entry.scale).write(to: iconSet.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(entry.points)x\(entry.points)", "scale": "\(entry.scale)x", "filename": name])
}

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: iconSet.appendingPathComponent("Contents.json"))
let catalog = ["info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted])
    .write(to: iconSet.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("Иконка записана в \(iconSet.path)")
