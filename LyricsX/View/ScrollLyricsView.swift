import AppKit
import LyricsXFoundation
import OpenCC

protocol ScrollLyricsViewDelegate: AnyObject {
    func doubleClickLyricsLine(at position: TimeInterval)
    func scrollWheelDidStartScroll()
    func scrollWheelDidEndScroll()
}

enum ScrollLyricsVisualStyle {
    case classic
}

class ScrollLyricsView: NSScrollView {
    weak var delegate: ScrollLyricsViewDelegate?

    private let activeLineAnimationOverlay = NSTextField(labelWithString: "")
    private var activeLineAnimationGeneration = 0

    private var textView: NSTextView {
        // swiftlint:disable:next force_cast
        return documentView as! NSTextView
    }

    var fadeStripWidth: CGFloat = 24

    @objc dynamic var textColor = #colorLiteral(red: 0.7540688515, green: 0.7540867925, blue: 0.7540771365, alpha: 1) {
        didSet {
            DispatchQueue.main.async {
                self.restyleAllText()
            }
        }
    }

    @objc dynamic var highlightColor = #colorLiteral(red: 0.8866666667, green: 1, blue: 0.8, alpha: 1) {
        didSet {
            guard let highlightedRange = self.highlightedRange else { return }
            DispatchQueue.main.async {
                self.applyHighlightedAttributes(to: highlightedRange)
            }
        }
    }

    @objc dynamic var fontName = "Helvetica" {
        didSet { updateFont() }
    }

    @objc dynamic var fontSize: CGFloat = 12 {
        didSet { updateFont() }
    }

    var visualStyle: ScrollLyricsVisualStyle = .classic {
        didSet {
            guard oldValue != visualStyle else { return }
            restyleAllText()
        }
    }

    var lyricAlignment: NSTextAlignment = .center {
        didSet {
            guard oldValue != lyricAlignment else { return }
            restyleAllText()
        }
    }

    var lineSpacingScale: CGFloat = 1 {
        didSet {
            lineSpacingScale = lineSpacingScale.clamped(to: 0.7...1.6)
            guard oldValue != lineSpacingScale else { return }
            restyleAllText()
        }
    }

    var animationAmount: CGFloat = 1 {
        didSet {
            animationAmount = animationAmount.clamped(to: 0...1.5)
        }
    }

    private var ranges: [(TimeInterval, NSRange)] = []
    private var highlightedRange: NSRange?
    private var highlightedIndex: Int?

    func setupTextContents(lyrics: Lyrics?) {
        guard let lyrics = lyrics else {
            ranges = []
            textView.string = ""
            highlightedRange = nil
            highlightedIndex = nil
            activeLineAnimationOverlay.isHidden = true
            return
        }

        setupActiveLineAnimationOverlayIfNeeded()
        var lrcContent = ""
        var newRanges: [(TimeInterval, NSRange)] = []
        let enabledLrc = lyrics.lines.filter { $0.enabled && !$0.content.isEmpty }
        let languageCode = lyrics.metadata.translationLanguages.first

        for line in enabledLrc {
            var lineStr = line.content
            if var trans = line.attachments[.translation(languageCode: languageCode)], defaults[.preferBilingualLyrics],
               languageCode?.hasPrefix("zh") == true {
                if let converter = ChineseConverter.shared {
                    trans = converter.convert(trans)
                }
                lineStr += "\n" + trans
            }
            let range = NSRange(location: lrcContent.utf16.count, length: lineStr.utf16.count)
            newRanges.append((line.position, range))
            lrcContent += lineStr
            if line != enabledLrc.last {
                lrcContent += "\n\n"
            }
        }
        ranges = newRanges
        textView.string = lrcContent
        highlightedRange = nil
        highlightedIndex = nil
        activeLineAnimationOverlay.isHidden = true
        restyleAllText()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        updateFadeEdgeMask()
        updateEdgeInset()
        updateActiveLineAnimationOverlayFrame()
    }

    override func mouseUp(with event: NSEvent) {
        guard event.clickCount == 2 else {
            super.mouseUp(with: event)
            return
        }

        let clickPoint = textView.convert(event.locationInWindow, from: nil)
        let clickRange = ranges.filter { _, range in
            let bounding = textView.layoutManager!.boundingRect(forGlyphRange: range, in: textView.textContainer!)
            return bounding.contains(clickPoint)
        }
        if let (position, _) = clickRange.first {
            delegate?.doubleClickLyricsLine(at: position)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        switch event.momentumPhase {
        case .began:
            delegate?.scrollWheelDidStartScroll()
        case .ended,
             .cancelled:
            delegate?.scrollWheelDidEndScroll()
        default:
            break
        }
    }

    // overriding scrollwheel method breaks trackpad responsive scrolling ability
    override class var isCompatibleWithResponsiveScrolling: Bool {
        return true
    }

    private func updateFadeEdgeMask() {
        let location = fadeStripWidth / frame.height
        wantsLayer = true
        layer?.mask = CAGradientLayer().then {
            $0.frame = bounds
            $0.colors = [#colorLiteral(red: 0, green: 0, blue: 0, alpha: 0), #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1), #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1), #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0)] as [CGColor]
            $0.locations = [0, location as NSNumber, (1 - location) as NSNumber, 1]
            $0.startPoint = .zero
            $0.endPoint = CGPoint(x: 0, y: 1)
        }
    }

    private func updateEdgeInset() {
        guard !ranges.isEmpty else {
            return
        }

        let bounding1 = textView.layoutManager!.boundingRect(forGlyphRange: ranges.first!.1, in: textView.textContainer!)
        let topInset = frame.height / 2 - bounding1.height / 2
        let bounding2 = textView.layoutManager!.boundingRect(forGlyphRange: ranges.last!.1, in: textView.textContainer!)
        let bottomInset = frame.height / 2 - bounding2.height / 2
        automaticallyAdjustsContentInsets = false
        contentInsets = NSEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
    }

    @discardableResult
    func highlight(position: TimeInterval) -> Bool {
        guard !ranges.isEmpty else {
            return false
        }

        var left = ranges.startIndex
        var right = ranges.endIndex - 1
        while left <= right {
            let mid = (left + right) / 2
            if ranges[mid].0 <= position {
                left = mid + 1
            } else {
                right = mid - 1
            }
        }
        let index = right.clamped(to: ranges.indices)
        let range = ranges[index].1

        if highlightedIndex == index {
            return false
        }

        if usesAMLLOriginalStackStyle {
            highlightedIndex = index
            highlightedRange = range
            restyleAllText()
            animateActiveLineChange(range: range)
        } else {
            highlightedRange.map { applyBaseAttributes(to: $0) }
            applyHighlightedAttributes(to: range)
            highlightedRange = range
            highlightedIndex = index
            animateActiveLineChange(range: range)
        }

        return true
    }

    func scroll(position: TimeInterval) {
        guard !ranges.isEmpty else {
            return
        }

        var left = ranges.startIndex
        var right = ranges.endIndex - 1
        while left <= right {
            let mid = (left + right) / 2
            if ranges[mid].0 <= position {
                left = mid + 1
            } else {
                right = mid - 1
            }
        }
        let range = ranges[right.clamped(to: ranges.indices)].1

        let bounding = textView.layoutManager!.boundingRect(forGlyphRange: range, in: textView.textContainer!)

        let point = NSPoint(x: 0, y: bounding.midY - frame.height / 2)
        textView.scroll(point)
        updateActiveLineAnimationOverlayFrame()
    }

    func updateFont() {
        restyleAllText()
    }

    private func restyleAllText() {
        let range = textView.string.fullRange
        guard range.length > 0 else { return }
        if usesAMLLOriginalStackStyle {
            for (index, item) in ranges.enumerated() {
                applyOriginalCompareAttributes(to: item.1, index: index)
            }
        } else {
            applyBaseAttributes(to: range)
            highlightedRange.map { applyHighlightedAttributes(to: $0) }
        }
        needsLayout = true
        updateActiveLineAnimationOverlayFrame()
    }

    private func applyBaseAttributes(to range: NSRange) {
        guard let storage = textView.textStorage else { return }
        guard let range = validTextRange(range, in: storage) else { return }
        storage.removeAttribute(.shadow, range: range)
        storage.addAttributes([
            .foregroundColor: baseTextColor,
            .paragraphStyle: paragraphStyle,
            .font: baseFont,
            .kern: usesAMLLFamilyStyle ? 0.1 : 0,
        ], range: range)
    }

    private func applyHighlightedAttributes(to range: NSRange) {
        guard let storage = textView.textStorage else { return }
        guard let range = validTextRange(range, in: storage) else { return }
        storage.removeAttribute(.shadow, range: range)
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: activeTextColor,
            .paragraphStyle: paragraphStyle,
            .font: activeFont,
            .kern: usesAMLLFamilyStyle ? 0.12 : 0,
        ]
        if let activeShadow {
            attributes[.shadow] = activeShadow
        }
        storage.addAttributes(attributes, range: range)
    }

    private func applyOriginalCompareAttributes(to range: NSRange, index: Int) {
        guard let storage = textView.textStorage else { return }
        guard let range = validTextRange(range, in: storage) else { return }
        let currentIndex = highlightedIndex ?? index
        let distance = abs(index - currentIndex)
        let isActive = distance == 0
        let isPassed = index < currentIndex
        let alpha: CGFloat
        switch distance {
        case 0:
            alpha = 1
        case 1:
            alpha = isPassed ? 0.24 : 0.42
        case 2:
            alpha = isPassed ? 0.14 : 0.25
        default:
            alpha = isPassed ? 0.08 : 0.16
        }

        storage.addAttributes([
            .foregroundColor: (isActive ? activeTextColor : textColor).withAlphaComponent(alpha),
            .paragraphStyle: paragraphStyle,
            .font: originalCompareFont(distance: distance),
            .kern: isActive ? 0.12 : 0,
            .shadow: originalCompareShadow(distance: distance),
        ], range: range)
    }

    private func validTextRange(_ range: NSRange, in storage: NSTextStorage) -> NSRange? {
        guard range.location >= 0,
              range.length > 0,
              range.location < storage.length else {
            return nil
        }
        return NSRange(location: range.location, length: min(range.length, storage.length - range.location))
    }

    private func setupActiveLineAnimationOverlayIfNeeded() {
        guard activeLineAnimationOverlay.superview == nil else {
            return
        }

        activeLineAnimationOverlay.isBezeled = false
        activeLineAnimationOverlay.isBordered = false
        activeLineAnimationOverlay.drawsBackground = false
        activeLineAnimationOverlay.isEditable = false
        activeLineAnimationOverlay.isSelectable = false
        activeLineAnimationOverlay.maximumNumberOfLines = 0
        activeLineAnimationOverlay.lineBreakMode = .byWordWrapping
        activeLineAnimationOverlay.wantsLayer = true
        activeLineAnimationOverlay.alphaValue = 1
        activeLineAnimationOverlay.isHidden = true
        activeLineAnimationOverlay.layer?.masksToBounds = false
        activeLineAnimationOverlay.layer?.shadowOffset = .zero
        activeLineAnimationOverlay.layer?.shadowRadius = 18
        activeLineAnimationOverlay.layer?.shadowOpacity = 0
        contentView.addSubview(activeLineAnimationOverlay, positioned: .above, relativeTo: nil)
    }

    private func animateActiveLineChange(range: NSRange) {
        guard usesAMLLFamilyStyle, animationAmount > 0 else {
            activeLineAnimationOverlay.isHidden = true
            return
        }

        setupActiveLineAnimationOverlayIfNeeded()
        updateActiveLineAnimationOverlayContent(range: range)
        updateActiveLineAnimationOverlayFrame()

        activeLineAnimationGeneration += 1
        let generation = activeLineAnimationGeneration
        let layer = activeLineAnimationOverlay.layer
        activeLineAnimationOverlay.isHidden = false
        activeLineAnimationOverlay.alphaValue = 1
        layer?.removeAnimation(forKey: "activeLineScalePulse")
        layer?.removeAnimation(forKey: "activeLineOpacityPulse")
        layer?.removeAnimation(forKey: "activeLineGlowPulse")
        layer?.opacity = 0
        layer?.transform = CATransform3DIdentity
        layer?.shadowColor = (activeTextColor.usingColorSpace(.deviceRGB) ?? activeTextColor).cgColor

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        let scaleLift = 0.08 * animationAmount
        scale.values = [1 - scaleLift, 1 + scaleLift, 1.0]
        scale.keyTimes = [0, 0.36, 1]
        scale.duration = 0.46
        scale.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
        ]

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 0.95 * animationAmount, 0.5 * animationAmount, 0]
        opacity.keyTimes = [0, 0.18, 0.64, 1]
        opacity.duration = 0.62
        opacity.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .easeIn),
        ]

        let glow = CAKeyframeAnimation(keyPath: "shadowOpacity")
        glow.values = [0, 0.72 * animationAmount, 0.24 * animationAmount, 0]
        glow.keyTimes = opacity.keyTimes
        glow.duration = opacity.duration
        glow.timingFunctions = opacity.timingFunctions

        layer?.add(scale, forKey: "activeLineScalePulse")
        layer?.add(opacity, forKey: "activeLineOpacityPulse")
        layer?.add(glow, forKey: "activeLineGlowPulse")

        DispatchQueue.main.asyncAfter(deadline: .now() + opacity.duration) { [weak self] in
            guard let self,
                  self.activeLineAnimationGeneration == generation else {
                return
            }
            self.activeLineAnimationOverlay.isHidden = true
            self.activeLineAnimationOverlay.layer?.opacity = 0
            self.activeLineAnimationOverlay.layer?.shadowOpacity = 0
        }
    }

    private func updateActiveLineAnimationOverlayContent(range: NSRange) {
        let storage = textView.string as NSString
        guard NSMaxRange(range) <= storage.length else {
            activeLineAnimationOverlay.stringValue = ""
            return
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = effectiveTextAlignment
        paragraph.lineSpacing = max(4, fontSize * 0.16 * lineSpacingScale)
        let activeLineText = storage.substring(with: range)
        activeLineAnimationOverlay.attributedStringValue = NSAttributedString(
            string: activeLineText,
            attributes: [
                .foregroundColor: activeTextColor,
                .font: activeFont,
                .paragraphStyle: paragraph,
                .kern: 0.12,
            ]
        )
    }

    private func updateActiveLineAnimationOverlayFrame() {
        guard !activeLineAnimationOverlay.isHidden,
              usesAMLLFamilyStyle,
              let highlightedRange,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: highlightedRange, actualCharacterRange: nil)
        var bounding = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        bounding.origin.x += textView.textContainerOrigin.x
        bounding.origin.y += textView.textContainerOrigin.y
        var frame = contentView.convert(bounding, from: textView).insetBy(dx: -18, dy: -10)
        frame.origin.x = max(0, frame.origin.x)
        frame.size.width = min(contentView.bounds.width - frame.origin.x, max(frame.width, contentView.bounds.width * 0.56))
        activeLineAnimationOverlay.frame = frame.integral
    }

    private var baseFont: NSFont {
        return NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
    }

    private var activeFont: NSFont {
        guard usesAMLLFamilyStyle else {
            return baseFont
        }
        let scale: CGFloat = usesAMLLOriginalStackStyle ? 1.16 : 1.08
        let activeSize = max(fontSize, fontSize * scale)
        let font = NSFont(name: fontName, size: activeSize) ?? NSFont.boldSystemFont(ofSize: activeSize)
        return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }

    private var baseTextColor: NSColor {
        guard usesAMLLFamilyStyle else {
            return textColor
        }
        return textColor.withAlphaComponent(0.42)
    }

    private var activeTextColor: NSColor {
        guard usesAMLLFamilyStyle else {
            return highlightColor
        }
        return highlightColor.blended(withFraction: 0.18, of: .white) ?? highlightColor
    }

    private var paragraphStyle: NSParagraphStyle {
        return NSMutableParagraphStyle().with {
            $0.alignment = effectiveTextAlignment
            if usesAMLLFamilyStyle {
                if usesAMLLOriginalStackStyle {
                    $0.lineSpacing = max(8, fontSize * 0.28 * lineSpacingScale)
                    $0.minimumLineHeight = fontSize * 1.18 * lineSpacingScale
                } else {
                    $0.lineSpacing = max(5, fontSize * 0.18 * lineSpacingScale)
                    $0.minimumLineHeight = fontSize * 1.12 * lineSpacingScale
                }
            }
        }
    }

    private var effectiveTextAlignment: NSTextAlignment {
        guard usesAMLLFamilyStyle else {
            return .center
        }
        return lyricAlignment
    }

    private var usesAMLLFamilyStyle: Bool {
        return visualStyle != .classic
    }

    private var usesAMLLOriginalStackStyle: Bool {
        return false
    }

    private var activeShadow: NSShadow? {
        return nil
    }

    private func originalCompareFont(distance: Int) -> NSFont {
        let scale: CGFloat
        switch distance {
        case 0:
            scale = 1.16
        case 1:
            scale = 0.94
        default:
            scale = 0.88
        }
        let size = max(10, fontSize * scale)
        let font = NSFont(name: fontName, size: size) ?? NSFont.systemFont(ofSize: size)
        guard distance == 0 else {
            return font
        }
        return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }

    private func originalCompareShadow(distance: Int) -> Any {
        let blur: CGFloat
        let alpha: CGFloat
        switch distance {
        case 0:
            blur = 12
            alpha = 0.42
        case 1:
            blur = 3
            alpha = 0.18
        default:
            blur = 5
            alpha = 0.10
        }
        return NSShadow().with {
            $0.shadowBlurRadius = blur
            $0.shadowColor = NSColor.white.withAlphaComponent(alpha)
            $0.shadowOffset = .zero
        }
    }
}
