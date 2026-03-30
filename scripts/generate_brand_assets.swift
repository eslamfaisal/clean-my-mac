import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesURL = root.appending(path: "Resources", directoryHint: .isDirectory)
let iconsetURL = resourcesURL.appending(path: "AppIcon.iconset", directoryHint: .isDirectory)
let icnsURL = resourcesURL.appending(path: "AppIcon.icns")
let previewURL = resourcesURL.appending(path: "BrandPreview.png")

try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: icnsURL)

let iconSizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (dimension, fileName) in iconSizes {
    let image = makeLogoImage(size: CGFloat(dimension))
    let data = try pngData(from: image)
    try data.write(to: iconsetURL.appending(path: fileName), options: .atomic)
}

let preview = makeLogoImage(size: 1024, includeWordmark: true)
let previewData = try pngData(from: preview)
try previewData.write(to: previewURL, options: .atomic)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "BrandAssets", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
}

print("Generated:")
print("  \(icnsURL.path)")
print("  \(previewURL.path)")

private func makeLogoImage(size: CGFloat, includeWordmark: Bool = false) -> NSImage {
    let canvasSize = includeWordmark ? NSSize(width: size * 1.9, height: size) : NSSize(width: size, height: size)
    let image = NSImage(size: canvasSize)
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    let badgeRect = CGRect(x: 0, y: 0, width: size, height: size)
    drawBadge(in: badgeRect, context: ctx)

    if includeWordmark {
        let titleRect = CGRect(x: size * 1.02, y: size * 0.46, width: size * 0.8, height: size * 0.22)
        let subtitleRect = CGRect(x: size * 1.02, y: size * 0.30, width: size * 0.8, height: size * 0.14)

        let title = NSAttributedString(
            string: "CleanMyMac",
            attributes: [
                .font: NSFont.systemFont(ofSize: size * 0.18, weight: .black),
                .foregroundColor: NSColor.white,
            ]
        )
        title.draw(in: titleRect)

        let subtitleStyle = NSMutableParagraphStyle()
        subtitleStyle.alignment = .left
        let subtitle = NSAttributedString(
            string: "Developer Disk Cleanup Studio",
            attributes: [
                .font: NSFont.systemFont(ofSize: size * 0.08, weight: .semibold),
                .foregroundColor: NSColor(calibratedRed: 0.48, green: 0.78, blue: 1.0, alpha: 0.88),
                .paragraphStyle: subtitleStyle,
                .kern: size * 0.015,
            ]
        )
        subtitle.draw(in: subtitleRect)
    }

    image.unlockFocus()
    return image
}

private func drawBadge(in rect: CGRect, context: CGContext) {
    context.saveGState()

    let shadow = NSShadow()
    shadow.shadowBlurRadius = rect.width * 0.08
    shadow.shadowOffset = NSSize(width: 0, height: -rect.height * 0.02)
    shadow.shadowColor = NSColor(calibratedRed: 0.16, green: 0.58, blue: 1.0, alpha: 0.28)
    shadow.set()

    let basePath = NSBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08))
    let baseGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.19, green: 0.25, blue: 0.38, alpha: 1.0),
        NSColor(calibratedRed: 0.07, green: 0.10, blue: 0.16, alpha: 1.0),
        NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.05, alpha: 1.0),
    ])!
    baseGradient.draw(in: basePath, relativeCenterPosition: NSZeroPoint)

    context.restoreGState()

    let ringPath = NSBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08))
    ringPath.lineWidth = rect.width * 0.08
    NSColor(calibratedRed: 0.30, green: 0.88, blue: 0.79, alpha: 0.95).setStroke()
    ringPath.stroke()

    let ringOverlay = NSBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.16, dy: rect.height * 0.16))
    NSColor.white.withAlphaComponent(0.08).setStroke()
    ringOverlay.lineWidth = max(1, rect.width * 0.012)
    ringOverlay.stroke()

    let driveRect = CGRect(
        x: rect.midX - rect.width * 0.28,
        y: rect.midY - rect.height * 0.18,
        width: rect.width * 0.56,
        height: rect.height * 0.66
    )
    let drivePath = NSBezierPath(roundedRect: driveRect, xRadius: rect.width * 0.10, yRadius: rect.width * 0.10)
    NSColor.white.withAlphaComponent(0.12).setFill()
    drivePath.fill()
    NSColor.white.withAlphaComponent(0.15).setStroke()
    drivePath.lineWidth = max(1, rect.width * 0.015)
    drivePath.stroke()

    let activityDot = NSBezierPath(ovalIn: CGRect(
        x: rect.midX - rect.width * 0.035,
        y: driveRect.maxY - rect.height * 0.17,
        width: rect.width * 0.07,
        height: rect.width * 0.07
    ))
    NSColor(calibratedRed: 0.27, green: 0.66, blue: 1.0, alpha: 0.92).setFill()
    activityDot.fill()

    let slot1 = NSBezierPath(roundedRect: CGRect(
        x: rect.midX - rect.width * 0.12,
        y: rect.midY + rect.height * 0.02,
        width: rect.width * 0.24,
        height: rect.height * 0.045
    ), xRadius: rect.width * 0.02, yRadius: rect.width * 0.02)
    NSColor.white.withAlphaComponent(0.10).setFill()
    slot1.fill()

    let slot2 = NSBezierPath(roundedRect: CGRect(
        x: rect.midX - rect.width * 0.09,
        y: rect.midY - rect.height * 0.07,
        width: rect.width * 0.18,
        height: rect.height * 0.038
    ), xRadius: rect.width * 0.02, yRadius: rect.width * 0.02)
    NSColor.white.withAlphaComponent(0.08).setFill()
    slot2.fill()

    let sweep = NSBezierPath()
    sweep.move(to: CGPoint(x: rect.minX + rect.width * 0.27, y: rect.midY - rect.height * 0.02))
    sweep.line(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.30))
    sweep.curve(
        to: CGPoint(x: rect.maxX - rect.width * 0.24, y: rect.maxY - rect.height * 0.24),
        controlPoint1: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.18),
        controlPoint2: CGPoint(x: rect.maxX - rect.width * 0.38, y: rect.maxY - rect.height * 0.36)
    )
    sweep.lineWidth = rect.width * 0.12
    sweep.lineCapStyle = .round
    sweep.lineJoinStyle = .round
    NSColor(calibratedRed: 0.42, green: 0.96, blue: 0.82, alpha: 1.0).setStroke()
    sweep.stroke()

    drawSparkle(center: CGPoint(x: rect.maxX - rect.width * 0.28, y: rect.maxY - rect.height * 0.30), radius: rect.width * 0.08)
    drawSparkle(center: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.maxY - rect.height * 0.40), radius: rect.width * 0.04)
}

private func drawSparkle(center: CGPoint, radius: CGFloat) {
    let sparkle = NSBezierPath()
    sparkle.move(to: CGPoint(x: center.x, y: center.y + radius))
    sparkle.line(to: CGPoint(x: center.x + radius * 0.34, y: center.y + radius * 0.34))
    sparkle.line(to: CGPoint(x: center.x + radius, y: center.y))
    sparkle.line(to: CGPoint(x: center.x + radius * 0.34, y: center.y - radius * 0.34))
    sparkle.line(to: CGPoint(x: center.x, y: center.y - radius))
    sparkle.line(to: CGPoint(x: center.x - radius * 0.34, y: center.y - radius * 0.34))
    sparkle.line(to: CGPoint(x: center.x - radius, y: center.y))
    sparkle.line(to: CGPoint(x: center.x - radius * 0.34, y: center.y + radius * 0.34))
    sparkle.close()
    NSColor.white.withAlphaComponent(0.92).setFill()
    sparkle.fill()
}

private func pngData(from image: NSImage) throws -> Data {
    guard
        let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let data = rep.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "BrandAssets", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
    }
    return data
}
