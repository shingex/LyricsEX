import AppKit
import CoreImage

enum DesktopLyricsAlbumColorExtractor {
    private static let minimumProgressCandidateSaturation: CGFloat = 0.2
    private static let minimumProgressGradientSaturation: CGFloat = 0.24
    private static let deviceRGBColorSpace = CGColorSpaceCreateDeviceRGB()
    private static let ciContext = CIContext(options: [
        .workingColorSpace: deviceRGBColorSpace,
        .outputColorSpace: deviceRGBColorSpace,
    ])

    static func cgImage(from image: NSImage) -> CGImage? {
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    static func backgroundColor(from cgImage: CGImage) -> NSColor? {
        if let color = sampledDominantColors(from: cgImage).first {
            return color
        }

        let colorSpace = deviceRGBColorSpace
        let image = normalizedRGBCIImage(from: cgImage, maxPixelDimension: 320, colorSpace: colorSpace)

        if let colors = dominantColors(from: image, colorSpace: colorSpace) {
            let adjusted = colors
                .compactMap { $0.usingColorSpace(.deviceRGB) }
                .map(adjustedColor(_:))
                .sorted { $0.saturationComponent > $1.saturationComponent }

            if let color = adjusted.first(where: { $0.brightnessComponent > 0.1 }) {
                return color
            }
        }

        return averageColor(from: image, colorSpace: colorSpace).map(adjustedColor(_:))
    }

    static func progressColors(from cgImage: CGImage) -> [NSColor] {
        let colorSpace = deviceRGBColorSpace
        let image = normalizedRGBCIImage(from: cgImage, maxPixelDimension: 320, colorSpace: colorSpace)
        let sampledColors = distinctProgressColors(sampledProgressColors(from: cgImage))
        if let pair = balancedProgressPair(from: sampledColors) {
            return pair
        }

        let kMeansColors = dominantColors(from: image, colorSpace: colorSpace)
            .map { distinctProgressColors($0) } ?? []
        if let pair = balancedProgressPair(from: sampledColors + kMeansColors) {
            return pair
        }

        let averageProgressColor = averageColor(from: image, colorSpace: colorSpace)
            .flatMap { distinctProgressColors([$0]).first }
        if let color = sampledColors.first ?? kMeansColors.first ?? averageProgressColor {
            return [color, color]
        }

        return [desktopLyricsAlbumBlurDefaultProgressColor, desktopLyricsAlbumBlurDefaultProgressColor]
    }

    static func blurredArtwork(from cgImage: CGImage, blurAmount: Double) -> CGImage? {
        let colorSpace = deviceRGBColorSpace
        let image = normalizedRGBCIImage(from: cgImage, maxPixelDimension: 360, colorSpace: colorSpace)
        let extent = image.extent
        let radius = Swift.max(0, Swift.min(1, blurAmount)) * 44
        let blurredImage = radius > 0
            ? image
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": radius])
                .cropped(to: extent)
            : image
        let filteredImage = blurredImage
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.25,
                kCIInputBrightnessKey: -0.04,
                kCIInputContrastKey: 1.06,
            ])

        return ciContext.createCGImage(filteredImage, from: extent)
    }

    private struct ColorBucket {
        var count = 0
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
    }

    private static func sampledDominantColors(from cgImage: CGImage) -> [NSColor] {
        let width = 64
        let height = 64
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return []
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var buckets: [Int: ColorBucket] = [:]
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = CGFloat(bytes[index + 3]) / 255
            guard alpha > 0.9 else { continue }

            let red = CGFloat(bytes[index]) / 255
            let green = CGFloat(bytes[index + 1]) / 255
            let blue = CGFloat(bytes[index + 2]) / 255
            let color = NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)

            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var ignoredAlpha: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &ignoredAlpha)

            guard brightness >= 0.12, brightness <= 0.92, saturation >= 0.18 else {
                continue
            }

            let redBucket = Int(red * 7)
            let greenBucket = Int(green * 7)
            let blueBucket = Int(blue * 7)
            let key = (redBucket << 16) | (greenBucket << 8) | blueBucket
            var bucket = buckets[key] ?? ColorBucket()
            bucket.count += 1
            bucket.red += red
            bucket.green += green
            bucket.blue += blue
            bucket.saturation += saturation
            bucket.brightness += brightness
            buckets[key] = bucket
        }

        let ranked = buckets.values.compactMap { bucket -> (score: Double, color: NSColor)? in
            guard bucket.count > 0 else { return nil }
            let count = CGFloat(bucket.count)
            let red = bucket.red / count
            let green = bucket.green / count
            let blue = bucket.blue / count
            let averageSaturation = bucket.saturation / count
            let averageBrightness = bucket.brightness / count

            let color = NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
            let adjusted = adjustedSampledColor(color)
            let darkPenalty = averageBrightness < 0.25 ? 0.65 : 1
            let score = Double(count) * (0.6 + Double(averageSaturation)) * darkPenalty
            return (score, adjusted)
        }.sorted { $0.score > $1.score }

        return distinctColors(ranked.map(\.color))
    }

    private static func sampledProgressColors(from cgImage: CGImage) -> [NSColor] {
        let width = 72
        let height = 72
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return []
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var buckets: [Int: ColorBucket] = [:]
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = CGFloat(bytes[index + 3]) / 255
            guard alpha > 0.9 else { continue }

            let red = CGFloat(bytes[index]) / 255
            let green = CGFloat(bytes[index + 1]) / 255
            let blue = CGFloat(bytes[index + 2]) / 255
            let color = NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)

            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var ignoredAlpha: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &ignoredAlpha)

            guard brightness >= 0.08,
                  brightness <= 0.96,
                  saturation >= minimumProgressCandidateSaturation else {
                continue
            }

            let redBucket = Int(red * 9)
            let greenBucket = Int(green * 9)
            let blueBucket = Int(blue * 9)
            let key = (redBucket << 16) | (greenBucket << 8) | blueBucket
            var bucket = buckets[key] ?? ColorBucket()
            bucket.count += 1
            bucket.red += red
            bucket.green += green
            bucket.blue += blue
            bucket.saturation += saturation
            bucket.brightness += brightness
            buckets[key] = bucket
        }

        let ranked = buckets.values.compactMap { bucket -> (score: CGFloat, color: NSColor)? in
            guard bucket.count > 0 else { return nil }
            let count = CGFloat(bucket.count)
            let red = bucket.red / count
            let green = bucket.green / count
            let blue = bucket.blue / count
            let averageSaturation = bucket.saturation / count
            let averageBrightness = bucket.brightness / count
            guard averageSaturation >= minimumProgressCandidateSaturation else {
                return nil
            }

            let color = NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
            let chromaScore = averageSaturation * 3.0
            let visibilityScore = 1 - abs(averageBrightness - 0.68)
            let areaScore = log(count + 1)
            let score = (0.4 + chromaScore + visibilityScore * 0.45) * areaScore
            return (score, color)
        }.sorted { $0.score > $1.score }

        return ranked.map(\.color)
    }

    private static func normalizedRGBCIImage(from cgImage: CGImage, maxPixelDimension: CGFloat, colorSpace: CGColorSpace) -> CIImage {
        var image = CIImage(cgImage: cgImage, options: [.colorSpace: colorSpace])
        let extent = image.extent.integral
        let scale = Swift.min(1, maxPixelDimension / Swift.max(extent.width, extent.height))
        if scale < 1 {
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        return image
    }

    private static func dominantColors(from image: CIImage, colorSpace: CGColorSpace, clusterCount: Int = 8) -> [NSColor]? {
        guard let filter = CIFilter(name: "CIKMeans") else {
            return nil
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: image.extent), forKey: "inputExtent")
        filter.setValue(clusterCount, forKey: "inputCount")
        filter.setValue(20, forKey: "inputPasses")
        filter.setValue(NSNumber(value: true), forKey: "inputPerceptual")

        guard let rawOutputImage = filter.outputImage else {
            return nil
        }
        let outputImage = rawOutputImage
            .unpremultiplyingAlpha()
            .applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])

        var bitmap = [UInt8](repeating: 0, count: 4 * clusterCount)
        ciContext.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4 * clusterCount,
            bounds: CGRect(x: 0, y: 0, width: clusterCount, height: 1),
            format: .RGBA8,
            colorSpace: colorSpace
        )

        return (0..<clusterCount).map { index in
            let offset = index * 4
            return NSColor(
                calibratedRed: CGFloat(bitmap[offset]) / 255,
                green: CGFloat(bitmap[offset + 1]) / 255,
                blue: CGFloat(bitmap[offset + 2]) / 255,
                alpha: 1
            )
        }
    }

    private static func averageColor(from image: CIImage, colorSpace: CGColorSpace) -> NSColor? {
        guard let filter = CIFilter(name: "CIAreaAverage") else {
            return nil
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: image.extent), forKey: "inputExtent")
        guard let outputImage = filter.outputImage else {
            return nil
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: colorSpace
        )

        return NSColor(
            calibratedRed: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: 1
        )
    }

    private static func adjustedColor(_ color: NSColor) -> NSColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        brightness = Swift.max(brightness - 0.2, 0.1)
        if saturation < 0.9 {
            saturation = Swift.max(0.1, saturation * 3)
        }

        return NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
    }

    private static func adjustedSampledColor(_ color: NSColor) -> NSColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        saturation = Swift.min(0.85, Swift.max(0.35, saturation * 1.35))
        brightness = Swift.min(0.72, Swift.max(0.22, brightness * 0.82))

        return NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
    }

    private static func adjustedProgressColor(_ color: NSColor) -> NSColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        saturation = Swift.min(0.82, Swift.max(0.48, saturation * 1.08))
        brightness = Swift.min(0.9, Swift.max(0.62, brightness + 0.18))

        return NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
    }

    private static func distinctColors(_ colors: [NSColor]) -> [NSColor] {
        var result: [NSColor] = []
        for color in colors.compactMap({ $0.usingColorSpace(.deviceRGB) }) {
            guard !result.contains(where: { areSimilar($0, color) }) else {
                continue
            }
            result.append(color)
        }
        return result
    }

    private static func distinctProgressColors(_ colors: [NSColor]) -> [NSColor] {
        var result: [NSColor] = []
        for sourceColor in colors.compactMap({ $0.usingColorSpace(.deviceRGB) }) {
            guard sourceColor.saturationComponent >= minimumProgressCandidateSaturation else {
                continue
            }
            let color = adjustedProgressColor(sourceColor)
            guard !result.contains(where: { progressDistance($0, color) < 0.14 }) else {
                continue
            }
            result.append(color)
        }
        return result
    }

    private static func areSimilar(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        var lhsHue: CGFloat = 0
        var lhsSaturation: CGFloat = 0
        var lhsBrightness: CGFloat = 0
        var lhsAlpha: CGFloat = 0
        var rhsHue: CGFloat = 0
        var rhsSaturation: CGFloat = 0
        var rhsBrightness: CGFloat = 0
        var rhsAlpha: CGFloat = 0
        lhs.getHue(&lhsHue, saturation: &lhsSaturation, brightness: &lhsBrightness, alpha: &lhsAlpha)
        rhs.getHue(&rhsHue, saturation: &rhsSaturation, brightness: &rhsBrightness, alpha: &rhsAlpha)

        let hueDistance = Swift.min(abs(lhsHue - rhsHue), 1 - abs(lhsHue - rhsHue))
        return hueDistance < 0.06
            && abs(lhsSaturation - rhsSaturation) < 0.18
            && abs(lhsBrightness - rhsBrightness) < 0.18
    }

    private static func balancedProgressPair(from colors: [NSColor]) -> [NSColor]? {
        guard let firstColor = colors.first else {
            return nil
        }
        guard colors.count > 1 else {
            return [firstColor, firstColor]
        }

        var bestColor: NSColor?
        var bestScore: CGFloat = 0
        for color in colors.dropFirst() {
            guard hasCleanProgressGradient(from: firstColor, to: color) else {
                continue
            }
            let distance = progressDistance(firstColor, color)
            guard distance >= 0.2 else {
                continue
            }
            let overContrastPenalty = max(0, distance - 0.62) * 1.4
            let score = distance - overContrastPenalty
            if score > bestScore {
                bestScore = score
                bestColor = color
            }
        }

        return progressPairWithBrighterColorLast(firstColor, bestColor ?? firstColor)
    }

    private static func progressPairWithBrighterColorLast(_ firstColor: NSColor, _ secondColor: NSColor) -> [NSColor] {
        if perceivedBrightness(firstColor) > perceivedBrightness(secondColor) {
            return [secondColor, firstColor]
        }
        return [firstColor, secondColor]
    }

    private static func perceivedBrightness(_ color: NSColor) -> CGFloat {
        guard let rgbColor = color.usingColorSpace(.deviceRGB) else {
            return color.brightnessComponent
        }
        return rgbColor.redComponent * 0.2126
            + rgbColor.greenComponent * 0.7152
            + rgbColor.blueComponent * 0.0722
    }

    private static func hasCleanProgressGradient(from startColor: NSColor, to endColor: NSColor) -> Bool {
        guard let start = startColor.usingColorSpace(.deviceRGB),
              let end = endColor.usingColorSpace(.deviceRGB) else {
            return false
        }

        return [CGFloat(0.25), 0.5, 0.75].allSatisfy { progress in
            let color = NSColor(
                calibratedRed: start.redComponent + (end.redComponent - start.redComponent) * progress,
                green: start.greenComponent + (end.greenComponent - start.greenComponent) * progress,
                blue: start.blueComponent + (end.blueComponent - start.blueComponent) * progress,
                alpha: 1
            )
            return color.saturationComponent >= minimumProgressGradientSaturation
        }
    }

    private static func progressDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        var lhsHue: CGFloat = 0
        var lhsSaturation: CGFloat = 0
        var lhsBrightness: CGFloat = 0
        var lhsAlpha: CGFloat = 0
        var rhsHue: CGFloat = 0
        var rhsSaturation: CGFloat = 0
        var rhsBrightness: CGFloat = 0
        var rhsAlpha: CGFloat = 0
        lhs.getHue(&lhsHue, saturation: &lhsSaturation, brightness: &lhsBrightness, alpha: &lhsAlpha)
        rhs.getHue(&rhsHue, saturation: &rhsSaturation, brightness: &rhsBrightness, alpha: &rhsAlpha)

        let hueDistance = Swift.min(abs(lhsHue - rhsHue), 1 - abs(lhsHue - rhsHue))
        return hueDistance * 1.8
            + abs(lhsSaturation - rhsSaturation) * 0.45
            + abs(lhsBrightness - rhsBrightness) * 0.75
    }

}
