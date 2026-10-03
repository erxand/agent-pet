import AppKit

package enum PixelRenderer {
    private static let bitsPerSample = 8
    private static let samplesPerPixel = 4
    private static let bitsPerPixel = 32
    private static let bytesPerPixel = 4
    private static let maximumComponentValue: CGFloat = 255

    package static func image(for frame: PixelFrame, palette: SpritePalette, scale: Int, facingLeft: Bool) -> NSImage {
        let effectiveScale = max(1, scale)
        let frameSideLength = frame.sideLength
        let pixelSideLength = frameSideLength * effectiveScale
        let imageSize = NSSize(width: pixelSideLength, height: pixelSideLength)

        guard let representation = makeRepresentation(pixelSideLength: pixelSideLength),
              let pixelBuffer = representation.bitmapData else {
            return NSImage(size: imageSize)
        }

        let bytesPerRow = representation.bytesPerRow
        pixelBuffer.update(repeating: 0, count: bytesPerRow * pixelSideLength)

        var componentsByCharacter: [Character: PixelComponents?] = [:]
        for frameRow in 0..<frameSideLength {
            for frameColumn in 0..<frameSideLength {
                let sourceColumn = facingLeft ? frameSideLength - 1 - frameColumn : frameColumn
                let inkCharacter = frame.character(column: sourceColumn, row: frameRow)
                let components: PixelComponents?
                if let alreadyResolved = componentsByCharacter[inkCharacter] {
                    components = alreadyResolved
                } else {
                    let resolved = makeComponents(from: palette.color(for: inkCharacter))
                    componentsByCharacter[inkCharacter] = resolved
                    components = resolved
                }
                guard let components else { continue }
                fillBlock(
                    pixelBuffer: pixelBuffer,
                    bytesPerRow: bytesPerRow,
                    blockColumn: frameColumn,
                    blockRow: frameRow,
                    scale: effectiveScale,
                    components: components
                )
            }
        }

        let image = NSImage(size: imageSize)
        image.addRepresentation(representation.retagging(with: .sRGB) ?? representation)
        return image
    }

    private struct PixelComponents {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: UInt8
    }

    private static func makeRepresentation(pixelSideLength: Int) -> NSBitmapImageRep? {
        NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSideLength,
            pixelsHigh: pixelSideLength,
            bitsPerSample: bitsPerSample,
            samplesPerPixel: samplesPerPixel,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: pixelSideLength * bytesPerPixel,
            bitsPerPixel: bitsPerPixel
        )
    }

    private static func makeComponents(from inkColor: NSColor?) -> PixelComponents? {
        guard let inkColor, let convertedColor = inkColor.usingColorSpace(.sRGB) else { return nil }
        return PixelComponents(
            red: componentByte(from: convertedColor.redComponent),
            green: componentByte(from: convertedColor.greenComponent),
            blue: componentByte(from: convertedColor.blueComponent),
            alpha: componentByte(from: convertedColor.alphaComponent)
        )
    }

    private static func componentByte(from component: CGFloat) -> UInt8 {
        let clamped = min(max(component, 0), 1)
        return UInt8((clamped * maximumComponentValue).rounded())
    }

    private static func fillBlock(
        pixelBuffer: UnsafeMutablePointer<UInt8>,
        bytesPerRow: Int,
        blockColumn: Int,
        blockRow: Int,
        scale: Int,
        components: PixelComponents
    ) {
        for rowOffset in 0..<scale {
            let destinationRow = blockRow * scale + rowOffset
            let rowStartIndex = destinationRow * bytesPerRow
            for columnOffset in 0..<scale {
                let destinationColumn = blockColumn * scale + columnOffset
                let byteIndex = rowStartIndex + destinationColumn * bytesPerPixel
                pixelBuffer[byteIndex] = components.red
                pixelBuffer[byteIndex + 1] = components.green
                pixelBuffer[byteIndex + 2] = components.blue
                pixelBuffer[byteIndex + 3] = components.alpha
            }
        }
    }
}
