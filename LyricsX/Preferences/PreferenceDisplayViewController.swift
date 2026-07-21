import AppKit

class PreferenceDisplayViewController: PreferenceViewController, FontSelectTextFieldDelegate {
    @IBOutlet var karaokeFontSelectField: FontSelectTextField!
    @IBOutlet var hudFontSelectField: FontSelectTextField!

    @IBOutlet var fontFallbackLabel: NSTextField!
    @IBOutlet var removeFontFallbackButton: NSButton!

    override func viewDidLoad() {
        karaokeFontSelectField.selectedFont = defaults.desktopLyricsFont
        karaokeFontSelectField.fontChangeDelegate = self
        hudFontSelectField.selectedFont = defaults.lyricsWindowFont
        hudFontSelectField.fontChangeDelegate = self
        updateScreenFontFallback()
        removeMigratedKaraokeThemeControls()
        removeMigratedLyricsWindowThemeControls()
        super.viewDidLoad()
    }

    private func removeMigratedKaraokeThemeControls() {
        guard let karaokeThemeContainer = karaokeFontSelectField.superview else {
            return
        }

        let migratedColorKeys: Set<String> = [
            "values.DesktopLyricsBackgroundColor",
            "values.DesktopLyricsColor",
            "values.DesktopLyricsProgressColor",
            "values.DesktopLyricsShadowColor",
        ]
        var viewsToRemove = Set<NSView>()

        viewsToRemove.insert(karaokeFontSelectField)
        viewsToRemove.insert(fontFallbackLabel)
        viewsToRemove.insert(removeFontFallbackButton)

        for subview in karaokeThemeContainer.allSubviews where subview.isMigratedKaraokeThemeColorWell(keys: migratedColorKeys) {
            viewsToRemove.insert(subview)
        }

        var didChange = true
        while didChange {
            didChange = false
            for constraint in karaokeThemeContainer.allConstraints {
                guard let firstView = constraint.firstItem as? NSView else {
                    continue
                }
                let secondView = constraint.secondItem as? NSView
                if viewsToRemove.contains(firstView),
                   let secondView,
                   secondView.isMigratedKaraokeThemeCompanion,
                   !viewsToRemove.contains(secondView) {
                    viewsToRemove.insert(secondView)
                    didChange = true
                } else if let secondView,
                          viewsToRemove.contains(secondView),
                          firstView.isMigratedKaraokeThemeCompanion,
                          !viewsToRemove.contains(firstView) {
                    viewsToRemove.insert(firstView)
                    didChange = true
                }
            }
        }

        for stackView in karaokeThemeContainer.allSubviews.compactMap({ $0 as? NSStackView })
            where !stackView.subviews.isEmpty && stackView.subviews.allSatisfy({ viewsToRemove.contains($0) }) {
            viewsToRemove.insert(stackView)
        }

        for separator in karaokeThemeContainer.allSubviews.compactMap({ $0 as? NSBox })
            where separator.boxType == .separator
                && karaokeThemeContainer.allConstraints.contains(where: { $0.references(separator) && $0.referencesAny(in: viewsToRemove) }) {
            viewsToRemove.insert(separator)
        }

        let affectedConstraints = karaokeThemeContainer.allConstraints.filter { $0.referencesAny(in: viewsToRemove) }
        for owner in karaokeThemeContainer.ancestorChain {
            owner.removeConstraints(affectedConstraints.filter { owner.constraints.contains($0) })
        }
        for view in karaokeThemeContainer.allSubviews {
            view.removeConstraints(affectedConstraints.filter { view.constraints.contains($0) })
        }

        for view in viewsToRemove.sortedForRemoval {
            view.removeFromSuperview()
        }
    }

    private func removeMigratedLyricsWindowThemeControls() {
        guard let lyricsWindowThemeContainer = hudFontSelectField.superview else {
            return
        }

        let migratedColorKeys: Set<String> = [
            "values.LyricsWindowTextColor",
            "values.LyricsWindowHighlightColor",
        ]
        var viewsToRemove = Set<NSView>()
        viewsToRemove.insert(hudFontSelectField)

        for subview in lyricsWindowThemeContainer.allSubviews where subview.isMigratedKaraokeThemeColorWell(keys: migratedColorKeys) {
            viewsToRemove.insert(subview)
        }

        var didChange = true
        while didChange {
            didChange = false
            for constraint in lyricsWindowThemeContainer.allConstraints {
                guard let firstView = constraint.firstItem as? NSView else {
                    continue
                }
                let secondView = constraint.secondItem as? NSView
                if viewsToRemove.contains(firstView),
                   let secondView,
                   secondView.isMigratedKaraokeThemeCompanion,
                   !viewsToRemove.contains(secondView) {
                    viewsToRemove.insert(secondView)
                    didChange = true
                } else if let secondView,
                          viewsToRemove.contains(secondView),
                          firstView.isMigratedKaraokeThemeCompanion,
                          !viewsToRemove.contains(firstView) {
                    viewsToRemove.insert(firstView)
                    didChange = true
                }
            }
        }

        for stackView in lyricsWindowThemeContainer.allSubviews.compactMap({ $0 as? NSStackView })
            where !stackView.subviews.isEmpty && stackView.subviews.allSatisfy({ viewsToRemove.contains($0) }) {
            viewsToRemove.insert(stackView)
        }

        for separator in lyricsWindowThemeContainer.allSubviews.compactMap({ $0 as? NSBox })
            where separator.boxType == .separator
                && lyricsWindowThemeContainer.allConstraints.contains(where: { $0.references(separator) && $0.referencesAny(in: viewsToRemove) }) {
            viewsToRemove.insert(separator)
        }

        let affectedConstraints = lyricsWindowThemeContainer.allConstraints.filter { $0.referencesAny(in: viewsToRemove) }
        for owner in lyricsWindowThemeContainer.ancestorChain {
            owner.removeConstraints(affectedConstraints.filter { owner.constraints.contains($0) })
        }
        for view in lyricsWindowThemeContainer.allSubviews {
            view.removeConstraints(affectedConstraints.filter { view.constraints.contains($0) })
        }

        for view in viewsToRemove.sortedForRemoval {
            view.removeFromSuperview()
        }
    }

    func updateScreenFontFallback() {
        guard let fallback = defaults[.desktopLyricsFontNameFallback].first else {
            fontFallbackLabel.isHidden = true
            removeFontFallbackButton.isHidden = true
            return
        }
        fontFallbackLabel.isHidden = false
        removeFontFallbackButton.isHidden = false
        let format = NSLocalizedString("Font Fallback: %@", comment: "")
        fontFallbackLabel.stringValue = String(format: format, arguments: [fallback])
    }

    @IBAction func removeFontFallbackAction(_ sender: Any) {
        defaults[.desktopLyricsFontNameFallback].removeAll()
        updateScreenFontFallback()
    }

    func fontChanged(from oldFont: NSFont, to newFont: NSFont, sender: FontSelectTextField) {
        if sender === karaokeFontSelectField {
            defaults[.desktopLyricsFontName] = newFont.fontName
            defaults[.desktopLyricsFontSize] = Int(newFont.pointSize)
            if (oldFont.familyName != nil && oldFont.familyName != newFont.familyName)
                || oldFont.fontName != newFont.fontName {
                // guarantee different font family of font fallback
                var fallback = defaults[.desktopLyricsFontNameFallback]
                if let index = fallback.firstIndex(of: newFont.fontName) {
                    fallback.remove(at: index)
                }
                fallback.insert(oldFont.fontName, at: 0)
                defaults[.desktopLyricsFontNameFallback] = Array(fallback.prefix(fontNameFallbackCountMax))
                updateScreenFontFallback()
            }
        } else if sender === hudFontSelectField {
            defaults[.lyricsWindowFontName] = newFont.fontName
            defaults[.lyricsWindowFontSize] = Int(newFont.pointSize)
        }
    }
}

private extension NSView {
    var allSubviews: [NSView] {
        return subviews + subviews.flatMap(\.allSubviews)
    }

    var allConstraints: [NSLayoutConstraint] {
        return constraints + subviews.flatMap(\.allConstraints)
    }

    var ancestorChain: [NSView] {
        var views = [self]
        var view = superview
        while let current = view {
            views.append(current)
            view = current.superview
        }
        return views
    }

    var isMigratedKaraokeThemeCompanion: Bool {
        if let textField = self as? NSTextField {
            return !textField.isEditable && !textField.isSelectable
        }
        if let button = self as? NSButton {
            return button.action == #selector(PreferenceDisplayViewController.removeFontFallbackAction(_:))
        }
        return false
    }

    func isMigratedKaraokeThemeColorWell(keys: Set<String>) -> Bool {
        guard let colorWell = self as? NSColorWell,
              let info = colorWell.infoForBinding(.value),
              let keyPath = info[.observedKeyPath] as? String else {
            return false
        }
        return keys.contains(keyPath)
    }
}

private extension NSLayoutConstraint {
    func references(_ view: NSView) -> Bool {
        return (firstItem as? NSView) === view || (secondItem as? NSView) === view
    }

    func referencesAny(in views: Set<NSView>) -> Bool {
        return views.contains { references($0) }
    }
}

private extension Set where Element == NSView {
    var sortedForRemoval: [NSView] {
        return sorted { lhs, rhs in
            lhs.allSubviews.count > rhs.allSubviews.count
        }
    }
}

class AlphaColorWell: NSColorWell {
    override func activate(_ exclusive: Bool) {
        NSColorPanel.shared.showsAlpha = true
        super.activate(exclusive)
    }

    override func deactivate() {
        super.deactivate()
        NSColorPanel.shared.showsAlpha = false
    }
}
