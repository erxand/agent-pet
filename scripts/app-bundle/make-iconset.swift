// Usage: swift scripts/app-bundle/make-iconset.swift --art SQUARE.png --output AppIcon.iconset
//        [--small-crop X,Y,SIZE]
//
// Makes the ten PNGs of a macOS .iconset from one square image. Each icon is Apple's app icon grid:
// the art clipped to the continuous corner rounded rectangle of an 824 px body centred on a
// 1024 px canvas, a transparent outside and a soft drop shadow, which is the shape macOS shows as
// it is instead of placing it inside a grey frame. The large sizes are made by halving the 1024 px
// icon step by step, so every step filters well. --small-crop names a square of the art, in its
// own pixels from the top left, that the 16 and 32 px icons show instead of the whole art, so a
// busy picture still reads at that size. Those small icons also fill more of the canvas, the way
// Apple's own do at that size.
import AppKit
import Foundation

let canvasSize = 1024
let bodySize: CGFloat = 824
// macOS draws a 16 or 32 px icon whose body is the 824 px grid inside a grey frame, at 1x; a
// 900 px body is shown as it is (measured on macOS 27).
let smallBodySize: CGFloat = 900
let cornerRadiusPerBody: CGFloat = 185.4 / 824
let shadowOffset = CGSize(width: 0, height: -10)
let shadowBlur: CGFloat = 20
let shadowOpacity: CGFloat = 0.3
let smallSizeLimit = 32
let iconSizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

// Apple's continuous corner: each corner is two cubic curves joined by a short one, and the
// straight edges start 1.528665 radii from the corner instead of 1.
func continuousRoundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    let r = radius
    path.move(to: point(minX + 1.52866483 * r, maxY))
    path.addLine(to: point(maxX - 1.52866471 * r, maxY))
    path.addCurve(to: point(maxX - 0.63149399 * r, maxY - 0.07491100 * r),
                  control1: point(maxX - 1.08849323 * r, maxY), control2: point(maxX - 0.86840689 * r, maxY - 0.02065986 * r))
    path.addCurve(to: point(maxX - 0.07491100 * r, maxY - 0.63149399 * r),
                  control1: point(maxX - 0.37282392 * r, maxY - 0.16906001 * r), control2: point(maxX - 0.16906001 * r, maxY - 0.37282392 * r))
    path.addCurve(to: point(maxX, maxY - 1.52866471 * r),
                  control1: point(maxX - 0.02065986 * r, maxY - 0.86840689 * r), control2: point(maxX, maxY - 1.08849323 * r))
    path.addLine(to: point(maxX, minY + 1.52866483 * r))
    path.addCurve(to: point(maxX - 0.07491100 * r, minY + 0.63149399 * r),
                  control1: point(maxX, minY + 1.08849323 * r), control2: point(maxX - 0.02065986 * r, minY + 0.86840689 * r))
    path.addCurve(to: point(maxX - 0.63149399 * r, minY + 0.07491100 * r),
                  control1: point(maxX - 0.16906001 * r, minY + 0.37282392 * r), control2: point(maxX - 0.37282392 * r, minY + 0.16906001 * r))
    path.addCurve(to: point(maxX - 1.52866471 * r, minY),
                  control1: point(maxX - 0.86840689 * r, minY + 0.02065986 * r), control2: point(maxX - 1.08849323 * r, minY))
    path.addLine(to: point(minX + 1.52866483 * r, minY))
    path.addCurve(to: point(minX + 0.63149399 * r, minY + 0.07491100 * r),
                  control1: point(minX + 1.08849323 * r, minY), control2: point(minX + 0.86840689 * r, minY + 0.02065986 * r))
    path.addCurve(to: point(minX + 0.07491100 * r, minY + 0.63149399 * r),
                  control1: point(minX + 0.37282392 * r, minY + 0.16906001 * r), control2: point(minX + 0.16906001 * r, minY + 0.37282392 * r))
    path.addCurve(to: point(minX, minY + 1.52866483 * r),
                  control1: point(minX + 0.02065986 * r, minY + 0.86840689 * r), control2: point(minX, minY + 1.08849323 * r))
    path.addLine(to: point(minX, maxY - 1.52866471 * r))
    path.addCurve(to: point(minX + 0.07491100 * r, maxY - 0.63149399 * r),
                  control1: point(minX, maxY - 1.08849323 * r), control2: point(minX + 0.02065986 * r, maxY - 0.86840689 * r))
    path.addCurve(to: point(minX + 0.63149399 * r, maxY - 0.07491100 * r),
                  control1: point(minX + 0.16906001 * r, maxY - 0.37282392 * r), control2: point(minX + 0.37282392 * r, maxY - 0.16906001 * r))
    path.addCurve(to: point(minX + 1.52866483 * r, maxY),
                  control1: point(minX + 0.86840689 * r, maxY - 0.02065986 * r), control2: point(minX + 1.08849323 * r, maxY))
    path.closeSubpath()
    return path
}

func makeContext(pixels: Int) -> CGContext {
    guard let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fail("cannot make a \(pixels) px bitmap") }
    context.interpolationQuality = .high
    return context
}

func icon(from art: CGImage, body size: CGFloat) -> CGImage {
    let context = makeContext(pixels: canvasSize)
    let inset = (CGFloat(canvasSize) - size) / 2
    let body = CGRect(x: inset, y: inset, width: size, height: size)
    let shape = continuousRoundedRect(body, radius: size * cornerRadiusPerBody)
    context.saveGState()
    context.setShadow(offset: shadowOffset, blur: shadowBlur, color: CGColor(gray: 0, alpha: shadowOpacity))
    context.addPath(shape)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.draw(art, in: body)
    context.restoreGState()
    guard let image = context.makeImage() else { fail("cannot draw the icon") }
    return image
}

func halved(_ image: CGImage) -> CGImage {
    let context = makeContext(pixels: image.width / 2)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width / 2, height: image.height / 2))
    guard let smaller = context.makeImage() else { fail("cannot scale the icon") }
    return smaller
}

func write(_ image: CGImage, to url: URL) {
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else { fail("cannot encode \(url.path)") }
    do {
        try data.write(to: url)
    } catch {
        fail("cannot write \(url.path): \(error.localizedDescription)")
    }
}

let arguments = CommandLine.arguments
guard let artPath = value(after: "--art", in: arguments) else { fail("--art is required") }
guard let outputPath = value(after: "--output", in: arguments) else { fail("--output is required") }
guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: artPath) as CFURL, nil),
      let art = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot read \(artPath)") }
guard art.width == art.height else { fail("\(artPath) is \(art.width)x\(art.height), not square") }

var smallArt = art
if let crop = value(after: "--small-crop", in: arguments) {
    let numbers = crop.split(separator: ",").compactMap { Int($0) }
    guard numbers.count == 3, numbers[2] > 0, numbers[0] >= 0, numbers[1] >= 0,
          numbers[0] + numbers[2] <= art.width, numbers[1] + numbers[2] <= art.height,
          let cropped = art.cropping(to: CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[2]))
    else { fail("--small-crop \(crop) is not X,Y,SIZE inside the art") }
    smallArt = cropped
}

var bySize: [Int: CGImage] = [:]
var smallBySize: [Int: CGImage] = [:]
var large = icon(from: art, body: bodySize)
var small = icon(from: smallArt, body: smallBodySize)
var pixels = canvasSize
while pixels >= 16 {
    bySize[pixels] = large
    smallBySize[pixels] = small
    if pixels > 16 {
        large = halved(large)
        small = halved(small)
    }
    pixels /= 2
}

let output = URL(fileURLWithPath: outputPath, isDirectory: true)
do {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
} catch {
    fail("cannot make \(output.path): \(error.localizedDescription)")
}
for size in iconSizes {
    let image = size.pixels <= smallSizeLimit ? smallBySize[size.pixels]! : bySize[size.pixels]!
    write(image, to: output.appendingPathComponent("\(size.name).png", isDirectory: false))
}
