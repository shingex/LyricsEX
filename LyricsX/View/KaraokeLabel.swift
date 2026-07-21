import Cocoa
import CoreImage
import SwiftCF
import CoreGraphicsExt
import CoreTextExt

class KaraokeLabel: NSTextField {
    @objc dynamic var isVertical = false {
        didSet {
            clearCache()
            invalidateIntrinsicContentSize()
        }
    }

    @objc dynamic var drawFurigana = false {
        didSet {
            clearCache()
            invalidateIntrinsicContentSize()
        }
    }

    @objc dynamic var drawRomajin = false {
        didSet {
            clearCache()
            invalidateIntrinsicContentSize()
        }
    }

    override var attributedStringValue: NSAttributedString {
        didSet {
            clearCache()
        }
    }

    override var stringValue: String {
        didSet {
            clearCache()
        }
    }

    @objc override dynamic var font: NSFont? {
        didSet {
            clearCache()
        }
    }

    @objc override dynamic var textColor: NSColor? {
        didSet {
            clearCache()
        }
    }

    private func clearCache() {
        _attrString = nil
        _ctFrame = nil
        needsLayout = true
        needsDisplay = true
        removeProgressAnimation()
    }

    private var _attrString: NSAttributedString?
    private var romajinAnnotations: [(String, NSRange)] = []

    private var attrString: NSAttributedString {
        if let attrString = _attrString {
            return attrString
        }
        let attrString = NSMutableAttributedString(attributedString: attributedStringValue)
        let string = attrString.string as NSString
        let shouldDrawFurigana = drawFurigana && string.dominantLanguage == "ja"
        let shouldDrawRomajin = drawRomajin && string.dominantLanguage == "ja"
        let tokenizer = CFStringTokenizer.create(string: .from(string))
        romajinAnnotations = []
        for tokenType in IteratorSequence(tokenizer) where tokenType.contains(.isCJWordMask) {
            if isVertical {
                let tokenRange = tokenizer.currentTokenRange()
                let attr: [NSAttributedString.Key: Any] = [
                    .verticalGlyphForm: true,
                    .baselineOffset: (font?.pointSize ?? 24) * 0.25,
                ]
                attrString.addAttributes(attr, range: tokenRange.asNS)
            }
            guard shouldDrawFurigana else { continue }
            if let (furigana, range) = tokenizer.currentFuriganaAnnotation(in: string) {
                var attr: [CFAttributedString.Key: Any] = [.ctRubySizeFactor: 0.5]
                attr[.ctForegroundColor] = textColor
                let annotation = CTRubyAnnotation.create(furigana, attributes: attr)
                attrString.addAttribute(.cf(.ctRubyAnnotation), value: annotation, range: range)
            }
            if shouldDrawRomajin, let (romajin, range) = tokenizer.currentRomanjiAnnotation(in: string) {
                romajinAnnotations.append((romajin as String, range))
            }
        }
        textColor?.do { attrString.addAttributes([.foregroundColor: $0], range: attrString.fullRange) }
        _attrString = attrString
        return attrString
    }

    private var _ctFrame: CTFrame?

    private func ctFrame(_ dirtyRect: NSRect? = nil) -> CTFrame {
        if let ctFrame = _ctFrame {
            return ctFrame
        }
        if dirtyRect == nil {
            layoutSubtreeIfNeeded()
        }
        let progression: CTFrameProgression = isVertical ? .rightToLeft : .topToBottom
        let frameAttr: [CTFrame.AttributeKey: Any] = [.progression: progression.rawValue as NSNumber]
        let framesetter = CTFramesetter.create(attributedString: attrString)
        let (suggestSize, fitRange) = framesetter.suggestFrameSize(constraints: (dirtyRect ?? bounds).size, frameAttributes: frameAttr)
        let path = CGPath(rect: CGRect(origin: .zero, size: suggestSize), transform: nil)
        let ctFrame = framesetter.frame(stringRange: fitRange, path: path, frameAttributes: frameAttr)
        _ctFrame = ctFrame
        return ctFrame
    }

    override var intrinsicContentSize: NSSize {
        let progression: CTFrameProgression = isVertical ? .rightToLeft : .topToBottom
        let frameAttr: [CTFrame.AttributeKey: Any] = [.progression: progression.rawValue as NSNumber]
        let framesetter = CTFramesetter.create(attributedString: attrString)
        let constraints = CGSize(width: CGFloat.infinity, height: .infinity)
        return framesetter.suggestFrameSize(constraints: constraints, frameAttributes: frameAttr).size
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        let cgContext = context.cgContext
        cgContext.textMatrix = .identity
        cgContext.translateBy(x: 0, y: bounds.height)
        cgContext.scaleBy(x: 1.0, y: -1.0)
        if !isProgressLayerActive {
            CTFrameDraw(ctFrame(dirtyRect), cgContext)
        }

        drawRomajiAnnotations(in: cgContext, frame: ctFrame())
    }

    // MARK: - Progress

    // TODO: multi-line
    private var solidProgressColor: NSColor?
    private var isProgressLayerActive = false
    private var displaysProgressGradientAsBase = false
    private var progressBoundaryGap: CGFloat = 0
    private var textBlurRadius: CGFloat = 0

    private lazy var progressLayer: CAGradientLayer = {
        let pLayer = CAGradientLayer()
        wantsLayer = true
        layer?.addSublayer(pLayer)
        return pLayer
    }()

    @objc dynamic var progressColor: NSColor? {
        get {
            return solidProgressColor
        }
        set {
            solidProgressColor = newValue
            updateProgressLayerColors()
        }
    }

    var progressGradientColors: [NSColor]? {
        didSet {
            updateProgressLayerColors()
        }
    }

    var reversesProgressGradient = false {
        didSet {
            updateProgressLayerColors()
        }
    }

    func setProgressAnimation(color: NSColor, progress: [(TimeInterval, Int)]) {
        progressGradientColors = nil
        progressColor = color
        runProgressAnimation(progress: progress)
    }

    func setProgressAnimation(colors: [NSColor], progress: [(TimeInterval, Int)]) {
        if colors.count >= 2 {
            progressGradientColors = colors
        } else if let color = colors.first {
            progressGradientColors = nil
            progressColor = color
        }
        runProgressAnimation(progress: progress)
    }

    func setDisplaysProgressGradientAsBase(_ displays: Bool) {
        if displays {
            if displaysProgressGradientAsBase, isProgressLayerActive {
                updateProgressLayerColors()
                return
            }
            removeProgressAnimation()
            displaysProgressGradientAsBase = true
            guard prepareProgressLayer() != nil else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            progressLayer.locations = [0, 1]
            CATransaction.commit()
        } else if displaysProgressGradientAsBase {
            displaysProgressGradientAsBase = false
            removeProgressAnimation()
        }
    }

    func setTextBlurRadius(_ radius: CGFloat) {
        let radius = max(0, radius)
        guard radius != textBlurRadius else { return }
        textBlurRadius = radius
        wantsLayer = true
        layer?.masksToBounds = false

        guard radius > 0, let filter = CIFilter(name: "CIGaussianBlur") else {
            layer?.filters = []
            return
        }
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        layer?.filters = [filter]
    }

    private func runProgressAnimation(progress: [(TimeInterval, Int)]) {
        displaysProgressGradientAsBase = false
        removeProgressAnimation()
        guard let progressLayout = prepareProgressLayer() else { return }
        let line = progressLayout.line
        let progressExtent = progressLayout.extent
        let progressLeadingInset = progressLayout.leadingInset
        let progressBleed = progressLayout.bleed

        progressBoundaryGap = min(max((font?.pointSize ?? 24) * 0.5, 1) / max(progressExtent, 1), 1)
        guard let index = progress.firstIndex(where: { $0.0 > 0 }) else {
            progressLayer.locations = progressLayerLocations(for: progressExtent, extent: progressExtent)
            return
        }
        var map = progress.map {
            (
                $0.0,
                min(max(line.offset(charIndex: $0.1).primary + progressLeadingInset + progressBleed, 0), progressExtent)
            )
        }
        if index > 0 {
            let progress = map[index - 1].1 + CGFloat(map[index - 1].0) * (map[index].1 - map[index - 1].1) / CGFloat(map[index].0 - map[index - 1].0)
            map.replaceSubrange(..<index, with: [(0, progress)])
        }

        let duration = map.last!.0
        let locationValues = map.map { progressLayerLocations(for: $0.1, extent: progressExtent) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.locations = locationValues.last
        CATransaction.commit()
        let animation = CAKeyframeAnimation()
        animation.keyTimes = map.map { ($0.0 / duration) as NSNumber }
        animation.values = locationValues
        animation.keyPath = "locations"
        animation.duration = duration
        progressLayer.add(animation, forKey: "inlineProgress")
    }

    private func prepareProgressLayer() -> (line: CTLine, leadingInset: CGFloat, extent: CGFloat, bleed: CGFloat)? {
        guard let line = ctFrame().lines.first,
              let origin = ctFrame().lineOrigins(range: CFRange(location: 0, length: 1)).first else {
            return nil
        }
        var lineBounds = line.bounds()
        var transform = CGAffineTransform.translate(x: origin.x, y: origin.y)
        if isVertical {
            transform.transform(by: .swap() * .translate(y: -lineBounds.width))
            transform *= .flip(height: bounds.height)
        }
        lineBounds.apply(t: transform)
        let progressBleed = max(2, ceil((font?.pointSize ?? 24) * 0.06))
        let progressBounds = lineBounds
            .insetBy(dx: -progressBleed, dy: -progressBleed)
            .integral
        let progressLeadingInset = isVertical
            ? lineBounds.minY - progressBounds.minY
            : lineBounds.minX - progressBounds.minX
        let progressExtent = isVertical ? progressBounds.height : progressBounds.width
        let backingScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2

        progressLayer.anchorPoint = isVertical ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0, y: 0.5)
        progressLayer.frame = progressBounds
        progressLayer.contentsScale = backingScale
        progressLayer.startPoint = isVertical ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0, y: 0.5)
        progressLayer.endPoint = isVertical ? CGPoint(x: 0.5, y: 1) : CGPoint(x: 1, y: 0.5)
        updateProgressLayerColors()
        isProgressLayerActive = true
        needsDisplay = true
        let mask = CALayer()
        mask.frame = progressLayer.bounds
        mask.contentsScale = backingScale
        let img = NSImage(size: progressLayer.bounds.size, flipped: false) { _ in
            let context = NSGraphicsContext.current!.cgContext
            let ori = progressBounds.applying(.flip(height: self.bounds.height)).origin
            context.concatenate(.translate(x: -ori.x, y: -ori.y))
            CTFrameDraw(self.ctFrame(), context)
            return true
        }
        mask.contents = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        progressLayer.mask = mask
        return (line, progressLeadingInset, progressExtent, progressBleed)
    }

    func pauseProgressAnimation() {
        let pausedTime = progressLayer.convertTime(CACurrentMediaTime(), from: nil)
        progressLayer.speed = 0
        progressLayer.timeOffset = pausedTime
    }

    func resumeProgressAnimation() {
        let pausedTime = progressLayer.timeOffset
        progressLayer.speed = 1
        progressLayer.timeOffset = 0
        progressLayer.beginTime = 0
        let timeSincePause = progressLayer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        progressLayer.beginTime = timeSincePause
    }

    func removeProgressAnimation() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.speed = 1
        progressLayer.timeOffset = 0
        progressLayer.removeAnimation(forKey: "inlineProgress")
        progressLayer.frame = .zero
        progressLayer.mask = nil
        isProgressLayerActive = false
        needsDisplay = true
        CATransaction.commit()
    }

    private func updateProgressLayerColors() {
        let progressColors = progressGradientColors ?? solidProgressColor.map { [$0, $0] } ?? []
        guard let firstProgressColor = progressColors.first,
              let lastProgressColor = progressColors.last else {
            progressLayer.colors = []
            return
        }
        let baseColor = textColor ?? .black
        let colors: [NSColor]
        if displaysProgressGradientAsBase {
            colors = [lastProgressColor, firstProgressColor]
        } else if reversesProgressGradient {
            colors = [baseColor, baseColor, lastProgressColor, firstProgressColor]
        } else {
            colors = [firstProgressColor, lastProgressColor, baseColor, baseColor]
        }
        progressLayer.colors = colors.map(\.cgColor)
    }

    private func progressLayerLocations(for progress: CGFloat, extent: CGFloat) -> [NSNumber] {
        let leadingProgress = (progress / max(extent, 1)).clamped(to: 0...1)
        let trailingBaseProgress = min(leadingProgress + progressBoundaryGap, 1)
        return [0, leadingProgress, trailingBaseProgress, 1].map { $0 as NSNumber }
    }

    private func drawRomajiAnnotations(in context: CGContext, frame: CTFrame) {
        guard drawRomajin, !romajinAnnotations.isEmpty else { return }

        let lines = frame.lines
        let origins = frame.lineOrigins(range: CFRangeMake(0, lines.count))
        var annotationIndex = 0

        // 处理每行和每个 glyph run
        for (line, origin) in zip(lines, origins) {
            let runs = line.glyphRuns
            for run in runs {
                let range = run.stringRange
                var subIndex = 0

                while annotationIndex + subIndex < romajinAnnotations.count {
                    let (romajin, annotationRange) = romajinAnnotations[annotationIndex + subIndex]
                    if NSRange(location: range.location, length: range.length).contains(annotationRange.location) {
                        var ascent: CGFloat = 0
                        var descent: CGFloat = 0
                        var leading: CGFloat = 0
                        let width = CTRunGetTypographicBounds(run, CFRangeMake(0, 0), &ascent, &descent, &leading)
                        var position = CGPoint.zero
                        CTRunGetPositions(run, CFRangeMake(0, 1), &position)
                        let glyphX = origin.x + position.x

                        let relativeOffset = CGFloat(annotationRange.location - range.location) / CGFloat(range.length) * width
                        let glyphBounds = CGRect(
                            x: glyphX + relativeOffset,
                            y: origin.y - descent,
                            width: width / CGFloat(range.length) * CGFloat(annotationRange.length),
                            height: ascent + descent
                        )

                        let fontSize = font?.pointSize ?? 24
                        var rubyFontSize = fontSize * 0.3
                        let rubyFontBase = NSFont.systemFont(ofSize: rubyFontSize)
                        let rubyAttrBase: [NSAttributedString.Key: Any] = [
                            .foregroundColor: textColor ?? .black,
                            .font: rubyFontBase,
                        ]
                        var rubyString = NSAttributedString(string: romajin, attributes: rubyAttrBase)
                        var rubyWidth = rubyString.size().width
                        let maxWidth = glyphBounds.width

                        while rubyWidth > maxWidth * 0.8, rubyFontSize > 1 {
                            rubyFontSize *= 0.9
                            let rubyFont = NSFont.systemFont(ofSize: rubyFontSize)
                            let rubyAttr: [NSAttributedString.Key: Any] = [
                                .font: rubyFont,
                                .foregroundColor: textColor ?? .black,
                            ]
                            rubyString = NSAttributedString(string: romajin, attributes: rubyAttr)
                            rubyWidth = rubyString.size().width
                        }

                        let glyphWidth = glyphBounds.width
                        let xOffset = (glyphWidth - rubyWidth) / 2
                        let rubyPoint = CGPoint(
                            x: glyphBounds.minX + xOffset,
                            y: glyphBounds.minY - fontSize * 0.2
                        )
                        let rubyLine = CTLineCreateWithAttributedString(rubyString)
                        context.textPosition = rubyPoint
                        CTLineDraw(rubyLine, context)

                        subIndex += 1
                    } else {
                        break
                    }
                }
                annotationIndex += subIndex
            }
        }

        // 处理剩余的 annotations
        while annotationIndex < romajinAnnotations.count {
            let (romajin, _) = romajinAnnotations[annotationIndex]
            if let lastLine = lines.last, let lastOrigin = origins.last, let lastRun = lastLine.glyphRuns.last {
                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                var leading: CGFloat = 0
                let width = CTRunGetTypographicBounds(lastRun, CFRangeMake(0, 0), &ascent, &descent, &leading)
                var position = CGPoint.zero
                CTRunGetPositions(lastRun, CFRangeMake(0, 1), &position)
                let glyphX = lastOrigin.x + position.x + width
                let glyphBounds = CGRect(
                    x: glyphX,
                    y: lastOrigin.y - descent,
                    width: width,
                    height: ascent + descent
                )

                let fontSize = font?.pointSize ?? 24
                var rubyFontSize = fontSize * 0.3
                let rubyAttrBase: [NSAttributedString.Key: Any] = [
                    .foregroundColor: textColor ?? .black,
                ]
                var rubyString = NSAttributedString(string: romajin, attributes: rubyAttrBase)
                var rubyWidth = rubyString.size().width
                let maxWidth = glyphBounds.width

                while rubyWidth > maxWidth * 0.8, rubyFontSize > 1 {
                    rubyFontSize *= 0.9
                    let rubyFont = NSFont.systemFont(ofSize: rubyFontSize)
                    let rubyAttr: [NSAttributedString.Key: Any] = [
                        .font: rubyFont,
                        .foregroundColor: textColor ?? .black,
                    ]
                    rubyString = NSAttributedString(string: romajin, attributes: rubyAttr)
                    rubyWidth = rubyString.size().width
                }

                let glyphWidth = glyphBounds.width
                let xOffset = (glyphWidth - rubyWidth) / 2
                let rubyPoint = CGPoint(
                    x: glyphBounds.minX + xOffset,
                    y: glyphBounds.minY - 0.2 * fontSize
                )
                let rubyLine = CTLineCreateWithAttributedString(rubyString)
                context.textPosition = rubyPoint
                CTLineDraw(rubyLine, context)
            }
            annotationIndex += 1
        }
    }
}
