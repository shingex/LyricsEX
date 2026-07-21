import AppKit
import CoreImage
import SnapKit

private final class KaraokeDragHandleView: NSView {
    var menuProvider: (() -> NSMenu?)?

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else {
            super.rightMouseDown(with: event)
            return
        }
        popDetachedMenu(from: menu, at: convert(event.locationInWindow, from: nil))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = menuProvider?() else {
            return super.menu(for: event)
        }
        return menu.detachedContextMenu()
    }
}

private final class KaraokeInterludeDotsView: NSView {
    private static let animationKey = "interludePulse"
    private let colorLayer = CAGradientLayer()
    private let dotsMaskLayer = CALayer()
    private let dots = (0..<3).map { _ in CALayer() }
    private var dotDiameter: CGFloat = 8
    private var dotSpacing: CGFloat = 4
    private var isVertical = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(colorLayer)
        colorLayer.mask = dotsMaskLayer
        dots.forEach {
            $0.backgroundColor = NSColor.white.cgColor
            dotsMaskLayer.addSublayer($0)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: dotDiameter * 3 + dotSpacing * 2, height: dotDiameter)
    }

    override func layout() {
        super.layout()
        colorLayer.frame = bounds
        colorLayer.startPoint = isVertical ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0, y: 0.5)
        colorLayer.endPoint = isVertical ? CGPoint(x: 0.5, y: 1) : CGPoint(x: 1, y: 0.5)
        dotsMaskLayer.frame = bounds
        for (index, dot) in dots.enumerated() {
            dot.bounds = CGRect(x: 0, y: 0, width: dotDiameter, height: dotDiameter)
            dot.cornerRadius = dotDiameter / 2
            dot.position = CGPoint(
                x: dotDiameter / 2 + CGFloat(index) * (dotDiameter + dotSpacing),
                y: bounds.midY
            )
        }
    }

    func updateAppearance(fontSize: CGFloat, colors: [NSColor], isVertical: Bool, blurRadius: CGFloat) {
        dotDiameter = max(6, fontSize * 0.8)
        dotSpacing = max(3, dotDiameter * 0.45)
        self.isVertical = isVertical
        invalidateIntrinsicContentSize()
        needsLayout = true

        let visibleColors = colors.filter { $0.alphaComponent > 0 }
        let firstColor = visibleColors.first ?? .labelColor
        let lastColor = visibleColors.last ?? firstColor
        let targetColors = [firstColor.cgColor, lastColor.cgColor]
        let displayedColors = (colorLayer.presentation() as? CAGradientLayer)?.colors ?? colorLayer.colors
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        colorLayer.colors = targetColors
        CATransaction.commit()
        if let displayedColors, window != nil {
            let transition = CABasicAnimation(keyPath: "colors")
            transition.fromValue = displayedColors
            transition.toValue = targetColors
            transition.duration = 0.25
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            colorLayer.add(transition, forKey: "lineColorTransition")
        }

        let blurRadius = max(0, blurRadius)
        guard blurRadius > 0, let filter = CIFilter(name: "CIGaussianBlur") else {
            layer?.filters = []
            return
        }
        filter.setValue(blurRadius, forKey: kCIInputRadiusKey)
        layer?.filters = [filter]
    }

    func setActive(_ active: Bool, isPlaying: Bool) {
        guard active else {
            stopAnimating()
            return
        }
        if dots.first?.animation(forKey: Self.animationKey) == nil {
            startAnimating()
        }
        setAnimationsPlaying(isPlaying)
    }

    private func startAnimating() {
        for (index, dot) in dots.enumerated() {
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.keyTimes = [0, 0.35, 0.7, 1]
            scale.values = [0.72, 1, 0.72, 0.72]

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.keyTimes = scale.keyTimes
            opacity.values = [0.45, 1, 0.45, 0.45]

            let group = CAAnimationGroup()
            group.animations = [scale, opacity]
            group.duration = 1.5
            group.beginTime = dot.convertTime(CACurrentMediaTime(), from: nil) + Double(index) * 0.16
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dot.add(group, forKey: Self.animationKey)
        }
    }

    private func stopAnimating() {
        dots.forEach {
            $0.speed = 1
            $0.timeOffset = 0
            $0.beginTime = 0
            $0.removeAnimation(forKey: Self.animationKey)
        }
    }

    private func setAnimationsPlaying(_ isPlaying: Bool) {
        for dot in dots {
            if isPlaying, dot.speed == 0 {
                let pausedTime = dot.timeOffset
                dot.speed = 1
                dot.timeOffset = 0
                dot.beginTime = 0
                dot.beginTime = dot.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
            } else if !isPlaying, dot.speed != 0 {
                let pausedTime = dot.convertTime(CACurrentMediaTime(), from: nil)
                dot.speed = 0
                dot.timeOffset = pausedTime
            }
        }
    }
}

class KaraokeLyricsView: NSView {
    enum InterludePlacement: Equatable {
        case firstLine
        case secondLine
    }

    private let backgroundView: NSView
    private let backgroundContentView: NSView
    private let dynamicBackgroundView: LyricsDynamicBackgroundView
    private let albumArtworkView: NSView
    private let visualEffectView: NSVisualEffectView
    private let backgroundTintView: NSView
    private let stackView: NSStackView
    private let interludeDotsView: KaraokeInterludeDotsView
    private var currentInterludePlacement: InterludePlacement?
    private var exitingViewIDs = Set<ObjectIdentifier>()
    private let dragHandleView: KaraokeDragHandleView
    private let dragHandleFillLayer: CAGradientLayer

    var dragHandleMenuProvider: (() -> NSMenu?)? {
        didSet {
            dragHandleView.menuProvider = dragHandleMenuProvider
        }
    }

    @objc dynamic var theme = DesktopLyricsTheme.classic.rawValue {
        didSet { updateAppearance() }
    }

    @objc dynamic var isVertical = false {
        didSet {
            stackView.orientation = isVertical ? .horizontal : .vertical
            (isVertical ? displayLine2 : displayLine1).map { stackView.insertArrangedSubview($0, at: 0) }
            updateFontSize()
        }
    }

    @objc dynamic var drawFurigana = false
    @objc dynamic var drawRomajin = false

    @objc dynamic var font = NSFont.labelFont(ofSize: 24) { didSet { updateFontSize() } }
    @objc dynamic var textColor = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1) {
        didSet { updateInterludeDotsAppearance() }
    }
    @objc dynamic var shadowColor = #colorLiteral(red: 0, green: 1, blue: 0.8333333333, alpha: 1)
    @objc dynamic var progressColor = #colorLiteral(red: 0, green: 1, blue: 0.8333333333, alpha: 1) {
        didSet {
            refreshProgressColor()
            updateAppearance()
        }
    }
    var progressGradientColors: [NSColor]? {
        didSet {
            refreshProgressColor()
            updateDragHandleAppearance()
        }
    }
    var reversesProgressGradient = false {
        didSet { refreshProgressColor() }
    }
    var inactiveLineBlurRadius: CGFloat = 2 {
        didSet {
            updateLineAppearanceRoles()
            updateInterludeDotsAppearance()
        }
    }
    @objc dynamic var backgroundColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0.6018835616) {
        didSet {
            updateAppearance()
        }
    }
    @objc dynamic var modernBackgroundOpacity: CGFloat = 0.5 {
        didSet { updateAppearance() }
    }
    @objc dynamic var albumBlurDimAmount: CGFloat = 0.42 {
        didSet { updateAppearance() }
    }
    @objc dynamic var modernBlurEnabled = true {
        didSet { updateAppearance() }
    }
    @objc dynamic var modernCornerRadius: CGFloat = 16 {
        didSet { updateAppearance() }
    }
    var modernAlbumArtwork: CGImage? {
        didSet { updateAppearance() }
    }
    var amllDynamicColors: [NSColor]? {
        didSet { updateAppearance() }
    }
    @objc dynamic var amllDynamicDimAmount: CGFloat = 0.34 {
        didSet { updateAppearance() }
    }
    @objc dynamic var amllDynamicFlowSpeed: CGFloat = 0.9 {
        didSet { dynamicBackgroundView.flowSpeed = amllDynamicFlowSpeed }
    }
    @objc dynamic var amllDynamicIntensity: CGFloat = 0.72 {
        didSet { dynamicBackgroundView.intensity = amllDynamicIntensity }
    }

    @objc dynamic var shouldHideWithMouse = true {
        didSet {
            updateTrackingAreas()
        }
    }

    @objc dynamic var showsDragHandleWhenMouseHidden = false {
        didSet {
            mouseTest()
        }
    }

    var displayLine1: KaraokeLabel?
    var displayLine2: KaraokeLabel?

    override init(frame frameRect: NSRect) {
        self.stackView = NSStackView(frame: frameRect)
        self.interludeDotsView = KaraokeInterludeDotsView(frame: .zero)
        stackView.orientation = .vertical
        stackView.autoresizingMask = [.width, .height]
        stackView.wantsLayer = true
        self.dragHandleView = KaraokeDragHandleView(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        self.dragHandleFillLayer = CAGradientLayer()
        dragHandleView.wantsLayer = true
        dragHandleView.alphaValue = 0
        dragHandleView.isHidden = true
        self.backgroundView = NSView(frame: frameRect)
        backgroundView.autoresizingMask = [.width, .height]
        backgroundView.wantsLayer = true
        self.backgroundContentView = NSView(frame: frameRect)
        backgroundContentView.autoresizingMask = [.width, .height]
        backgroundContentView.wantsLayer = true
        self.dynamicBackgroundView = LyricsDynamicBackgroundView(frame: frameRect)
        dynamicBackgroundView.autoresizingMask = [.width, .height]
        self.albumArtworkView = NSView(frame: frameRect)
        albumArtworkView.autoresizingMask = [.width, .height]
        albumArtworkView.wantsLayer = true
        albumArtworkView.layer?.contentsGravity = .resizeAspectFill
        self.visualEffectView = NSVisualEffectView(frame: frameRect)
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        self.backgroundTintView = NSView(frame: frameRect)
        backgroundTintView.autoresizingMask = [.width, .height]
        backgroundTintView.wantsLayer = true
        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(backgroundView)
        backgroundView.addSubview(backgroundContentView)
        backgroundContentView.addSubview(dynamicBackgroundView)
        backgroundContentView.addSubview(albumArtworkView)
        backgroundContentView.addSubview(visualEffectView)
        backgroundContentView.addSubview(backgroundTintView)
        backgroundView.addSubview(stackView)
        addSubview(dragHandleView)
        dragHandleView.snp.makeConstraints {
            $0.center.equalToSuperview()
            $0.size.equalTo(CGSize(width: 22, height: 22))
        }
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateFontSize() {
        let usesCompactModernLayout = DesktopLyricsTheme(rawValue: theme)?.usesCompactModernLayout == true
        var insetX = usesCompactModernLayout ? max(20, font.pointSize * 0.66) : font.pointSize
        var insetY = usesCompactModernLayout ? 10 : insetX / 3
        if isVertical {
            (insetX, insetY) = (insetY, insetX)
        }
        stackView.snp.remakeConstraints {
            $0.edges.equalToSuperview().inset(NSEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX))
        }
        stackView.spacing = usesCompactModernLayout ? 6 : font.pointSize / 3
        updateInterludeDotsAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        let theme = DesktopLyricsTheme(rawValue: theme) ?? .classic
        let hasAlbumArtwork = theme == .albumBlur && modernAlbumArtwork != nil
        let usesDynamicBackground = theme == .amllDynamic
        let backgroundOpacity = theme.usesCompactModernLayout ? normalizedModernBackgroundOpacity : 1
        updateBackgroundLayerOrder(theme: theme)
        backgroundContentView.alphaValue = 1
        albumArtworkView.isHidden = !hasAlbumArtwork
        albumArtworkView.alphaValue = backgroundOpacity
        albumArtworkView.layer?.contents = modernAlbumArtwork
        dynamicBackgroundView.isHidden = !usesDynamicBackground
        dynamicBackgroundView.alphaValue = backgroundOpacity
        dynamicBackgroundView.colors = amllDynamicColors ?? [backgroundColor, progressColor]
        dynamicBackgroundView.fallbackColor = backgroundColor
        dynamicBackgroundView.dimAmount = amllDynamicDimAmount
        dynamicBackgroundView.flowSpeed = amllDynamicFlowSpeed
        dynamicBackgroundView.intensity = amllDynamicIntensity
        let usesVisualEffectBackground = shouldShowVisualEffectBackground(theme: theme, opacity: backgroundOpacity)
        visualEffectView.isHidden = !usesVisualEffectBackground
        visualEffectView.alphaValue = 1
        visualEffectView.blendingMode = theme == .albumBlur ? .withinWindow : .behindWindow
        backgroundTintView.layer?.backgroundColor = effectiveBackgroundColor(theme: theme, hasAlbumArtwork: hasAlbumArtwork).cgColor

        updateBackgroundCornerRadius(theme: theme)
        backgroundView.layer?.masksToBounds = true
        updateDragHandleAppearance()
        [albumArtworkView, visualEffectView, backgroundTintView].forEach {
            $0.layer?.cornerRadius = 0
            $0.layer?.masksToBounds = false
        }
    }

    private func updateBackgroundLayerOrder(theme: DesktopLyricsTheme) {
        let subviews = backgroundContentView.subviews
        guard let visualEffectIndex = subviews.firstIndex(where: { $0 === visualEffectView }),
              let dynamicBackgroundIndex = subviews.firstIndex(where: { $0 === dynamicBackgroundView }),
              let albumArtworkIndex = subviews.firstIndex(where: { $0 === albumArtworkView }),
              let backgroundTintIndex = subviews.firstIndex(where: { $0 === backgroundTintView }) else {
            return
        }

        if theme == .amllDynamic {
            guard visualEffectIndex > dynamicBackgroundIndex else { return }
            visualEffectView.removeFromSuperview()
            backgroundContentView.addSubview(visualEffectView, positioned: .below, relativeTo: dynamicBackgroundView)
        } else {
            guard visualEffectIndex < albumArtworkIndex || visualEffectIndex > backgroundTintIndex else { return }
            visualEffectView.removeFromSuperview()
            backgroundContentView.addSubview(visualEffectView, positioned: .above, relativeTo: albumArtworkView)
        }
    }

    private func updateDragHandleAppearance() {
        if dragHandleFillLayer.superlayer == nil {
            dragHandleView.layer?.insertSublayer(dragHandleFillLayer, at: 0)
        }

        dragHandleView.layer?.cornerRadius = 11
        dragHandleView.layer?.masksToBounds = false
        dragHandleView.layer?.backgroundColor = NSColor.clear.cgColor
        dragHandleView.layer?.borderWidth = 0
        dragHandleView.layer?.borderColor = NSColor.clear.cgColor
        dragHandleView.layer?.shadowOpacity = 0
        dragHandleView.layer?.shadowRadius = 0
        dragHandleView.layer?.shadowOffset = .zero

        var fillColors: [NSColor] = []
        if let progressGradientColors {
            for color in progressGradientColors where color.alphaComponent > 0 {
                fillColors.append(color)
            }
        }
        if fillColors.isEmpty {
            fillColors.append(progressColor)
        }
        if fillColors.count == 1, let color = fillColors.first {
            fillColors.append(color)
        }
        let fillCGColors: [CGColor] = fillColors.map { color in
            color.withAlphaComponent(0.95).cgColor
        }
        dragHandleFillLayer.colors = fillCGColors
        dragHandleFillLayer.startPoint = CGPoint(x: 0, y: 0.5)
        dragHandleFillLayer.endPoint = CGPoint(x: 1, y: 0.5)
        dragHandleFillLayer.cornerRadius = 11
        dragHandleFillLayer.masksToBounds = true
        dragHandleFillLayer.frame = dragHandleView.bounds
    }

    private func effectiveBackgroundColor(theme: DesktopLyricsTheme, hasAlbumArtwork: Bool) -> NSColor {
        if theme == .albumBlur, hasAlbumArtwork {
            return backgroundColor.withAlphaComponent(albumBlurDimAmount * normalizedModernBackgroundOpacity)
        } else if theme == .amllDynamic {
            return backgroundColor.withAlphaComponent(amllDynamicDimAmount * normalizedModernBackgroundOpacity)
        } else if theme.usesCompactModernLayout {
            return backgroundColor.withAlphaComponent(normalizedModernBackgroundOpacity)
        }
        return backgroundColor
    }

    private func shouldShowVisualEffectBackground(theme: DesktopLyricsTheme, opacity: CGFloat) -> Bool {
        guard opacity > 0 else {
            return false
        }

        switch theme {
        case .modern:
            return modernBlurEnabled
        case .albumBlur, .amllDynamic:
            return true
        case .classic:
            return false
        }
    }

    private var normalizedModernBackgroundOpacity: CGFloat {
        modernBackgroundOpacity.clamped(to: 0...1)
    }

    private func lyricsLabel(_ content: String) -> KaraokeLabel {
        if let view = stackView.subviews.lazy.compactMap({ $0 as? KaraokeLabel }).first(where: {
            !stackView.arrangedSubviews.contains($0)
                && !exitingViewIDs.contains(ObjectIdentifier($0))
        }) {
            view.isHidden = false
            view.alphaValue = 0
            view.stringValue = content
            view.removeProgressAnimation()
            view.removeFromSuperview()
            applyProgressAppearance(to: view)
            return view
        }
        return KaraokeLabel(labelWithString: content).then {
            $0.bind(\.font, to: self, withKeyPath: \.font)
            $0.bind(\.textColor, to: self, withKeyPath: \.textColor)
            $0.bind(\.progressColor, to: self, withKeyPath: \.progressColor)
            $0.bind(\._shadowColor, to: self, withKeyPath: \.shadowColor)
            $0.bind(\.isVertical, to: self, withKeyPath: \.isVertical)
            $0.bind(\.drawFurigana, to: self, withKeyPath: \.drawFurigana)
            $0.bind(\.drawRomajin, to: self, withKeyPath: \.drawRomajin)
            applyProgressAppearance(to: $0)
            $0.alphaValue = 0
        }
    }

    func displayLrc(
        _ firstLine: String,
        secondLine: String = "",
        interludePlacement: InterludePlacement? = nil,
        isPlaying: Bool = true
    ) {
        let contentChanged = displayLine1?.stringValue != firstLine
            || displayLine2?.stringValue != secondLine
            || currentInterludePlacement != interludePlacement
        currentInterludePlacement = interludePlacement
        let currentViews = stackView.arrangedSubviews
        let currentLabels = currentViews.compactMap { $0 as? KaraokeLabel }
        var usedLabels = Set<ObjectIdentifier>()

        func reusableLabel(for content: String) -> KaraokeLabel {
            if let label = currentLabels.first(where: {
                $0.stringValue == content && !usedLabels.contains(ObjectIdentifier($0))
            }) {
                usedLabels.insert(ObjectIdentifier(label))
                return label
            }
            let label = lyricsLabel(content)
            usedLabels.insert(ObjectIdentifier(label))
            return label
        }

        var semanticViews: [NSView] = []
        if interludePlacement == .firstLine {
            displayLine1 = nil
            semanticViews.append(interludeDotsView)
        } else if !firstLine.trimmingCharacters(in: .whitespaces).isEmpty {
            let label = reusableLabel(for: firstLine)
            displayLine1 = label
            semanticViews.append(label)
        } else {
            displayLine1 = nil
        }

        if interludePlacement == .secondLine {
            displayLine2 = nil
            semanticViews.append(interludeDotsView)
        } else if !secondLine.trimmingCharacters(in: .whitespaces).isEmpty {
            let label = reusableLabel(for: secondLine)
            displayLine2 = label
            semanticViews.append(label)
        } else {
            displayLine2 = nil
        }

        let desiredViews = isVertical ? Array(semanticViews.reversed()) : semanticViews
        let desiredIDs = Set(desiredViews.map(ObjectIdentifier.init))
        let currentIDs = currentViews.map(ObjectIdentifier.init)
        let desiredViewIDs = desiredViews.map(ObjectIdentifier.init)

        updateInterludeDotsAppearance()
        if contentChanged, DesktopLyricsTheme(rawValue: theme) == .amllDynamic {
            dynamicBackgroundView.pulseForLyricChange(strength: amllDynamicIntensity)
        }
        if currentIDs == desiredViewIDs {
            desiredViews.forEach {
                $0.isHidden = false
                $0.alphaValue = 1
            }
            interludeDotsView.setActive(interludePlacement != nil, isPlaying: isPlaying)
            isHidden = desiredViews.isEmpty
            updateLineAppearanceRoles()
            return
        }

        let toBeHide = currentViews.filter { !desiredIDs.contains(ObjectIdentifier($0)) }
        let toBeShow = desiredViews.filter { !currentIDs.contains(ObjectIdentifier($0)) }
        let oldFrames = Dictionary(uniqueKeysWithValues: currentViews.map {
            (ObjectIdentifier($0), $0.frame)
        })

        desiredViews.forEach {
            let id = ObjectIdentifier($0)
            exitingViewIDs.remove(id)
            $0.wantsLayer = true
            $0.layer?.removeAnimation(forKey: "lineTransition")
            $0.layer?.removeAnimation(forKey: "lineExit")
            $0.isHidden = false
            $0.alphaValue = 1
        }

        currentViews.forEach { stackView.removeArrangedSubview($0) }
        desiredViews.forEach { stackView.addArrangedSubview($0) }
        isHidden = desiredViews.isEmpty
        layoutSubtreeIfNeeded()
        updateLineAppearanceRoles()

        for view in toBeHide {
            animateLineExit(view)
        }
        for (index, view) in desiredViews.enumerated() {
            if let oldFrame = oldFrames[ObjectIdentifier(view)] {
                animateLineMove(view, from: oldFrame, delay: Double(index) * 0.035)
            } else if toBeShow.contains(where: { $0 === view }) {
                animateLineEntrance(view, delay: Double(index) * 0.06)
            }
        }

        interludeDotsView.setActive(interludePlacement != nil, isPlaying: isPlaying)
        mouseTest()
    }

    private func animateLineExit(_ view: NSView) {
        let id = ObjectIdentifier(view)
        exitingViewIDs.insert(id)
        view.wantsLayer = true
        guard let layer = view.layer else {
            finishLineExit(view, id: id)
            return
        }

        view.isHidden = false
        view.alphaValue = 1
        let distance = max(12, font.pointSize * 0.55)
        layer.add(
            lineTransitionAnimation(
                translationFromX: 0,
                translationFromY: 0,
                translationToX: 0,
                translationToY: distance,
                opacityFrom: 1,
                opacityTo: 0,
                delay: 0,
                duration: 0.2,
                holdsFinalState: true,
                timingFunction: CAMediaTimingFunction(name: .easeIn)
            ),
            forKey: "lineExit"
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak view] in
            guard let self, let view else { return }
            self.finishLineExit(view, id: id)
        }
    }

    private func finishLineExit(_ view: NSView, id: ObjectIdentifier) {
        guard exitingViewIDs.remove(id) != nil else { return }
        view.isHidden = true
        view.alphaValue = 0
        view.layer?.removeAnimation(forKey: "lineExit")
        (view as? KaraokeLabel)?.removeProgressAnimation()
    }

    private func animateLineMove(_ view: NSView, from oldFrame: NSRect, delay: TimeInterval) {
        let translationX = oldFrame.midX - view.frame.midX
        let translationY = oldFrame.midY - view.frame.midY
        guard abs(translationX) > 0.5 || abs(translationY) > 0.5 else { return }
        view.layer?.add(
            lineTransitionAnimation(
                translationFromX: translationX,
                translationFromY: translationY,
                opacityFrom: 1,
                opacityTo: 1,
                delay: delay,
                duration: 0.25,
                timingFunction: CAMediaTimingFunction(name: .easeInEaseOut)
            ),
            forKey: "lineTransition"
        )
    }

    private func animateLineEntrance(_ view: NSView, delay: TimeInterval) {
        view.layer?.add(
            lineTransitionAnimation(
                translationFromX: 0,
                translationFromY: -max(12, font.pointSize * 0.55),
                opacityFrom: 0,
                opacityTo: 1,
                delay: delay,
                duration: 0.24,
                timingFunction: CAMediaTimingFunction(name: .easeOut)
            ),
            forKey: "lineTransition"
        )
    }

    private func lineTransitionAnimation(
        translationFromX: CGFloat,
        translationFromY: CGFloat,
        translationToX: CGFloat = 0,
        translationToY: CGFloat = 0,
        opacityFrom: Float,
        opacityTo: Float,
        delay: TimeInterval,
        duration: TimeInterval,
        holdsFinalState: Bool = false,
        timingFunction: CAMediaTimingFunction
    ) -> CAAnimationGroup {
        let x = CABasicAnimation(keyPath: "transform.translation.x")
        x.fromValue = translationFromX
        x.toValue = translationToX
        x.timingFunction = timingFunction

        let y = CABasicAnimation(keyPath: "transform.translation.y")
        y.fromValue = translationFromY
        y.toValue = translationToY
        y.timingFunction = timingFunction

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = opacityFrom
        opacity.toValue = opacityTo
        opacity.timingFunction = timingFunction

        let animation = CAAnimationGroup()
        animation.animations = [x, y, opacity]
        animation.beginTime = CACurrentMediaTime() + delay
        animation.duration = duration
        animation.fillMode = holdsFinalState ? .both : .backwards
        animation.isRemovedOnCompletion = !holdsFinalState
        return animation
    }

    func refreshProgressColor() {
        displayLine1.map(applyProgressAppearance(to:))
        displayLine2.map(applyProgressAppearance(to:))
        updateLineAppearanceRoles()
        updateInterludeDotsAppearance()
        updateDragHandleAppearance()
    }

    override func layout() {
        super.layout()
        updateBackgroundCornerRadius()
        dragHandleFillLayer.frame = dragHandleView.bounds
    }

    private func updateBackgroundCornerRadius(theme: DesktopLyricsTheme? = nil) {
        let theme = theme ?? (DesktopLyricsTheme(rawValue: self.theme) ?? .classic)
        let requestedRadius = theme.usesCompactModernLayout ? modernCornerRadius : font.pointSize / 2
        backgroundView.layer?.cornerRadius = cappedCornerRadius(requestedRadius, for: backgroundView)
    }

    private func cappedCornerRadius(_ radius: CGFloat, for view: NSView) -> CGFloat {
        let width = view.bounds.width > 0 ? view.bounds.width : view.frame.width
        let height = view.bounds.height > 0 ? view.bounds.height : view.frame.height
        guard width > 0, height > 0 else {
            return max(0, radius)
        }
        return min(max(0, radius), min(width, height) / 2)
    }

    private func applyProgressAppearance(to label: KaraokeLabel) {
        label.progressColor = progressColor
        label.progressGradientColors = progressGradientColors
        label.reversesProgressGradient = reversesProgressGradient
    }

    private func updateInterludeDotsAppearance() {
        let gradientColors = progressGradientColors?.filter { $0.alphaComponent > 0 } ?? []
        let activeColors = gradientColors.isEmpty ? [progressColor] : gradientColors
        let orderedActiveColors = reversesProgressGradient ? Array(activeColors.reversed()) : activeColors
        let usesProgressColors = currentInterludePlacement == .firstLine
            || (currentInterludePlacement == .secondLine && reversesProgressGradient)
        interludeDotsView.updateAppearance(
            fontSize: font.pointSize,
            colors: usesProgressColors ? orderedActiveColors : [textColor],
            isVertical: isVertical,
            blurRadius: currentInterludePlacement == .secondLine ? inactiveLineBlurRadius : 0
        )
    }

    private func updateLineAppearanceRoles() {
        displayLine1?.setDisplaysProgressGradientAsBase(false)
        displayLine1?.setTextBlurRadius(0)
        displayLine2?.setDisplaysProgressGradientAsBase(reversesProgressGradient)
        displayLine2?.setTextBlurRadius(inactiveLineBlurRadius)
    }

    // MARK: - Event

    private var trackingArea: NSTrackingArea?

    private var isHiddenByMouse = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingArea.map(removeTrackingArea)
        if shouldHideWithMouse {
            let trackingOptions: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .assumeInside]
            trackingArea = NSTrackingArea(rect: bounds, options: trackingOptions, owner: self)
            trackingArea.map(addTrackingArea)
        }
        mouseTest()
    }

    private func mouseTest() {
        if shouldHideWithMouse,
           let point = NSEvent.mouseLocation(in: self),
           bounds.contains(point) {
            setHiddenByMouse(true)
        } else {
            setHiddenByMouse(false)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        setHiddenByMouse(true)
    }

    override func mouseEntered(with event: NSEvent) {
        setHiddenByMouse(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHiddenByMouse(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isHiddenByMouse, showsDragHandleWhenMouseHidden else {
            return super.hitTest(point)
        }
        return dragHandleView.frame.contains(point) ? super.hitTest(point) : nil
    }

    override func rightMouseDown(with event: NSEvent) {
        guard popDragHandleMenuIfNeeded(with: event) else {
            super.rightMouseDown(with: event)
            return
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard shouldShowDragHandleMenu(for: event) else {
            return super.menu(for: event)
        }
        return dragHandleMenuProvider?().map { $0.detachedContextMenu() } ?? super.menu(for: event)
    }

    @discardableResult
    func popDragHandleMenuIfNeeded(with event: NSEvent) -> Bool {
        guard shouldShowDragHandleMenu(for: event),
              let menu = dragHandleMenuProvider?() else {
            return false
        }
        popDetachedMenu(from: menu, at: convert(event.locationInWindow, from: nil))
        return true
    }

    private func shouldShowDragHandleMenu(for event: NSEvent) -> Bool {
        guard showsDragHandleWhenMouseHidden,
              !dragHandleView.isHidden,
              dragHandleView.alphaValue > 0.01 else {
            return false
        }
        let point = convert(event.locationInWindow, from: nil)
        return dragHandleView.frame.contains(point)
    }

    private func setHiddenByMouse(_ hidden: Bool) {
        guard shouldHideWithMouse else {
            isHiddenByMouse = false
            alphaValue = 1
            backgroundView.alphaValue = 1
            dragHandleView.alphaValue = 0
            dragHandleView.isHidden = true
            return
        }

        isHiddenByMouse = hidden
        if hidden, showsDragHandleWhenMouseHidden {
            alphaValue = 1
            backgroundView.animator().alphaValue = 0
            dragHandleView.isHidden = false
            dragHandleView.animator().alphaValue = 1
        } else if hidden {
            dragHandleView.animator().alphaValue = 0
            dragHandleView.isHidden = true
            backgroundView.alphaValue = 1
            animator().alphaValue = 0
        } else {
            animator().alphaValue = 1
            backgroundView.animator().alphaValue = 1
            dragHandleView.animator().alphaValue = 0
            dragHandleView.isHidden = true
        }
    }
}

private extension NSView {
    func popDetachedMenu(from menu: NSMenu, at point: NSPoint) {
        let detachedMenu = menu.detachedContextMenu()
        detachedMenu.popUp(positioning: nil, at: point, in: self)
    }
}

private extension NSMenu {
    func detachedContextMenu() -> NSMenu {
        update()

        let menu = NSMenu(title: title)
        menu.autoenablesItems = autoenablesItems
        menu.delegate = delegate
        for item in items {
            if let copiedItem = item.copy() as? NSMenuItem {
                menu.addItem(copiedItem)
            }
        }
        return menu
    }
}

private extension DesktopLyricsTheme {
    var usesCompactModernLayout: Bool {
        switch self {
        case .classic:
            return false
        case .modern, .albumBlur, .amllDynamic:
            return true
        }
    }
}

extension NSEvent {
    class func mouseLocation(in view: NSView) -> NSPoint? {
        guard let window = view.window else { return nil }
        let windowLocation = window.convertFromScreen(NSRect(origin: NSEvent.mouseLocation, size: .zero)).origin
        return view.convert(windowLocation, from: nil)
    }
}

extension NSTextField {
    // swiftlint:disable:next identifier_name
    @objc dynamic var _shadowColor: NSColor? {
        get {
            return shadow?.shadowColor
        }
        set {
            shadow = newValue.map { color in
                NSShadow().then {
                    $0.shadowBlurRadius = 3
                    $0.shadowColor = color
                    $0.shadowOffset = .zero
                }
            }
        }
    }
}
