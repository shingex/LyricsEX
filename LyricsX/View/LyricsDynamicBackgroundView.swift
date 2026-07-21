import AppKit

final class LyricsDynamicBackgroundView: NSView {
    private struct AnimationConfiguration: Equatable {
        let size: CGSize
        let flowSpeed: CGFloat
        let intensity: CGFloat
    }

    private let baseGradientLayer = CAGradientLayer()
    private let accentGradientLayer = CAGradientLayer()
    private let highlightGradientLayer = CAGradientLayer()
    private var animationConfiguration: AnimationConfiguration?

    var colors: [NSColor] = [] {
        didSet { updatePalette() }
    }

    var fallbackColor: NSColor = desktopLyricsAMLLDynamicDefaultFallbackColor {
        didSet { updatePalette() }
    }

    var dimAmount: CGFloat = 0.34 {
        didSet { updatePalette() }
    }

    var intensity: CGFloat = 0.72 {
        didSet {
            updatePalette()
            updateAnimations()
        }
    }

    var flowSpeed: CGFloat = 0.9 {
        didSet { updateAnimations() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        [baseGradientLayer, accentGradientLayer, highlightGradientLayer].forEach {
            $0.needsDisplayOnBoundsChange = true
            layer?.addSublayer($0)
        }
        accentGradientLayer.type = .radial
        highlightGradientLayer.type = .radial

        updatePalette()
        updateAnimations()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateFrames()
        updateAnimations()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window == nil ? stopAnimations() : updateAnimations()
    }

    override var isHidden: Bool {
        didSet {
            isHidden ? stopAnimations() : updateAnimations()
        }
    }

    func pulseForLyricChange(strength: CGFloat) {
        guard window != nil, !isHidden, !bounds.isEmpty else {
            return
        }
        let normalizedStrength = min(1, max(0.15, strength))
        addPulseAnimation(
            to: accentGradientLayer,
            key: "accentLyricPulse",
            scale: 1 + normalizedStrength * 0.1,
            opacity: min(0.95, CGFloat(accentGradientLayer.opacity) + normalizedStrength * 0.16)
        )
        addPulseAnimation(
            to: highlightGradientLayer,
            key: "highlightLyricPulse",
            scale: 1 + normalizedStrength * 0.16,
            opacity: min(0.88, CGFloat(highlightGradientLayer.opacity) + normalizedStrength * 0.18)
        )
    }

    private func updateFrames() {
        baseGradientLayer.frame = bounds
        let inset = -max(bounds.width, bounds.height) * 0.36
        let extendedBounds = bounds.insetBy(dx: inset, dy: inset)
        accentGradientLayer.frame = extendedBounds
        highlightGradientLayer.frame = extendedBounds
        accentGradientLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        highlightGradientLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    private func updatePalette() {
        let palette = normalizedPalette()
        let base = palette[0]
        let accent = palette[1]
        let highlight = palette[2]
        let shadow = palette[3]

        baseGradientLayer.startPoint = CGPoint(x: 0.08, y: 0.12)
        baseGradientLayer.endPoint = CGPoint(x: 0.92, y: 0.88)
        baseGradientLayer.locations = [0, 0.38, 0.72, 1]
        baseGradientLayer.colors = [
            shadow.withBrightnessMultiplier(0.7).cgColor,
            base.withSaturationMultiplier(1.25).cgColor,
            accent.withSaturationMultiplier(1.18).cgColor,
            shadow.withAlphaComponent(1).cgColor,
        ]

        let accentAlpha = min(0.82, max(0.18, intensity))
        accentGradientLayer.startPoint = CGPoint(x: 0.18, y: 0.2)
        accentGradientLayer.endPoint = CGPoint(x: 0.78, y: 0.82)
        accentGradientLayer.locations = [0, 0.42, 1]
        accentGradientLayer.opacity = Float(accentAlpha)
        accentGradientLayer.colors = [
            highlight.withAlphaComponent(0.85).cgColor,
            accent.withAlphaComponent(0.42).cgColor,
            shadow.withAlphaComponent(0).cgColor,
        ]

        highlightGradientLayer.startPoint = CGPoint(x: 0.74, y: 0.18)
        highlightGradientLayer.endPoint = CGPoint(x: 0.26, y: 0.9)
        highlightGradientLayer.locations = [0, 0.5, 1]
        highlightGradientLayer.opacity = Float(min(0.7, max(0.12, intensity * 0.72)))
        highlightGradientLayer.colors = [
            base.withBrightnessMultiplier(1.2).withAlphaComponent(0.68).cgColor,
            highlight.withAlphaComponent(0.28).cgColor,
            shadow.withAlphaComponent(0).cgColor,
        ]

        layer?.backgroundColor = shadow.withAlphaComponent(max(0.1, dimAmount)).cgColor
    }

    private func normalizedPalette() -> [NSColor] {
        let source = colors.isEmpty ? [fallbackColor, desktopLyricsAMLLDynamicDefaultProgressColor] : colors
        var result = source.compactMap { $0.usingColorSpace(.deviceRGB) }
        if result.isEmpty {
            result = [desktopLyricsAMLLDynamicDefaultFallbackColor, desktopLyricsAMLLDynamicDefaultProgressColor]
        }
        while result.count < 4 {
            result.append(result.last?.shiftedHue(by: 0.18) ?? desktopLyricsAMLLDynamicDefaultProgressColor)
        }
        return Array(result.prefix(4))
    }

    private func updateAnimations() {
        guard window != nil, !isHidden, !bounds.isEmpty, flowSpeed > 0.05 else {
            stopAnimations()
            return
        }

        let configuration = AnimationConfiguration(
            size: bounds.size,
            flowSpeed: flowSpeed,
            intensity: intensity
        )
        guard animationConfiguration != configuration || !hasCompleteFlowAnimations else {
            return
        }

        stopAnimations()
        animationConfiguration = configuration
        addBaseFlowAnimation(duration: max(3, 6 / Double(flowSpeed)))
        addMotionAnimation(to: accentGradientLayer, key: "accentPositionFlow", duration: max(3.25, 6.5 / Double(flowSpeed)), phase: 0)
        addMotionAnimation(to: highlightGradientLayer, key: "highlightPositionFlow", duration: max(4, 8 / Double(flowSpeed)), phase: CGFloat.pi)
        addScaleAnimation(to: accentGradientLayer, key: "accentScaleFlow", duration: max(3, 5.5 / Double(flowSpeed)), from: 0.9, to: 1.2)
        addScaleAnimation(to: highlightGradientLayer, key: "highlightScaleFlow", duration: max(3.5, 6.5 / Double(flowSpeed)), from: 1.18, to: 0.86)
        addOpacityAnimation(to: accentGradientLayer, key: "accentOpacityFlow", duration: max(2.5, 4.5 / Double(flowSpeed)), base: CGFloat(accentGradientLayer.opacity))
        addOpacityAnimation(to: highlightGradientLayer, key: "highlightOpacityFlow", duration: max(3, 5.5 / Double(flowSpeed)), base: CGFloat(highlightGradientLayer.opacity))
    }

    private func stopAnimations() {
        [baseGradientLayer, accentGradientLayer, highlightGradientLayer].forEach { $0.removeAllAnimations() }
        animationConfiguration = nil
    }

    private var hasCompleteFlowAnimations: Bool {
        return baseGradientLayer.animation(forKey: "baseStartFlow") != nil
            && baseGradientLayer.animation(forKey: "baseEndFlow") != nil
            && baseGradientLayer.animation(forKey: "baseLocationsFlow") != nil
            && accentGradientLayer.animation(forKey: "accentPositionFlow") != nil
            && accentGradientLayer.animation(forKey: "accentScaleFlow") != nil
            && accentGradientLayer.animation(forKey: "accentOpacityFlow") != nil
            && highlightGradientLayer.animation(forKey: "highlightPositionFlow") != nil
            && highlightGradientLayer.animation(forKey: "highlightScaleFlow") != nil
            && highlightGradientLayer.animation(forKey: "highlightOpacityFlow") != nil
    }

    private func addBaseFlowAnimation(duration: Double) {
        let startAnimation = CABasicAnimation(keyPath: "startPoint")
        startAnimation.fromValue = CGPoint(x: 0.04, y: 0.12)
        startAnimation.toValue = CGPoint(x: 0.38, y: -0.02)

        let endAnimation = CABasicAnimation(keyPath: "endPoint")
        endAnimation.fromValue = CGPoint(x: 0.94, y: 0.9)
        endAnimation.toValue = CGPoint(x: 0.62, y: 1.02)

        let locationsAnimation = CABasicAnimation(keyPath: "locations")
        locationsAnimation.fromValue = [0, 0.32, 0.66, 1]
        locationsAnimation.toValue = [0, 0.5, 0.86, 1]

        [("baseStartFlow", startAnimation), ("baseEndFlow", endAnimation), ("baseLocationsFlow", locationsAnimation)].forEach { key, animation in
            animation.duration = max(6, duration)
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.isRemovedOnCompletion = false
            baseGradientLayer.add(animation, forKey: key)
        }
    }

    private func addMotionAnimation(to layer: CALayer, key: String, duration: Double, phase: CGFloat) {
        let normalizedIntensity = intensity.clamped(to: 0...1)
        let radiusX = max(bounds.width * (0.18 + normalizedIntensity * 0.28), 28)
        let radiusY = max(bounds.height * (0.16 + normalizedIntensity * 0.22), 24)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: center.x + cos(phase) * radiusX, y: center.y + sin(phase) * radiusY))
        path.addCurve(
            to: CGPoint(x: center.x - cos(phase) * radiusX, y: center.y - sin(phase) * radiusY),
            control1: CGPoint(x: center.x + radiusX * 0.85, y: center.y - radiusY * 1.2),
            control2: CGPoint(x: center.x - radiusX * 1.1, y: center.y + radiusY * 0.9)
        )
        path.addCurve(
            to: CGPoint(x: center.x + cos(phase) * radiusX, y: center.y + sin(phase) * radiusY),
            control1: CGPoint(x: center.x - radiusX * 0.85, y: center.y - radiusY * 1.15),
            control2: CGPoint(x: center.x + radiusX * 1.1, y: center.y + radiusY * 1.05)
        )

        let animation = CAKeyframeAnimation(keyPath: "position")
        animation.path = path
        animation.duration = max(8, duration)
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: key)
    }

    private func addScaleAnimation(to layer: CALayer, key: String, duration: Double, from: CGFloat, to: CGFloat) {
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = max(6, duration)
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: key)
    }

    private func addOpacityAnimation(to layer: CALayer, key: String, duration: Double, base: CGFloat) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = max(0.08, base * 0.64)
        animation.toValue = min(0.92, base * 1.18)
        animation.duration = max(6, duration)
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: key)
    }

    private func addPulseAnimation(to layer: CALayer, key: String, scale: CGFloat, opacity: CGFloat) {
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = scale
        scaleAnimation.toValue = layer.presentation()?.value(forKeyPath: "transform.scale") ?? 1
        scaleAnimation.duration = 0.72
        scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = opacity
        opacityAnimation.toValue = layer.presentation()?.opacity ?? layer.opacity
        opacityAnimation.duration = 0.72
        opacityAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let group = CAAnimationGroup()
        group.animations = [scaleAnimation, opacityAnimation]
        group.duration = 0.72
        group.isRemovedOnCompletion = true
        layer.add(group, forKey: key)
    }
}

private extension NSColor {
    func withSaturationMultiplier(_ multiplier: CGFloat) -> NSColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        usingColorSpace(.deviceRGB)?.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(
            hue: hue,
            saturation: min(1, max(0, saturation * multiplier)),
            brightness: brightness,
            alpha: alpha
        )
    }

    func withBrightnessMultiplier(_ multiplier: CGFloat) -> NSColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        usingColorSpace(.deviceRGB)?.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(
            hue: hue,
            saturation: saturation,
            brightness: min(1, max(0, brightness * multiplier)),
            alpha: alpha
        )
    }

    func shiftedHue(by amount: CGFloat) -> NSColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        usingColorSpace(.deviceRGB)?.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(
            hue: (hue + amount).truncatingRemainder(dividingBy: 1),
            saturation: min(0.9, max(0.35, saturation * 1.12)),
            brightness: min(0.82, max(0.28, brightness * 1.05)),
            alpha: alpha
        )
    }
}
