import AppKit

class PreferenceThemeViewController: PreferenceViewController, FontSelectTextFieldDelegate {
    private let classicThemeButton = NSButton(frame: .zero)
    private let modernThemeButton = NSButton(frame: .zero)
    private let albumBlurThemeButton = NSButton(frame: .zero)
    private let amllDynamicThemeButton = NSButton(frame: .zero)

    private let classicPanel = NSStackView()
    private let modernPanel = NSStackView()
    private let albumBlurPanel = NSStackView()
    private let amllDynamicPanel = NSStackView()

    private let classicFontField = FontSelectTextField(frame: .zero)
    private let classicBackgroundWell = AlphaColorWell(frame: .zero)
    private let classicBackgroundOpacitySlider = NSSlider(value: 60, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let classicBackgroundOpacityLabel = NSTextField(labelWithString: "")
    private let classicTextWell = NSColorWell(frame: .zero)
    private let classicProgressWell = NSColorWell(frame: .zero)
    private let classicShadowWell = AlphaColorWell(frame: .zero)
    private let classicInactiveBlurSlider = NSSlider(value: 2, minValue: 0, maxValue: 2, target: nil, action: nil)
    private let classicInactiveBlurLabel = NSTextField(labelWithString: "")

    private let modernFontField = FontSelectTextField(frame: .zero)
    private let modernTextWell = NSColorWell(frame: .zero)
    private let modernProgressWell = NSColorWell(frame: .zero)
    private let modernBackgroundWell = NSColorWell(frame: .zero)
    private let modernOpacitySlider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let modernOpacityLabel = NSTextField(labelWithString: "")
    private let modernBlurButton = NSButton(checkboxWithTitle: "Use blur material", target: nil, action: nil)
    private let modernCornerRadiusSlider = NSSlider(value: 16, minValue: 0, maxValue: 32, target: nil, action: nil)
    private let modernCornerRadiusLabel = NSTextField(labelWithString: "")
    private let modernInactiveBlurSlider = NSSlider(value: 2, minValue: 0, maxValue: 2, target: nil, action: nil)
    private let modernInactiveBlurLabel = NSTextField(labelWithString: "")

    private let albumBlurFontField = FontSelectTextField(frame: .zero)
    private let albumBlurTextWell = NSColorWell(frame: .zero)
    private let albumBlurProgressWell = NSColorWell(frame: .zero)
    private let albumBlurTintWell = NSColorWell(frame: .zero)
    private let albumBlurFallbackWell = NSColorWell(frame: .zero)
    private let albumBlurBackgroundOpacitySlider = NSSlider(value: 65, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let albumBlurBackgroundOpacityLabel = NSTextField(labelWithString: "")
    private let albumBlurDimSlider = NSSlider(value: 42, minValue: 0, maxValue: 80, target: nil, action: nil)
    private let albumBlurDimLabel = NSTextField(labelWithString: "")
    private let albumBlurBlurSlider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let albumBlurBlurLabel = NSTextField(labelWithString: "")
    private let albumBlurCornerRadiusSlider = NSSlider(value: 16, minValue: 0, maxValue: 32, target: nil, action: nil)
    private let albumBlurCornerRadiusLabel = NSTextField(labelWithString: "")
    private let albumBlurReverseGradientButton = NSButton(checkboxWithTitle: "Reverse gradient", target: nil, action: nil)
    private let albumBlurInactiveBlurSlider = NSSlider(value: 2, minValue: 0, maxValue: 2, target: nil, action: nil)
    private let albumBlurInactiveBlurLabel = NSTextField(labelWithString: "")

    private let amllDynamicFontField = FontSelectTextField(frame: .zero)
    private let amllDynamicTextWell = NSColorWell(frame: .zero)
    private let amllDynamicProgressWell = NSColorWell(frame: .zero)
    private let amllDynamicTintWell = NSColorWell(frame: .zero)
    private let amllDynamicFallbackWell = NSColorWell(frame: .zero)
    private let amllDynamicBackgroundOpacitySlider = NSSlider(value: 65, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let amllDynamicBackgroundOpacityLabel = NSTextField(labelWithString: "")
    private let amllDynamicDimSlider = NSSlider(value: 34, minValue: 0, maxValue: 75, target: nil, action: nil)
    private let amllDynamicDimLabel = NSTextField(labelWithString: "")
    private let amllDynamicFlowSlider = NSSlider(value: 90, minValue: 0, maxValue: 200, target: nil, action: nil)
    private let amllDynamicFlowLabel = NSTextField(labelWithString: "")
    private let amllDynamicIntensitySlider = NSSlider(value: 72, minValue: 20, maxValue: 100, target: nil, action: nil)
    private let amllDynamicIntensityLabel = NSTextField(labelWithString: "")
    private let amllDynamicCornerRadiusSlider = NSSlider(value: 18, minValue: 0, maxValue: 36, target: nil, action: nil)
    private let amllDynamicCornerRadiusLabel = NSTextField(labelWithString: "")
    private let amllDynamicReverseGradientButton = NSButton(checkboxWithTitle: "Reverse gradient", target: nil, action: nil)
    private let amllDynamicInactiveBlurSlider = NSSlider(value: 2, minValue: 0, maxValue: 2, target: nil, action: nil)
    private let amllDynamicInactiveBlurLabel = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 560))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Desktop Lyrics Theme"
        setupViews()
        reloadControls()
    }

    private func setupViews() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .centerX
        root.spacing = 18
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])

        configureThemeButton(classicThemeButton, title: "Classic", theme: .classic, image: themePreviewImage(theme: .classic))
        configureThemeButton(modernThemeButton, title: "Modern", theme: .modern, image: themePreviewImage(theme: .modern))
        configureThemeButton(albumBlurThemeButton, title: "Album Blur", theme: .albumBlur, image: themePreviewImage(theme: .albumBlur))
        configureThemeButton(amllDynamicThemeButton, title: "AMLL Dynamic / Apple Music", theme: .amllDynamic, image: themePreviewImage(theme: .amllDynamic))

        let themeList = NSStackView(views: [classicThemeButton, modernThemeButton, albumBlurThemeButton, amllDynamicThemeButton])
        themeList.orientation = .horizontal
        themeList.alignment = .top
        themeList.spacing = 14
        root.addArrangedSubview(themeList)

        setupClassicPanel()
        setupModernPanel()
        setupAlbumBlurPanel()
        setupAMLLDynamicPanel()

        root.addArrangedSubview(classicPanel)
        root.addArrangedSubview(modernPanel)
        root.addArrangedSubview(albumBlurPanel)
        root.addArrangedSubview(amllDynamicPanel)
    }

    private func configureThemeButton(_ button: NSButton, title: String, theme: DesktopLyricsTheme, image: NSImage) {
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
        button.layer?.cornerRadius = 8
        button.layer?.borderWidth = 1
        button.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 160),
            button.heightAnchor.constraint(equalToConstant: 112),
        ])
    }

    private func themePreviewImage(theme: DesktopLyricsTheme) -> NSImage {
        let size = NSSize(width: 150, height: 68)
        return NSImage(size: size, flipped: false) { _ in
            let backgroundRect = NSRect(x: 10, y: 16, width: 130, height: 38)
            let background = NSBezierPath(roundedRect: backgroundRect, xRadius: theme == .classic ? 14 : 18, yRadius: theme == .classic ? 14 : 18)
            background.addClip()

            switch theme {
            case .classic:
                NSColor(calibratedWhite: 0, alpha: 0.62).setFill()
                background.fill()
            case .modern:
                NSColor(calibratedRed: 0.18, green: 0.24, blue: 0.8, alpha: 0.55).setFill()
                background.fill()
            case .albumBlur:
                NSGradient(colors: [
                    NSColor(calibratedRed: 0.95, green: 0.36, blue: 0.28, alpha: 1),
                    NSColor(calibratedRed: 0.14, green: 0.38, blue: 0.86, alpha: 1),
                    NSColor(calibratedRed: 0.1, green: 0.08, blue: 0.2, alpha: 1),
                ])?.draw(in: backgroundRect, angle: 18)
                NSColor.black.withAlphaComponent(0.34).setFill()
                background.fill()
            case .amllDynamic:
                NSGradient(colors: [
                    NSColor(calibratedRed: 1, green: 0.27, blue: 0.42, alpha: 1),
                    NSColor(calibratedRed: 0.18, green: 0.48, blue: 1, alpha: 1),
                    NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.18, alpha: 1),
                ])?.draw(in: backgroundRect, angle: 32)
                NSColor.black.withAlphaComponent(0.26).setFill()
                background.fill()
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 23, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
            "LyricsX".draw(at: NSPoint(x: 31, y: 25), withAttributes: attributes)
            return true
        }
    }

    private func setupClassicPanel() {
        configurePanel(classicPanel)
        classicFontField.fontChangeDelegate = self
        classicPanel.addArrangedSubview(row(label: "Font:", control: classicFontField))
        [classicBackgroundWell, classicTextWell, classicProgressWell, classicShadowWell].forEach {
            $0.target = self
            $0.action = #selector(classicColorChanged(_:))
        }
        classicBackgroundOpacitySlider.target = self
        classicBackgroundOpacitySlider.action = #selector(classicBackgroundOpacityChanged(_:))
        classicPanel.addArrangedSubview(row(label: "Background:", control: colorOpacityRow(classicBackgroundWell, classicBackgroundOpacitySlider, classicBackgroundOpacityLabel)))
        classicPanel.addArrangedSubview(colorGrid([
            ("Lyrics", classicTextWell),
            ("Progress", classicProgressWell),
            ("Shadow", classicShadowWell),
        ]))
        classicInactiveBlurSlider.target = self
        classicInactiveBlurSlider.action = #selector(classicInactiveBlurChanged(_:))
        classicInactiveBlurSlider.isContinuous = false
        classicPanel.addArrangedSubview(row(label: "Inactive blur:", control: sliderRow(classicInactiveBlurSlider, classicInactiveBlurLabel)))
    }

    private func setupModernPanel() {
        configurePanel(modernPanel)
        modernFontField.fontChangeDelegate = self
        modernPanel.addArrangedSubview(row(label: "Font:", control: modernFontField))
        [modernTextWell, modernProgressWell, modernBackgroundWell].forEach {
            $0.target = self
            $0.action = #selector(modernColorChanged(_:))
        }
        modernPanel.addArrangedSubview(colorGrid([
            ("Lyrics", modernTextWell),
            ("Progress", modernProgressWell),
        ]))
        modernOpacitySlider.target = self
        modernOpacitySlider.action = #selector(modernOpacityChanged(_:))
        modernPanel.addArrangedSubview(row(label: "Background:", control: colorOpacityRow(modernBackgroundWell, modernOpacitySlider, modernOpacityLabel)))
        modernBlurButton.target = self
        modernBlurButton.action = #selector(modernBlurChanged(_:))
        modernPanel.addArrangedSubview(row(label: "Material:", control: modernBlurButton))
        modernCornerRadiusSlider.target = self
        modernCornerRadiusSlider.action = #selector(modernCornerRadiusChanged(_:))
        modernPanel.addArrangedSubview(row(label: "Corner:", control: sliderRow(modernCornerRadiusSlider, modernCornerRadiusLabel)))
        modernInactiveBlurSlider.target = self
        modernInactiveBlurSlider.action = #selector(modernInactiveBlurChanged(_:))
        modernInactiveBlurSlider.isContinuous = false
        modernPanel.addArrangedSubview(row(label: "Inactive blur:", control: sliderRow(modernInactiveBlurSlider, modernInactiveBlurLabel)))
    }

    private func setupAlbumBlurPanel() {
        configurePanel(albumBlurPanel)
        albumBlurFontField.fontChangeDelegate = self
        albumBlurPanel.addArrangedSubview(row(label: "Font:", control: albumBlurFontField))
        [albumBlurTextWell, albumBlurProgressWell, albumBlurTintWell, albumBlurFallbackWell].forEach {
            $0.target = self
            $0.action = #selector(albumBlurColorChanged(_:))
        }
        albumBlurPanel.addArrangedSubview(colorGrid([
            ("Lyrics", albumBlurTextWell),
            ("Progress", albumBlurProgressWell),
        ]))
        albumBlurReverseGradientButton.target = self
        albumBlurReverseGradientButton.action = #selector(albumBlurReverseGradientChanged(_:))
        albumBlurPanel.addArrangedSubview(row(label: "Gradient:", control: albumBlurReverseGradientButton))
        albumBlurBackgroundOpacitySlider.target = self
        albumBlurBackgroundOpacitySlider.action = #selector(albumBlurBackgroundOpacityChanged(_:))
        albumBlurPanel.addArrangedSubview(row(label: "Background:", control: colorOpacityRow(albumBlurFallbackWell, albumBlurBackgroundOpacitySlider, albumBlurBackgroundOpacityLabel)))
        albumBlurDimSlider.target = self
        albumBlurDimSlider.action = #selector(albumBlurDimChanged(_:))
        albumBlurPanel.addArrangedSubview(row(label: "Dim:", control: colorOpacityRow(albumBlurTintWell, albumBlurDimSlider, albumBlurDimLabel)))
        albumBlurBlurSlider.target = self
        albumBlurBlurSlider.action = #selector(albumBlurBlurChanged(_:))
        albumBlurPanel.addArrangedSubview(row(label: "Blur:", control: sliderRow(albumBlurBlurSlider, albumBlurBlurLabel)))
        albumBlurCornerRadiusSlider.target = self
        albumBlurCornerRadiusSlider.action = #selector(albumBlurCornerRadiusChanged(_:))
        albumBlurPanel.addArrangedSubview(row(label: "Corner:", control: sliderRow(albumBlurCornerRadiusSlider, albumBlurCornerRadiusLabel)))
        albumBlurInactiveBlurSlider.target = self
        albumBlurInactiveBlurSlider.action = #selector(albumBlurInactiveBlurChanged(_:))
        albumBlurInactiveBlurSlider.isContinuous = false
        albumBlurPanel.addArrangedSubview(row(label: "Inactive blur:", control: sliderRow(albumBlurInactiveBlurSlider, albumBlurInactiveBlurLabel)))
    }

    private func setupAMLLDynamicPanel() {
        configurePanel(amllDynamicPanel)
        amllDynamicFontField.fontChangeDelegate = self
        amllDynamicPanel.addArrangedSubview(row(label: "Font:", control: amllDynamicFontField))
        [amllDynamicTextWell, amllDynamicProgressWell, amllDynamicTintWell, amllDynamicFallbackWell].forEach {
            $0.target = self
            $0.action = #selector(amllDynamicColorChanged(_:))
        }
        amllDynamicPanel.addArrangedSubview(colorGrid([
            ("Lyrics", amllDynamicTextWell),
            ("Progress", amllDynamicProgressWell),
        ]))
        amllDynamicReverseGradientButton.target = self
        amllDynamicReverseGradientButton.action = #selector(amllDynamicReverseGradientChanged(_:))
        amllDynamicPanel.addArrangedSubview(row(label: "Gradient:", control: amllDynamicReverseGradientButton))
        amllDynamicBackgroundOpacitySlider.target = self
        amllDynamicBackgroundOpacitySlider.action = #selector(amllDynamicBackgroundOpacityChanged(_:))
        amllDynamicPanel.addArrangedSubview(row(label: "Background:", control: colorOpacityRow(amllDynamicFallbackWell, amllDynamicBackgroundOpacitySlider, amllDynamicBackgroundOpacityLabel)))
        amllDynamicDimSlider.target = self
        amllDynamicDimSlider.action = #selector(amllDynamicDimChanged(_:))
        amllDynamicPanel.addArrangedSubview(row(label: "Tint:", control: colorOpacityRow(amllDynamicTintWell, amllDynamicDimSlider, amllDynamicDimLabel)))
        amllDynamicFlowSlider.target = self
        amllDynamicFlowSlider.action = #selector(amllDynamicFlowChanged(_:))
        amllDynamicPanel.addArrangedSubview(row(label: "Flow:", control: sliderRow(amllDynamicFlowSlider, amllDynamicFlowLabel)))
        amllDynamicIntensitySlider.target = self
        amllDynamicIntensitySlider.action = #selector(amllDynamicIntensityChanged(_:))
        amllDynamicPanel.addArrangedSubview(row(label: "Intensity:", control: sliderRow(amllDynamicIntensitySlider, amllDynamicIntensityLabel)))
        amllDynamicCornerRadiusSlider.target = self
        amllDynamicCornerRadiusSlider.action = #selector(amllDynamicCornerRadiusChanged(_:))
        amllDynamicPanel.addArrangedSubview(row(label: "Corner:", control: sliderRow(amllDynamicCornerRadiusSlider, amllDynamicCornerRadiusLabel)))
        amllDynamicInactiveBlurSlider.target = self
        amllDynamicInactiveBlurSlider.action = #selector(amllDynamicInactiveBlurChanged(_:))
        amllDynamicInactiveBlurSlider.isContinuous = false
        amllDynamicPanel.addArrangedSubview(row(label: "Inactive blur:", control: sliderRow(amllDynamicInactiveBlurSlider, amllDynamicInactiveBlurLabel)))
    }

    private func configurePanel(_ panel: NSStackView) {
        panel.orientation = .vertical
        panel.alignment = .centerX
        panel.spacing = 12
        panel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func row(label: String, control: NSView) -> NSStackView {
        let labelView = NSTextField(labelWithString: label)
        labelView.alignment = .right
        labelView.widthAnchor.constraint(equalToConstant: 90).isActive = true
        let row = NSStackView(views: [labelView, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
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

    private func colorOpacityRow(_ colorWell: NSColorWell, _ slider: NSSlider, _ valueLabel: NSTextField) -> NSStackView {
        colorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 23).isActive = true
        let opacityLabel = NSTextField(labelWithString: "Opacity")
        opacityLabel.textColor = .secondaryLabelColor
        opacityLabel.alignment = .right
        opacityLabel.widthAnchor.constraint(equalToConstant: 54).isActive = true
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        valueLabel.widthAnchor.constraint(equalToConstant: 56).isActive = true
        let row = NSStackView(views: [colorWell, opacityLabel, slider, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func reloadControls() {
        let theme = DesktopLyricsTheme(rawValue: defaults[.desktopLyricsTheme]) ?? .classic
        classicPanel.isHidden = theme != .classic
        modernPanel.isHidden = theme != .modern
        albumBlurPanel.isHidden = theme != .albumBlur
        amllDynamicPanel.isHidden = theme != .amllDynamic
        updateThemeSelection(theme)

        classicFontField.selectedFont = defaults.desktopLyricsFont
        classicBackgroundWell.color = defaults.color(for: .desktopLyricsBackgroundColor, fallback: #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0.6041579279))
        classicBackgroundOpacitySlider.doubleValue = Double(classicBackgroundWell.color.alphaComponent * 100)
        classicTextWell.color = defaults.color(for: .desktopLyricsColor, fallback: .white)
        classicProgressWell.color = defaults.color(for: .desktopLyricsProgressColor, fallback: #colorLiteral(red: 0.1985405816, green: 1, blue: 0.8664234302, alpha: 1))
        classicShadowWell.color = defaults.color(for: .desktopLyricsShadowColor, fallback: #colorLiteral(red: 0, green: 1, blue: 0.8333333333, alpha: 1))
        classicInactiveBlurSlider.doubleValue = defaults[.desktopLyricsInactiveLineBlurRadius].clamped(to: 0...2)

        modernFontField.selectedFont = defaults.desktopLyricsModernFont
        modernTextWell.color = defaults.color(for: .desktopLyricsModernTextColor, fallback: .white)
        modernProgressWell.color = defaults.color(for: .desktopLyricsModernProgressColor, fallback: desktopLyricsModernDefaultProgressColor)
        modernBackgroundWell.color = defaults.color(for: .desktopLyricsModernBackgroundColor, fallback: NSColor(calibratedRed: 0.176, green: 0.235, blue: 0.8, alpha: 1))
        modernOpacitySlider.doubleValue = defaults[.desktopLyricsModernBackgroundOpacity] * 100
        modernBlurButton.state = defaults[.desktopLyricsModernBlurEnabled] ? .on : .off
        modernCornerRadiusSlider.doubleValue = defaults[.desktopLyricsModernCornerRadius]
        modernInactiveBlurSlider.doubleValue = defaults[.desktopLyricsModernInactiveLineBlurRadius].clamped(to: 0...2)

        albumBlurFontField.selectedFont = defaults.desktopLyricsAlbumBlurFont
        albumBlurTextWell.color = defaults.color(for: .desktopLyricsAlbumBlurTextColor, fallback: .white)
        albumBlurProgressWell.color = defaults.color(for: .desktopLyricsAlbumBlurProgressColor, fallback: desktopLyricsAlbumBlurDefaultProgressColor)
        albumBlurTintWell.color = defaults.color(for: .desktopLyricsAlbumBlurTintColor, fallback: .black)
        albumBlurFallbackWell.color = defaults.color(for: .desktopLyricsAlbumBlurFallbackColor, fallback: NSColor(calibratedRed: 0.176, green: 0.235, blue: 0.8, alpha: 1))
        albumBlurBackgroundOpacitySlider.doubleValue = defaults[.desktopLyricsAlbumBlurBackgroundOpacity] * 100
        albumBlurDimSlider.doubleValue = defaults[.desktopLyricsAlbumBlurDimAmount] * 100
        albumBlurBlurSlider.doubleValue = defaults[.desktopLyricsAlbumBlurBlurAmount] * 100
        albumBlurCornerRadiusSlider.doubleValue = defaults[.desktopLyricsAlbumBlurCornerRadius]
        albumBlurReverseGradientButton.state = defaults[.desktopLyricsAlbumBlurReverseProgressGradient] ? .on : .off
        albumBlurInactiveBlurSlider.doubleValue = defaults[.desktopLyricsAlbumBlurInactiveLineBlurRadius].clamped(to: 0...2)

        amllDynamicFontField.selectedFont = defaults.desktopLyricsAMLLDynamicFont
        amllDynamicTextWell.color = defaults.color(for: .desktopLyricsAMLLDynamicTextColor, fallback: .white)
        amllDynamicProgressWell.color = defaults.color(for: .desktopLyricsAMLLDynamicProgressColor, fallback: desktopLyricsAMLLDynamicDefaultProgressColor)
        amllDynamicTintWell.color = defaults.color(for: .desktopLyricsAMLLDynamicTintColor, fallback: .black)
        amllDynamicFallbackWell.color = defaults.color(for: .desktopLyricsAMLLDynamicFallbackColor, fallback: desktopLyricsAMLLDynamicDefaultFallbackColor)
        amllDynamicBackgroundOpacitySlider.doubleValue = defaults[.desktopLyricsAMLLDynamicBackgroundOpacity] * 100
        amllDynamicDimSlider.doubleValue = defaults[.desktopLyricsAMLLDynamicDimAmount] * 100
        amllDynamicFlowSlider.doubleValue = defaults[.desktopLyricsAMLLDynamicFlowSpeed] * 100
        amllDynamicIntensitySlider.doubleValue = defaults[.desktopLyricsAMLLDynamicIntensity] * 100
        amllDynamicCornerRadiusSlider.doubleValue = defaults[.desktopLyricsAMLLDynamicCornerRadius]
        amllDynamicReverseGradientButton.state = defaults[.desktopLyricsAMLLDynamicReverseProgressGradient] ? .on : .off
        amllDynamicInactiveBlurSlider.doubleValue = defaults[.desktopLyricsAMLLDynamicInactiveLineBlurRadius].clamped(to: 0...2)

        updateLabels()
    }

    private func updateThemeSelection(_ theme: DesktopLyricsTheme) {
        [classicThemeButton, modernThemeButton, albumBlurThemeButton, amllDynamicThemeButton].forEach { button in
            let isSelected = button.tag == theme.rawValue
            button.layer?.borderColor = (isSelected ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
            button.layer?.borderWidth = isSelected ? 2 : 1
            button.layer?.backgroundColor = (isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.clear).cgColor
        }
    }

    private func updateLabels() {
        classicBackgroundOpacityLabel.stringValue = "\(Int(classicBackgroundOpacitySlider.doubleValue))%"
        classicInactiveBlurLabel.stringValue = String(format: "%.1f px", classicInactiveBlurSlider.doubleValue)
        modernOpacityLabel.stringValue = "\(Int(modernOpacitySlider.doubleValue))%"
        modernCornerRadiusLabel.stringValue = "\(Int(modernCornerRadiusSlider.doubleValue)) px"
        modernInactiveBlurLabel.stringValue = String(format: "%.1f px", modernInactiveBlurSlider.doubleValue)
        albumBlurBackgroundOpacityLabel.stringValue = "\(Int(albumBlurBackgroundOpacitySlider.doubleValue))%"
        albumBlurDimLabel.stringValue = "\(Int(albumBlurDimSlider.doubleValue))%"
        albumBlurBlurLabel.stringValue = "\(Int(albumBlurBlurSlider.doubleValue))%"
        albumBlurCornerRadiusLabel.stringValue = "\(Int(albumBlurCornerRadiusSlider.doubleValue)) px"
        albumBlurInactiveBlurLabel.stringValue = String(format: "%.1f px", albumBlurInactiveBlurSlider.doubleValue)
        amllDynamicBackgroundOpacityLabel.stringValue = "\(Int(amllDynamicBackgroundOpacitySlider.doubleValue))%"
        amllDynamicDimLabel.stringValue = "\(Int(amllDynamicDimSlider.doubleValue))%"
        amllDynamicFlowLabel.stringValue = String(format: "%.1fx", amllDynamicFlowSlider.doubleValue / 100)
        amllDynamicIntensityLabel.stringValue = "\(Int(amllDynamicIntensitySlider.doubleValue))%"
        amllDynamicCornerRadiusLabel.stringValue = "\(Int(amllDynamicCornerRadiusSlider.doubleValue)) px"
        amllDynamicInactiveBlurLabel.stringValue = String(format: "%.1f px", amllDynamicInactiveBlurSlider.doubleValue)
    }

    private func notifyDesktopLyricsAppearanceChanged() {
        NotificationCenter.default.post(name: .desktopLyricsAppearanceDidChange, object: self)
    }

    @objc private func themeChanged(_ sender: NSButton) {
        defaults[.desktopLyricsTheme] = sender.tag
        reloadControls()
        notifyDesktopLyricsAppearanceChanged()
    }

    @objc private func classicColorChanged(_ sender: NSColorWell) {
        switch sender {
        case classicBackgroundWell:
            defaults.setColor(sender.color, for: .desktopLyricsBackgroundColor)
            classicBackgroundOpacitySlider.doubleValue = Double(sender.color.alphaComponent * 100)
            updateLabels()
        case classicTextWell: defaults.setColor(sender.color, for: .desktopLyricsColor)
        case classicProgressWell: defaults.setColor(sender.color, for: .desktopLyricsProgressColor)
        case classicShadowWell: defaults.setColor(sender.color, for: .desktopLyricsShadowColor)
        default: break
        }
        notifyDesktopLyricsAppearanceChanged()
    }

    @objc private func classicBackgroundOpacityChanged(_ sender: NSSlider) {
        let color = defaults.color(for: .desktopLyricsBackgroundColor, fallback: #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0.6041579279))
            .withAlphaComponent(CGFloat(sender.doubleValue / 100))
        defaults.setColor(color, for: .desktopLyricsBackgroundColor)
        classicBackgroundWell.color = color
        updateLabels()
        notifyDesktopLyricsAppearanceChanged()
    }

    @objc private func classicInactiveBlurChanged(_ sender: NSSlider) {
        defaults[.desktopLyricsInactiveLineBlurRadius] = sender.doubleValue
        updateLabels()
        notifyDesktopLyricsAppearanceChanged()
    }

    @objc private func modernColorChanged(_ sender: NSColorWell) {
        switch sender {
        case modernTextWell: defaults.setColor(sender.color, for: .desktopLyricsModernTextColor)
        case modernProgressWell: defaults.setColor(sender.color, for: .desktopLyricsModernProgressColor)
        case modernBackgroundWell: defaults.setColor(sender.color, for: .desktopLyricsModernBackgroundColor)
        default: break
        }
        notifyDesktopLyricsAppearanceChanged()
    }

    @objc private func modernOpacityChanged(_ sender: NSSlider) {
        defaults[.desktopLyricsModernBackgroundOpacity] = sender.doubleValue / 100
        updateLabels()
        notifyDesktopLyricsAppearanceChanged()
    }

    @objc private func modernBlurChanged(_ sender: NSButton) {
        defaults[.desktopLyricsModernBlurEnabled] = sender.state == .on
        notifyDesktopLyricsAppearanceChanged()
    }

    @objc private func modernCornerRadiusChanged(_ sender: NSSlider) {
        defaults[.desktopLyricsModernCornerRadius] = sender.doubleValue
        updateLabels()
        notifyDesktopLyricsAppearanceChanged()
    }

    @objc private func modernInactiveBlurChanged(_ sender: NSSlider) {
        defaults[.desktopLyricsModernInactiveLineBlurRadius] = sender.doubleValue
        updateLabels()
        notifyDesktopLyricsAppearanceChanged()
    }

    @objc private func albumBlurColorChanged(_ sender: NSColorWell) {
        switch sender {
        case albumBlurTextWell: defaults.setColor(sender.color, for: .desktopLyricsAlbumBlurTextColor)
        case albumBlurProgressWell: defaults.setColor(sender.color, for: .desktopLyricsAlbumBlurProgressColor)
        case albumBlurTintWell: defaults.setColor(sender.color, for: .desktopLyricsAlbumBlurTintColor)
        case albumBlurFallbackWell: defaults.setColor(sender.color, for: .desktopLyricsAlbumBlurFallbackColor)
        default: break
        }
        notifyDesktopLyricsAppearanceChanged()
    }

    @objc private func albumBlurDimChanged(_ sender: NSSlider) {
        defaults[.desktopLyricsAlbumBlurDimAmount] = sender.doubleValue / 100
        updateLabels()
        notifyDesktopLyricsAppearanceChanged()
    }

    @objc private func albumBlurBackgroundOpacityChanged(_ sender: NSSlider) {
        defaults[.desktopLyricsAlbumBlurBackgroundOpacity] = sender.doubleValue / 100
        updateLabels()
        notifyDesktopLyricsAppearanceChanged()
    }

    @objc private func albumBlurBlurChanged(_ sender: NSSlider) {
        defaults[.desktopLyricsAlbumBlurBlurAmount] = sender.doubleValue / 100
        updateLabels()
        notifyDesktopLyricsAppearanceChanged()
    }

    @objc private func albumBlurCornerRadiusChanged(_ sender: NSSlider) {
        defaults[.desktopLyricsAlbumBlurCornerRadius] = sender.doubleValue
        updateLabels()
        notifyDesktopLyricsAppearanceChanged()
    }

    @objc private func albumBlurReverseGradientChanged(_ sender: NSButton) {
        defaults[.desktopLyricsAlbumBlurReverseProgressGradient] = sender.state == .on
        notifyDesktopLyricsAppearanceChanged()
    }

    @objc private func albumBlurInactiveBlurChanged(_ sender: NSSlider) {
        defaults[.desktopLyricsAlbumBlurInactiveLineBlurRadius] = sender.doubleValue
        updateLabels()
        notifyDesktopLyricsAppearanceChanged()
    }

    @objc private func amllDynamicColorChanged(_ sender: NSColorWell) {
        switch sender {
        case amllDynamicTextWell: defaults.setColor(sender.color, for: .desktopLyricsAMLLDynamicTextColor)
        case amllDynamicProgressWell: defaults.setColor(sender.color, for: .desktopLyricsAMLLDynamicProgressColor)
        case amllDynamicTintWell: defaults.setColor(sender.color, for: .desktopLyricsAMLLDynamicTintColor)
        case amllDynamicFallbackWell: defaults.setColor(sender.color, for: .desktopLyricsAMLLDynamicFallbackColor)
        default: break
        }
        notifyDesktopLyricsAppearanceChanged()
    }

    @objc private func amllDynamicDimChanged(_ sender: NSSlider) {
        defaults[.desktopLyricsAMLLDynamicDimAmount] = sender.doubleValue / 100
        updateLabels()
        notifyDesktopLyricsAppearanceChanged()
    }

    @objc private func amllDynamicBackgroundOpacityChanged(_ sender: NSSlider) {
        defaults[.desktopLyricsAMLLDynamicBackgroundOpacity] = sender.doubleValue / 100
        updateLabels()
        notifyDesktopLyricsAppearanceChanged()
    }

    @objc private func amllDynamicFlowChanged(_ sender: NSSlider) {
        defaults[.desktopLyricsAMLLDynamicFlowSpeed] = sender.doubleValue / 100
        updateLabels()
        notifyDesktopLyricsAppearanceChanged()
    }

    @objc private func amllDynamicIntensityChanged(_ sender: NSSlider) {
        defaults[.desktopLyricsAMLLDynamicIntensity] = sender.doubleValue / 100
        updateLabels()
        notifyDesktopLyricsAppearanceChanged()
    }

    @objc private func amllDynamicCornerRadiusChanged(_ sender: NSSlider) {
        defaults[.desktopLyricsAMLLDynamicCornerRadius] = sender.doubleValue
        updateLabels()
        notifyDesktopLyricsAppearanceChanged()
    }

    @objc private func amllDynamicReverseGradientChanged(_ sender: NSButton) {
        defaults[.desktopLyricsAMLLDynamicReverseProgressGradient] = sender.state == .on
        notifyDesktopLyricsAppearanceChanged()
    }

    @objc private func amllDynamicInactiveBlurChanged(_ sender: NSSlider) {
        defaults[.desktopLyricsAMLLDynamicInactiveLineBlurRadius] = sender.doubleValue
        updateLabels()
        notifyDesktopLyricsAppearanceChanged()
    }

    func fontChanged(from oldFont: NSFont, to newFont: NSFont, sender: FontSelectTextField) {
        if sender === classicFontField {
            defaults[.desktopLyricsFontName] = newFont.fontName
            defaults[.desktopLyricsFontSize] = Int(newFont.pointSize)
        } else if sender === modernFontField {
            defaults[.desktopLyricsModernFontName] = newFont.fontName
            defaults[.desktopLyricsModernFontSize] = Int(newFont.pointSize)
        } else if sender === albumBlurFontField {
            defaults[.desktopLyricsAlbumBlurFontName] = newFont.fontName
            defaults[.desktopLyricsAlbumBlurFontSize] = Int(newFont.pointSize)
        } else if sender === amllDynamicFontField {
            defaults[.desktopLyricsAMLLDynamicFontName] = newFont.fontName
            defaults[.desktopLyricsAMLLDynamicFontSize] = Int(newFont.pointSize)
        }
        notifyDesktopLyricsAppearanceChanged()
    }
}
