import AppKit

class PreferenceLyricsWindowThemeViewController: PreferenceViewController, FontSelectTextFieldDelegate {
    private let classicThemeButton = NSButton(frame: .zero)
    private let amllOriginalSourceThemeButton = NSButton(frame: .zero)
    private let classicPanel = NSStackView()
    private let webViewPanel = NSStackView()

    private let classicFontField = FontSelectTextField(frame: .zero)
    private let classicTextWell = NSColorWell(frame: .zero)
    private let classicHighlightWell = NSColorWell(frame: .zero)

    private let webViewFontField = FontSelectTextField(frame: .zero)
    private let webViewAlignmentControl = NSSegmentedControl(frame: .zero)
    private let webViewLineSpacingSlider = NSSlider(value: 100, minValue: 70, maxValue: 160, target: nil, action: nil)
    private let webViewLineSpacingLabel = NSTextField(labelWithString: "")
    private let webViewMotionSlider = NSSlider(value: 100, minValue: 0, maxValue: 150, target: nil, action: nil)
    private let webViewMotionLabel = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 420))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = preferenceLocalized("Lyrics Window")
        setupViews()
        reloadControls()
    }

    private func setupViews() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .centerX
        root.spacing = 24
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])

        configureThemeButton(classicThemeButton, title: preferenceLocalized("Classic"), theme: .classic, image: themePreviewImage(theme: .classic))
        configureThemeButton(amllOriginalSourceThemeButton, title: preferenceLocalized("AMLL Original Source"), theme: .amllOriginalSource, image: themePreviewImage(theme: .amllOriginalSource))

        let themeList = NSStackView(views: [classicThemeButton, amllOriginalSourceThemeButton])
        themeList.orientation = .horizontal
        themeList.alignment = .top
        themeList.spacing = 14
        root.addArrangedSubview(themeList)

        setupClassicPanel()
        setupWebViewPanel()

        root.addArrangedSubview(classicPanel)
        root.addArrangedSubview(webViewPanel)
    }

    private func configureThemeButton(_ button: NSButton, title: String, theme: LyricsWindowTheme, image: NSImage) {
        button.title = title
        button.image = image
        button.imagePosition = .imageAbove
        button.imageScaling = .scaleProportionallyUpOrDown
        button.alignment = .center
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.tag = theme.rawValue
        button.target = self
        button.action = #selector(themeChanged(_:))
        button.wantsLayer = true
        button.layer?.cornerRadius = 10
        button.layer?.borderWidth = 1
        button.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 200),
            button.heightAnchor.constraint(equalToConstant: 120),
        ])
    }

    private func themePreviewImage(theme: LyricsWindowTheme) -> NSImage {
        let size = NSSize(width: 178, height: 68)
        return NSImage(size: size, flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()

            let backgroundRect = NSRect(x: 12, y: 10, width: 154, height: 48)
            switch theme {
            case .classic:
                let background = NSBezierPath(roundedRect: backgroundRect, xRadius: 10, yRadius: 10)
                NSColor(calibratedWhite: 0.55, alpha: 0.9).setFill()
                background.fill()
                Self.drawCenteredPreviewLines(in: backgroundRect)
            case .amllOriginalSource:
                let background = NSBezierPath(roundedRect: backgroundRect, xRadius: 14, yRadius: 14)
                background.addClip()
                NSGradient(colors: [
                    NSColor(calibratedRed: 1, green: 0.27, blue: 0.42, alpha: 1),
                    NSColor(calibratedRed: 0.18, green: 0.48, blue: 1, alpha: 1),
                    NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.18, alpha: 1),
                ])?.draw(in: backgroundRect, angle: 24)
                NSColor.black.withAlphaComponent(0.28).setFill()
                background.fill()
                Self.drawLeftPreviewLines(in: backgroundRect)
            }

            return true
        }
    }

    private static func drawCenteredPreviewLines(in rect: NSRect) {
        let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let lines = [
            ("原来爱是离我那么的近", NSColor(calibratedWhite: 0.78, alpha: 1)),
            ("大口呼吸 害怕浪费空气中的甜蜜", NSColor(calibratedRed: 0.86, green: 1, blue: 0.74, alpha: 1)),
            ("你就是我的福地", NSColor(calibratedWhite: 0.78, alpha: 1)),
        ]
        for (offset, line) in lines.enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: line.1,
            ]
            let size = line.0.size(withAttributes: attributes)
            line.0.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.maxY - 18 - CGFloat(offset * 14)), withAttributes: attributes)
        }
    }

    private static func drawLeftPreviewLines(in rect: NSRect) {
        let lines = [
            ("原来爱是离我那么的近", NSColor.white.withAlphaComponent(0.26), NSFont.systemFont(ofSize: 8, weight: .semibold)),
            ("大口呼吸 害怕浪费空气中的甜蜜", NSColor.white, NSFont.systemFont(ofSize: 11, weight: .bold)),
            ("你就是我的福地", NSColor.white.withAlphaComponent(0.34), NSFont.systemFont(ofSize: 8, weight: .semibold)),
        ]
        for (offset, line) in lines.enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: line.2,
                .foregroundColor: line.1,
            ]
            line.0.draw(at: NSPoint(x: rect.minX + 18, y: rect.maxY - 16 - CGFloat(offset * 14)), withAttributes: attributes)
        }
    }

    private func setupClassicPanel() {
        configurePanel(classicPanel)

        classicFontField.fontChangeDelegate = self
        classicPanel.addArrangedSubview(row(label: preferenceLocalized("Font:"), control: classicFontField))

        classicTextWell.target = self
        classicTextWell.action = #selector(classicColorChanged(_:))
        classicHighlightWell.target = self
        classicHighlightWell.action = #selector(classicColorChanged(_:))
        classicPanel.addArrangedSubview(colorGrid([
            (preferenceLocalized("Lyrics"), classicTextWell),
            (preferenceLocalized("Highlight"), classicHighlightWell),
        ]))
    }

    private func setupWebViewPanel() {
        configurePanel(webViewPanel)

        webViewFontField.fontChangeDelegate = self
        webViewPanel.addArrangedSubview(row(label: preferenceLocalized("Font:"), control: webViewFontField))

        webViewAlignmentControl.segmentCount = 2
        webViewAlignmentControl.setLabel(preferenceLocalized("Left"), forSegment: 0)
        webViewAlignmentControl.setLabel(preferenceLocalized("Center"), forSegment: 1)
        webViewAlignmentControl.trackingMode = .selectOne
        webViewAlignmentControl.target = self
        webViewAlignmentControl.action = #selector(webViewAlignmentChanged(_:))
        webViewAlignmentControl.widthAnchor.constraint(equalToConstant: 220).isActive = true
        webViewPanel.addArrangedSubview(row(label: preferenceLocalized("Alignment:"), control: webViewAlignmentControl))

        webViewLineSpacingSlider.target = self
        webViewLineSpacingSlider.action = #selector(webViewLineSpacingChanged(_:))
        webViewPanel.addArrangedSubview(row(label: preferenceLocalized("Line Gap:"), control: sliderRow(webViewLineSpacingSlider, webViewLineSpacingLabel)))

        webViewMotionSlider.target = self
        webViewMotionSlider.action = #selector(webViewMotionChanged(_:))
        webViewPanel.addArrangedSubview(row(label: preferenceLocalized("Motion:"), control: sliderRow(webViewMotionSlider, webViewMotionLabel)))

        let resetButton = NSButton(title: preferenceLocalized("Reset Theme"), target: self, action: #selector(resetWebView(_:)))
        webViewPanel.addArrangedSubview(resetButton)
    }

    private func configurePanel(_ panel: NSStackView) {
        panel.orientation = .vertical
        panel.alignment = .centerX
        panel.spacing = 14
        panel.edgeInsets = NSEdgeInsets(top: 18, left: 24, bottom: 18, right: 24)
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 12
        panel.layer?.borderWidth = 1
        panel.layer?.borderColor = NSColor.separatorColor.cgColor
        panel.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.32).cgColor
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.widthAnchor.constraint(equalToConstant: 520).isActive = true
    }

    private func row(label: String, control: NSView) -> NSStackView {
        let labelView = NSTextField(labelWithString: label)
        labelView.alignment = .right
        labelView.widthAnchor.constraint(equalToConstant: 90).isActive = true

        let row = NSStackView(views: [labelView, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func colorGrid(_ items: [(String, NSColorWell)]) -> NSStackView {
        let wells = items.map { item -> NSStackView in
            item.1.widthAnchor.constraint(equalToConstant: 44).isActive = true
            item.1.heightAnchor.constraint(equalToConstant: 23).isActive = true
            let label = NSTextField(labelWithString: item.0)
            let column = NSStackView(views: [item.1, label])
            column.orientation = .vertical
            column.alignment = .centerX
            column.spacing = 5
            return column
        }

        let grid = NSStackView(views: wells)
        grid.orientation = .horizontal
        grid.alignment = .top
        grid.spacing = 34
        return grid
    }

    private func sliderRow(_ slider: NSSlider, _ label: NSTextField) -> NSStackView {
        slider.widthAnchor.constraint(equalToConstant: 220).isActive = true
        label.widthAnchor.constraint(equalToConstant: 56).isActive = true
        let row = NSStackView(views: [slider, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func reloadControls() {
        let theme = normalizedTheme()
        classicPanel.isHidden = theme != .classic
        webViewPanel.isHidden = theme != .amllOriginalSource
        updateThemeSelection(theme)

        classicFontField.selectedFont = defaults.lyricsWindowFont
        classicTextWell.color = defaults.color(for: .lyricsWindowTextColor, fallback: #colorLiteral(red: 0.7540688515, green: 0.7540867925, blue: 0.7540771365, alpha: 1))
        classicHighlightWell.color = defaults.color(for: .lyricsWindowHighlightColor, fallback: #colorLiteral(red: 0.8866666667, green: 1, blue: 0.8, alpha: 1))

        webViewFontField.selectedFont = defaults.lyricsWindowAMLLOriginalFont
        webViewAlignmentControl.selectedSegment = defaults[.lyricsWindowAMLLDynamicAlignment]
        webViewLineSpacingSlider.doubleValue = defaults[.lyricsWindowAMLLDynamicLineSpacing] * 100
        webViewMotionSlider.doubleValue = defaults[.lyricsWindowAMLLDynamicMotionAmount] * 100
        updateWebViewLabels()
    }

    private func normalizedTheme() -> LyricsWindowTheme {
        let rawValue = defaults[.lyricsWindowTheme]
        if rawValue == 1 || rawValue == 2 {
            defaults[.lyricsWindowTheme] = LyricsWindowTheme.amllOriginalSource.rawValue
            return .amllOriginalSource
        }
        return LyricsWindowTheme(rawValue: rawValue) ?? .classic
    }

    private func updateThemeSelection(_ theme: LyricsWindowTheme) {
        [classicThemeButton, amllOriginalSourceThemeButton].forEach { button in
            let isSelected = button.tag == theme.rawValue
            button.layer?.borderColor = (isSelected ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
            button.layer?.borderWidth = isSelected ? 2 : 1
            button.layer?.backgroundColor = (isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.14) : NSColor.controlBackgroundColor.withAlphaComponent(0.24)).cgColor
        }
    }

    private func updateWebViewLabels() {
        webViewLineSpacingLabel.stringValue = "\(Int(webViewLineSpacingSlider.doubleValue))%"
        webViewMotionLabel.stringValue = "\(Int(webViewMotionSlider.doubleValue))%"
    }

    private func notifyLyricsWindowAppearanceChanged() {
        NotificationCenter.default.post(name: .lyricsWindowAppearanceDidChange, object: self)
    }

    @objc private func themeChanged(_ sender: NSButton) {
        defaults[.lyricsWindowTheme] = sender.tag
        reloadControls()
        notifyLyricsWindowAppearanceChanged()
    }

    @objc private func classicColorChanged(_ sender: NSColorWell) {
        switch sender {
        case classicTextWell:
            defaults.setColor(sender.color, for: .lyricsWindowTextColor)
        case classicHighlightWell:
            defaults.setColor(sender.color, for: .lyricsWindowHighlightColor)
        default:
            break
        }
        notifyLyricsWindowAppearanceChanged()
    }

    @objc private func webViewAlignmentChanged(_ sender: NSSegmentedControl) {
        defaults[.lyricsWindowAMLLDynamicAlignment] = sender.selectedSegment
        notifyLyricsWindowAppearanceChanged()
    }

    @objc private func webViewLineSpacingChanged(_ sender: NSSlider) {
        defaults[.lyricsWindowAMLLDynamicLineSpacing] = sender.doubleValue / 100
        updateWebViewLabels()
        notifyLyricsWindowAppearanceChanged()
    }

    @objc private func webViewMotionChanged(_ sender: NSSlider) {
        defaults[.lyricsWindowAMLLDynamicMotionAmount] = sender.doubleValue / 100
        updateWebViewLabels()
        notifyLyricsWindowAppearanceChanged()
    }

    @objc private func resetWebView(_ sender: Any) {
        let defaultFont = NSFont.boldSystemFont(ofSize: 32)
        defaults[.lyricsWindowAMLLOriginalFontName] = defaultFont.fontName
        defaults[.lyricsWindowAMLLOriginalFontSize] = Int(defaultFont.pointSize)
        defaults[.lyricsWindowAMLLDynamicAlignment] = LyricsWindowAMLLAlignment.left.rawValue
        defaults[.lyricsWindowAMLLDynamicLineSpacing] = 1.0
        defaults[.lyricsWindowAMLLDynamicMotionAmount] = 1.0
        reloadControls()
        notifyLyricsWindowAppearanceChanged()
    }

    func fontChanged(from oldFont: NSFont, to newFont: NSFont, sender: FontSelectTextField) {
        if sender === classicFontField {
            defaults[.lyricsWindowFontName] = newFont.fontName
            defaults[.lyricsWindowFontSize] = Int(newFont.pointSize)
        } else if sender === webViewFontField {
            defaults[.lyricsWindowAMLLOriginalFontName] = newFont.fontName
            defaults[.lyricsWindowAMLLOriginalFontSize] = Int(newFont.pointSize)
        }
        notifyLyricsWindowAppearanceChanged()
    }
}
