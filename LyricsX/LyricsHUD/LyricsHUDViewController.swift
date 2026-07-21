import AppKit
import Combine
import GenericID
import MusicPlayer

class LyricsHUDViewController: NSViewController, NSWindowDelegate, ScrollLyricsViewDelegate, DragNDropDelegate {
    @IBOutlet var dragNDropView: DragNDropView!
    @IBOutlet var lyricsScrollView: ScrollLyricsView!
    @IBOutlet var noLyricsLabel: NSTextField!

    @IBOutlet var lyricsScrollViewTopMargin: NSLayoutConstraint!
    @IBOutlet var lyricsScrollViewLeftMargin: NSLayoutConstraint!

    private let amllOriginalLyricsView = AMLLOriginalLyricsWebView(frame: .zero)
    private let systemMediaArtworkProvider = MusicPlayers.SystemMedia()

    @objc dynamic var isTracking = true {
        didSet {
            if !oldValue, isTracking {
                displayLyrics()
            }
        }
    }

    private var isWillTerminate = false

    private var cancelBag = Set<AnyCancellable>()
    private var amllOriginalTimer: AnyCancellable?

    override func awakeFromNib() {
        super.awakeFromNib()

        view.window?.do {
            $0.title = "Lyrics Window"
            $0.titlebarAppearsTransparent = true
//            $0.titleVisibility = .hidden
            $0.styleMask.insert(.borderless)
            $0.delegate = self
        }
        restoreWindowPlacement()
        setupThemeBackgroundViews()
        // swiftlint:disable:next force_cast
        let accessory = NSStoryboard.main!.instantiateController(withIdentifier: .lyricsHUDAccessory) as! NSTitlebarAccessoryViewController
        accessory.layoutAttribute = .right
        view.window?.addTitlebarAccessoryViewController(accessory)

        dragNDropView.dragDelegate = self
        lyricsScrollView.delegate = self
        lyricsScrollView.setupTextContents(lyrics: AppController.shared.currentLyrics)

        observeDefaults(keys: [
            .lyricsWindowTheme,
            .lyricsWindowFontName,
            .lyricsWindowFontSize,
            .lyricsWindowTextColor,
            .lyricsWindowHighlightColor,
            .lyricsWindowAMLLOriginalFontName,
            .lyricsWindowAMLLOriginalFontSize,
            .lyricsWindowAMLLDynamicAlignment,
            .lyricsWindowAMLLDynamicLineSpacing,
            .lyricsWindowAMLLDynamicMotionAmount,
        ], options: [.initial]) { [unowned self] in
            self.reloadLyricsWindowAppearance()
        }
        observeNotification(name: .lyricsWindowAppearanceDidChange, queue: .main) { [unowned self] _ in
            self.reloadLyricsWindowAppearance()
        }
        selectedPlayer.currentTrackWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.pushAMLLOriginalState()
            }
            .store(in: &cancelBag)
        systemMediaArtworkProvider?.currentTrackWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.pushAMLLOriginalState()
            }
            .store(in: &cancelBag)

        AppController.shared.$currentLyrics
            .signal()
            .receive(on: DispatchQueue.main)
            .invoke(LyricsHUDViewController.lyricsChanged, weaklyOn: self)
            .store(in: &cancelBag)
        AppController.shared.$currentLineIndex
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in
                self.displayLyrics()
            }.store(in: &cancelBag)

        observeNotification(
            name: NSScrollView.willStartLiveScrollNotification,
            object: lyricsScrollView,
            queue: .main
        ) { [unowned self] _ in self.isTracking = false }
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillTerminate(_:)), name: NSApplication.willTerminateNotification, object: nil)
    }

    private func setupThemeBackgroundViews() {
        view.wantsLayer = true

        view.addSubview(amllOriginalLyricsView, positioned: .above, relativeTo: nil)
        amllOriginalLyricsView.translatesAutoresizingMaskIntoConstraints = false
        amllOriginalLyricsView.isHidden = true

        NSLayoutConstraint.activate([
            amllOriginalLyricsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            amllOriginalLyricsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            amllOriginalLyricsView.topAnchor.constraint(equalTo: view.topAnchor),
            amllOriginalLyricsView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func restoreWindowPlacement() {
        guard let window = view.window,
              let frame = LyricsWindowPlacementStore.restoredWindowFrame(
                  key: .lyricsHUD,
                  minimumSize: NSSize(width: 320, height: 280)
              ) else {
            return
        }
        window.setFrame(frame, display: false)
    }

    private func saveWindowPlacement() {
        guard let window = view.window else {
            return
        }
        LyricsWindowPlacementStore.saveWindow(window, key: .lyricsHUD)
    }

    private func showAMLLOriginalWebView() {
        amllOriginalLyricsView.isHidden = false
        if defaults[.isShowLyricsHUD] {
            view.window?.makeKeyAndOrderFront(nil)
        }
        updateAMLLOriginalTimer(enabled: true)
        pushAMLLOriginalState()
    }

    private func closeAMLLOriginalWebView() {
        amllOriginalLyricsView.isHidden = true
        updateAMLLOriginalTimer(enabled: false)
    }

    private func reloadLyricsWindowAppearance() {
        applyLyricsWindowAppearance()
    }

    private func applyLyricsWindowAppearance() {
        let theme = normalizedLyricsWindowTheme()
        let amllAlignment = LyricsWindowAMLLAlignment(rawValue: defaults[.lyricsWindowAMLLDynamicAlignment]) ?? .left
        let amllLineSpacing = CGFloat(defaults[.lyricsWindowAMLLDynamicLineSpacing]).clamped(to: 0.7...1.6)
        let amllMotion = CGFloat(defaults[.lyricsWindowAMLLDynamicMotionAmount]).clamped(to: 0...1.5)
        if theme == .amllOriginalSource {
            lyricsScrollView.isHidden = true
            noLyricsLabel.isHidden = true
            view.layer?.cornerRadius = 0
            view.layer?.masksToBounds = false
            view.window?.backgroundColor = .clear
            view.window?.isOpaque = false
            amllOriginalLyricsView.setVisualOptions(
                alignment: amllAlignment,
                lineSpacing: amllLineSpacing,
                motionAmount: amllMotion,
                font: defaults.lyricsWindowAMLLOriginalFont
            )
            showAMLLOriginalWebView()
            return
        }

        closeAMLLOriginalWebView()
        lyricsScrollView.isHidden = false
        noLyricsLabel.isHidden = AppController.shared.currentLyrics != nil
        if defaults[.isShowLyricsHUD] {
            view.window?.makeKeyAndOrderFront(nil)
        }

        let font = defaults.lyricsWindowFont
        let textColor = defaults.color(for: .lyricsWindowTextColor, fallback: #colorLiteral(red: 0.7540688515, green: 0.7540867925, blue: 0.7540771365, alpha: 1))
        let highlightColor = defaults.color(for: .lyricsWindowHighlightColor, fallback: #colorLiteral(red: 0.8866666667, green: 1, blue: 0.8, alpha: 1))
        lyricsScrollView.visualStyle = .classic
        lyricsScrollView.fontName = font.fontName
        lyricsScrollView.fontSize = font.pointSize
        lyricsScrollView.textColor = textColor
        lyricsScrollView.highlightColor = highlightColor
        lyricsScrollView.lyricAlignment = .center
        lyricsScrollView.lineSpacingScale = 1
        lyricsScrollView.animationAmount = 1
        noLyricsLabel.textColor = textColor
        noLyricsLabel.font = NSFont.systemFont(ofSize: max(13, font.pointSize * 0.58))
        lyricsScrollViewTopMargin.constant = font.pointSize
        lyricsScrollViewLeftMargin.constant = font.pointSize
        view.layer?.cornerRadius = 0
        view.layer?.masksToBounds = false
        updateAMLLOriginalTimer(enabled: false)
        pushAMLLOriginalState()
        displayLyrics(animation: false)
    }

    private func normalizedLyricsWindowTheme() -> LyricsWindowTheme {
        let rawValue = defaults[.lyricsWindowTheme]
        if rawValue == 1 || rawValue == 2 {
            defaults[.lyricsWindowTheme] = LyricsWindowTheme.amllOriginalSource.rawValue
            return .amllOriginalSource
        }
        return LyricsWindowTheme(rawValue: rawValue) ?? .classic
    }

    private func artworkImage(for track: MusicTrack) -> (image: NSImage, source: String)? {
        if let artwork = track.artwork {
            return (artwork, "player")
        }
        guard let systemTrack = systemMediaArtworkProvider?.currentTrack,
              tracksLikelyMatch(track, systemTrack),
              let artwork = systemTrack.artwork else {
            return nil
        }
        return (artwork, "system-now-playing")
    }

    private func tracksLikelyMatch(_ lhs: MusicTrack, _ rhs: MusicTrack) -> Bool {
        if lhs.id == rhs.id {
            return true
        }

        let lhsTitle = normalizedTrackField(lhs.title)
        let rhsTitle = normalizedTrackField(rhs.title)
        guard !lhsTitle.isEmpty, lhsTitle == rhsTitle else {
            return false
        }

        let lhsArtist = normalizedTrackField(lhs.artist)
        let rhsArtist = normalizedTrackField(rhs.artist)
        let lhsAlbum = normalizedTrackField(lhs.album)
        let rhsAlbum = normalizedTrackField(rhs.album)

        if !lhsArtist.isEmpty, !rhsArtist.isEmpty {
            return lhsArtist == rhsArtist
        }
        if !lhsAlbum.isEmpty, !rhsAlbum.isEmpty {
            return lhsAlbum == rhsAlbum
        }
        return true
    }

    private func normalizedTrackField(_ value: String?) -> String {
        return (value ?? "")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    override func viewWillAppear() {
        let isOriginalSource = normalizedLyricsWindowTheme() == .amllOriginalSource
        let isUsingOriginalSourceWebView = isOriginalSource && !amllOriginalLyricsView.isHidden
        noLyricsLabel.isHidden = isUsingOriginalSourceWebView ? true : AppController.shared.currentLyrics != nil
        displayLyrics(animation: false)
    }

    // MARK: - Handler

    private func lyricsChanged() {
        DispatchQueue.main.async {
            let newLyrics = AppController.shared.currentLyrics
            self.lyricsScrollView.setupTextContents(lyrics: newLyrics)
            self.amllOriginalLyricsView.setLyrics(newLyrics, trackDuration: selectedPlayer.currentTrack?.duration)
            let isOriginalSource = self.normalizedLyricsWindowTheme() == .amllOriginalSource
            let isUsingOriginalSourceWebView = isOriginalSource && !self.amllOriginalLyricsView.isHidden
            self.noLyricsLabel.isHidden = isUsingOriginalSourceWebView ? true : newLyrics != nil
            self.displayLyrics(animation: false)
        }
    }

    private func displayLyrics(animation: Bool = true) {
        var pos = selectedPlayer.playbackTime
        pos += AppController.shared.currentLyrics?.adjustedTimeDelay ?? 0
        let theme = normalizedLyricsWindowTheme()
        if theme == .amllOriginalSource {
            amllOriginalLyricsView.setCurrentTime(pos)
            return
        }
        lyricsScrollView.highlight(position: pos)
        guard isTracking else {
            return
        }
        if animation {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.allowsImplicitAnimation = true
                context.timingFunction = .swiftOut
                self.lyricsScrollView.scroll(position: pos)
            }
        } else {
            lyricsScrollView.scroll(position: pos)
        }
    }

    private func updateAMLLOriginalTimer(enabled: Bool) {
        if enabled {
            guard amllOriginalTimer == nil else {
                return
            }
            amllOriginalTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    self?.pushAMLLOriginalPlaybackTime()
                }
        } else {
            amllOriginalTimer?.cancel()
            amllOriginalTimer = nil
        }
    }

    private func pushAMLLOriginalState() {
        guard normalizedLyricsWindowTheme() == .amllOriginalSource else {
            return
        }
        amllOriginalLyricsView.setLyrics(AppController.shared.currentLyrics, trackDuration: selectedPlayer.currentTrack?.duration)
        if let track = selectedPlayer.currentTrack ?? systemMediaArtworkProvider?.currentTrack {
            amllOriginalLyricsView.setAlbumImage(artworkImage(for: track)?.image)
        }
        pushAMLLOriginalPlaybackTime()
    }

    private func pushAMLLOriginalPlaybackTime() {
        var pos = selectedPlayer.playbackTime
        pos += AppController.shared.currentLyrics?.adjustedTimeDelay ?? 0
        amllOriginalLyricsView.setCurrentTime(pos)
        amllOriginalLyricsView.setPlaying(selectedPlayer.playbackState.isPlaying)
    }

    // MARK: ScrollLyricsViewDelegate

    func doubleClickLyricsLine(at position: TimeInterval) {
        let pos = position - (AppController.shared.currentLyrics?.adjustedTimeDelay ?? 0)
        selectedPlayer.playbackTime = pos
        isTracking = true
    }

    func scrollWheelDidStartScroll() {
        isTracking = false
    }

    func scrollWheelDidEndScroll() {}

    // MARK: NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        saveWindowPlacement()
        DispatchQueue.main.async {
            self.displayLyrics(animation: false)
        }
    }

    func windowDidMove(_ notification: Notification) {
        saveWindowPlacement()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        saveWindowPlacement()
    }

    // MARK: DragNDropDelegate

    func dragFinished(content: String) {
        do {
            try AppController.shared.importLyrics(content)
        } catch {
            let alert = NSAlert(error: error)
            alert.beginSheetModal(for: view.window!)
        }
    }

    func windowWillClose(_ notification: Notification) {
        saveWindowPlacement()
        closeAMLLOriginalWebView()
        guard !isWillTerminate else { return }
        defaults[.isShowLyricsHUD] = false
    }

    @objc func applicationWillTerminate(_ notification: Notification) {
        saveWindowPlacement()
        isWillTerminate = true
    }
}

class LyricsHUDAccessoryViewController: NSTitlebarAccessoryViewController {
    @IBAction func lockAction(_ sender: NSButton) {
        if sender.state == .on {
            view.window?.level = .modalPanel
        } else {
            view.window?.level = .normal
        }
    }
}
