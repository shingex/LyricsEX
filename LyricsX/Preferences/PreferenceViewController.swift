import Cocoa

class PreferenceTabViewController: NSTabViewController {
    private let sidebarWidth: CGFloat = 210
    private let pageTitleLabel = NSTextField(labelWithString: "")
    private let pageSubtitleLabel = NSTextField(wrappingLabelWithString: "")
    private var navigationButtons: [Int: NSButton] = [:]
    private var managedTabItems: [NSTabViewItem] = []
    private var didConfigureSidebarLayout = false

    override func viewDidLoad() {
        super.viewDidLoad()

        if !tabViewItems.contains(where: { $0.viewController is PreferenceThemeViewController }) {
            let themeViewController = PreferenceThemeViewController()
            let tabItem = NSTabViewItem(viewController: themeViewController)
            tabItem.label = preferenceLocalized("Desktop Lyrics")
            insertTabViewItem(tabItem, at: min(2, tabViewItems.count))
        }

        if !tabViewItems.contains(where: { $0.viewController is PreferenceLyricsWindowThemeViewController }) {
            let themeViewController = PreferenceLyricsWindowThemeViewController()
            let tabItem = NSTabViewItem(viewController: themeViewController)
            tabItem.label = preferenceLocalized("Lyrics Window")
            insertTabViewItem(tabItem, at: min(3, tabViewItems.count))
        }

        configureNavigationIcons()
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        guard !didConfigureSidebarLayout else { return }
        managedTabItems = tabView.tabViewItems.isEmpty ? tabViewItems : tabView.tabViewItems
        guard !managedTabItems.isEmpty else { return }
        didConfigureSidebarLayout = true
        let initialIndex = managedTabItems.firstIndex { $0 === tabView.selectedTabViewItem } ?? 0
        configureSidebarLayout()
        selectPage(initialIndex)

        if let window = view.window {
            DispatchQueue.main.async {
                window.toolbar = nil
                window.title = preferenceLocalized("Settings")
                window.setContentSize(NSSize(width: 1000, height: 780))
                window.center()
            }
        }
    }

    private func configureNavigationIcons() {
        let iconNames = [
            "gearshape",
            "textformat.size",
            "captions.bubble",
            "macwindow",
            "command",
            "line.3.horizontal.decrease.circle",
            "flask",
            "list.number",
        ]
        let fallbackImageNames = [
            "NSPreferencesGeneral",
            "NSFontPanel",
            "NSColorPanel",
            "NSColorPanel",
            "toolbar_shortcut",
            "toolbar_filter",
            "toolbar_lab",
            "NSListViewTemplate",
        ]

        for (index, tabItem) in tabViewItems.enumerated() where index < iconNames.count {
            if #available(macOS 11.0, *) {
                tabItem.image = NSImage(
                    systemSymbolName: iconNames[index],
                    accessibilityDescription: tabItem.label
                )
            }
            if tabItem.image == nil {
                tabItem.image = NSImage(named: NSImage.Name(fallbackImageNames[index]))
            }
            tabItem.image?.isTemplate = true
        }
    }

    private func configureSidebarLayout() {
        tabView.tabViewType = .noTabsNoBorder

        view.removeConstraints(view.constraints.filter { constraint in
            constraint.firstItem as? NSView === tabView || constraint.secondItem as? NSView === tabView
        })

        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.state = .followsWindowActiveState
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let sidebarSeparator = NSBox()
        sidebarSeparator.boxType = .separator
        sidebarSeparator.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(sidebar)
        view.addSubview(sidebarSeparator)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: view.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: sidebarWidth),
            sidebarSeparator.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sidebarSeparator.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarSeparator.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        configureSidebarContent(in: sidebar)
        configurePageContent(beside: sidebar)
    }

    private func configureSidebarContent(in sidebar: NSView) {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 22),
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
        ])

        let title = NSTextField(labelWithString: preferenceLocalized("Settings"))
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        stack.addArrangedSubview(title)
        stack.setCustomSpacing(22, after: title)

        addNavigationGroup(
            title: preferenceLocalized("Basics"),
            pages: [0, 1, 4],
            to: stack
        )
        addNavigationGroup(
            title: preferenceLocalized("Lyrics & Appearance"),
            pages: [2, 3, 5, 7],
            to: stack
        )
        addNavigationGroup(
            title: preferenceLocalized("Advanced"),
            pages: [6],
            to: stack
        )
    }

    private func addNavigationGroup(title: String, pages: [Int], to stack: NSStackView) {
        let groupTitle = NSTextField(labelWithString: title.uppercased())
        groupTitle.font = .systemFont(ofSize: 10, weight: .semibold)
        groupTitle.textColor = .secondaryLabelColor
        stack.addArrangedSubview(groupTitle)

        for page in pages where page < managedTabItems.count {
            let tabItem = managedTabItems[page]
            let button = NSButton(title: tabItem.label, target: self, action: #selector(navigationButtonPressed(_:)))
            button.tag = page
            button.image = tabItem.image
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.alignment = .left
            button.font = .systemFont(ofSize: 13, weight: .medium)
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 8
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setAccessibilityLabel(tabItem.label)
            stack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            button.heightAnchor.constraint(equalToConstant: 34).isActive = true
            navigationButtons[page] = button
        }

        if let lastPage = pages.last, let lastButton = navigationButtons[lastPage] {
            stack.setCustomSpacing(18, after: lastButton)
        }
    }

    private func configurePageContent(beside sidebar: NSView) {
        pageTitleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        pageTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        pageSubtitleLabel.font = .systemFont(ofSize: 12)
        pageSubtitleLabel.textColor = .secondaryLabelColor
        pageSubtitleLabel.maximumNumberOfLines = 2
        pageSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        tabView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageTitleLabel)
        view.addSubview(pageSubtitleLabel)
        view.addSubview(separator)

        NSLayoutConstraint.activate([
            pageTitleLabel.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 28),
            pageTitleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            pageTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -28),
            pageSubtitleLabel.leadingAnchor.constraint(equalTo: pageTitleLabel.leadingAnchor),
            pageSubtitleLabel.topAnchor.constraint(equalTo: pageTitleLabel.bottomAnchor, constant: 5),
            pageSubtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            separator.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separator.topAnchor.constraint(equalTo: view.topAnchor, constant: 78),
            tabView.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 16),
            tabView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tabView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            tabView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])
    }

    @objc private func navigationButtonPressed(_ sender: NSButton) {
        selectPage(sender.tag)
    }

    private func selectPage(_ index: Int) {
        guard managedTabItems.indices.contains(index) else { return }
        tabView.selectTabViewItem(managedTabItems[index])

        for (page, button) in navigationButtons {
            let isSelected = page == index
            button.layer?.backgroundColor = (
                isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.16) : NSColor.clear
            ).cgColor
            if #available(macOS 10.14, *) {
                button.contentTintColor = isSelected ? .controlAccentColor : .labelColor
            }
        }

        pageTitleLabel.stringValue = managedTabItems[index].label
        pageSubtitleLabel.stringValue = subtitle(for: index)
    }

    private func subtitle(for index: Int) -> String {
        let subtitles = [
            preferenceLocalized("Choose the player, file location, language, and app behavior."),
            preferenceLocalized("Configure how line lyrics and the lyrics window behave."),
            preferenceLocalized("Choose a line lyrics theme and refine its visual details."),
            preferenceLocalized("Set the lyrics window theme, typography, and motion."),
            preferenceLocalized("Customize keyboard shortcuts for frequent actions."),
            preferenceLocalized("Manage lyrics content that should be ignored."),
            preferenceLocalized("Try experimental features that may change."),
            preferenceLocalized("Adjust lyrics providers and their priority."),
        ]
        return subtitles.indices.contains(index) ? subtitles[index] : ""
    }
}

func preferenceLocalized(_ key: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: .main, value: key, comment: "Preferences UI")
}

class PreferenceViewController: NSViewController {
//    override func viewWillAppear() {
//        super.viewWillAppear()
//        view.subviews.first?.alphaValue = 0
//        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) {
//            self.view.subviews.first?.animator().alphaValue = 1
//        }
//    }
//
//    override func viewWillDisappear() {
//        super.viewWillDisappear()
//        view.subviews.first?.animator().alphaValue = 0
//    }
}
