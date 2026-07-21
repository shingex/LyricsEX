import AppKit
import Combine
import GenericID
import LyricsXFoundation
import MusicPlayer
import OpenCC
import SnapKit
import SwiftCF
import CoreGraphicsExt

private final class KaraokeLyricsWindow: NSWindow {
    weak var lyricsView: KaraokeLyricsView?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .rightMouseDown,
           lyricsView?.popDragHandleMenuIfNeeded(with: event) == true {
            return
        }
        super.sendEvent(event)
    }
}

private final class AlbumColorRenderToken {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

class KaraokeLyricsWindowController: NSWindowController {
    private static let windowFrame = NSWindow.FrameAutosaveName("KaraokeWindow")
    private static let dragHandleSafeInset: CGFloat = 11
    private static let minimumInterludeDuration: TimeInterval = 5

    private var lyricsView = KaraokeLyricsView(frame: .zero)

    private var cancelBag = Set<AnyCancellable>()
    private var interludeStartSchedule: Cancellable?
    private var modernAlbumColor: NSColor?
    private var modernAlbumArtwork: CGImage?
    private var albumBlurProgressColors: [NSColor]?
    private var albumBlurAmount: Double?
    private var modernAlbumColorTrackID: String?
    private var modernAlbumColorGeneration = 0
    private var modernAlbumColorRenderToken: AlbumColorRenderToken?
    private let modernAlbumColorQueue = DispatchQueue(label: "com.lyricsx.desktopLyrics.albumColor", qos: .userInitiated)
    private let systemMediaArtworkProvider = MusicPlayers.SystemMedia()

    init() {
        let window = KaraokeLyricsWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isOpaque = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.setFrameUsingName(KaraokeLyricsWindowController.windowFrame, force: true)
        super.init(window: window)

        window.lyricsView = lyricsView
        window.contentView?.addSubview(lyricsView)
        lyricsView.dragHandleMenuProvider = {
            AppDelegate.shared?.statusBarMenu
        }

        addObserver()
        restoreDesktopLyricsPlacement(animate: false)

        lyricsView.displayLrc("LyricsX")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.lyricsView.displayLrc("")
            AppController.shared.$currentLyrics
                .signal()
                .receive(on: DispatchQueue.lyricsDisplay)
                .invoke(KaraokeLyricsWindowController.handleLyricsDisplay, weaklyOn: self)
                .store(in: &self.cancelBag)
            AppController.shared.$currentLineIndex
                .signal()
                .receive(on: DispatchQueue.lyricsDisplay)
                .invoke(KaraokeLyricsWindowController.handleLyricsDisplay, weaklyOn: self)
                .store(in: &self.cancelBag)
            selectedPlayer.playbackStateWillChange
                .signal()
                .receive(on: DispatchQueue.lyricsDisplay)
                .invoke(KaraokeLyricsWindowController.handleLyricsDisplay, weaklyOn: self)
                .store(in: &self.cancelBag)
            defaults.publisher(for: [.preferBilingualLyrics, .desktopLyricsOneLineMode])
                .prepend()
                .invoke(KaraokeLyricsWindowController.handleLyricsDisplay, weaklyOn: self)
                .store(in: &self.cancelBag)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func addObserver() {
        lyricsView.bind(\.isVertical, withDefaultName: .desktopLyricsVerticalMode, options: [.nullPlaceholder: false])
        lyricsView.bind(\.drawFurigana, withDefaultName: .desktopLyricsEnableFurigana, options: [.nullPlaceholder: false])
        lyricsView.bind(\.drawRomajin, withDefaultName: .desktopLyricsEnableRomajin, options: [.nullPlaceholder: false])

        let negateOption = [NSBindingOption.valueTransformerName: NSValueTransformerName.negateBooleanTransformerName]
        window?.contentView?.bind(.hidden, withDefaultName: .desktopLyricsEnabled, options: negateOption)

        observeDefaults(key: .disableLyricsWhenSreenShot, options: [.new, .initial]) { [unowned self] _, change in
            self.window?.sharingType = change.newValue ? .none : .readOnly
        }
        observeDefaults(keys: [
            .hideLyricsWhenMousePassingBy,
            .desktopLyricsDraggable,
        ], options: [.initial]) {
            self.lyricsView.shouldHideWithMouse = defaults[.hideLyricsWhenMousePassingBy]
            self.lyricsView.showsDragHandleWhenMouseHidden = defaults[.hideLyricsWhenMousePassingBy] && defaults[.desktopLyricsDraggable]
        }
        observeDefaults(keys: [
            .desktopLyricsFontName,
            .desktopLyricsFontSize,
            .desktopLyricsFontNameFallback,
            .desktopLyricsColor,
            .desktopLyricsProgressColor,
            .desktopLyricsShadowColor,
            .desktopLyricsBackgroundColor,
            .desktopLyricsInactiveLineBlurRadius,
            .desktopLyricsTheme,
            .desktopLyricsModernFontName,
            .desktopLyricsModernFontSize,
            .desktopLyricsModernTextColor,
            .desktopLyricsModernProgressColor,
            .desktopLyricsModernBackgroundColor,
            .desktopLyricsModernBackgroundOpacity,
            .desktopLyricsModernBlurEnabled,
            .desktopLyricsModernCornerRadius,
            .desktopLyricsModernInactiveLineBlurRadius,
            .desktopLyricsAlbumBlurFontName,
            .desktopLyricsAlbumBlurFontSize,
            .desktopLyricsAlbumBlurTextColor,
            .desktopLyricsAlbumBlurProgressColor,
            .desktopLyricsAlbumBlurTintColor,
            .desktopLyricsAlbumBlurFallbackColor,
            .desktopLyricsAlbumBlurBackgroundOpacity,
            .desktopLyricsAlbumBlurDimAmount,
            .desktopLyricsAlbumBlurBlurAmount,
            .desktopLyricsAlbumBlurCornerRadius,
            .desktopLyricsAlbumBlurInactiveLineBlurRadius,
            .desktopLyricsAlbumBlurReverseProgressGradient,
            .desktopLyricsAMLLDynamicFontName,
            .desktopLyricsAMLLDynamicFontSize,
            .desktopLyricsAMLLDynamicTextColor,
            .desktopLyricsAMLLDynamicProgressColor,
            .desktopLyricsAMLLDynamicTintColor,
            .desktopLyricsAMLLDynamicFallbackColor,
            .desktopLyricsAMLLDynamicBackgroundOpacity,
            .desktopLyricsAMLLDynamicDimAmount,
            .desktopLyricsAMLLDynamicFlowSpeed,
            .desktopLyricsAMLLDynamicIntensity,
            .desktopLyricsAMLLDynamicCornerRadius,
            .desktopLyricsAMLLDynamicInactiveLineBlurRadius,
            .desktopLyricsAMLLDynamicReverseProgressGradient,
        ], options: [.initial]) { [unowned self] in
            self.reloadDesktopLyricsAppearance()
        }
        selectedPlayer.currentTrackWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                self?.refreshModernAlbumColor(for: track)
            }
            .store(in: &cancelBag)
        systemMediaArtworkProvider?.currentTrackWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshModernAlbumColor()
            }
            .store(in: &cancelBag)

        observeNotification(name: NSApplication.didChangeScreenParametersNotification, queue: .main) { [unowned self] _ in
            self.restoreDesktopLyricsPlacement(animate: true)
        }
        observeNotification(center: workspaceNC, name: NSWorkspace.activeSpaceDidChangeNotification, queue: .main) { [unowned self] _ in
            self.updateWindowFrame(animate: true)
        }
    }

    private func reloadDesktopLyricsAppearance() {
        refreshModernAlbumColor()
        applyDesktopLyricsAppearance()
        refreshDisplayedProgress()
    }

    private func applyDesktopLyricsAppearance() {
        let theme = DesktopLyricsTheme(rawValue: defaults[.desktopLyricsTheme]) ?? .classic
        lyricsView.theme = theme.rawValue

        switch theme {
        case .classic:
            lyricsView.modernAlbumArtwork = nil
            lyricsView.progressGradientColors = nil
            lyricsView.reversesProgressGradient = false
            lyricsView.font = defaults.desktopLyricsFont
            lyricsView.textColor = defaults.color(for: .desktopLyricsColor, fallback: .white)
            lyricsView.progressColor = defaults.color(for: .desktopLyricsProgressColor, fallback: #colorLiteral(red: 0.1985405816, green: 1, blue: 0.8664234302, alpha: 1))
            lyricsView.shadowColor = defaults.color(for: .desktopLyricsShadowColor, fallback: #colorLiteral(red: 0, green: 1, blue: 0.8333333333, alpha: 1))
            lyricsView.backgroundColor = defaults.color(for: .desktopLyricsBackgroundColor, fallback: #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0.6041579279))
            lyricsView.inactiveLineBlurRadius = CGFloat(defaults[.desktopLyricsInactiveLineBlurRadius]).clamped(to: 0...2)
        case .modern:
            lyricsView.modernAlbumArtwork = nil
            lyricsView.progressGradientColors = nil
            lyricsView.reversesProgressGradient = false
            lyricsView.font = defaults.desktopLyricsModernFont
            lyricsView.textColor = defaults.color(for: .desktopLyricsModernTextColor, fallback: .white)
            lyricsView.progressColor = defaults.color(for: .desktopLyricsModernProgressColor, fallback: desktopLyricsModernDefaultProgressColor)
            lyricsView.shadowColor = .clear
            let fallbackColor = defaults.color(for: .desktopLyricsModernBackgroundColor, fallback: NSColor(calibratedRed: 0.176, green: 0.235, blue: 0.8, alpha: 1))
            lyricsView.backgroundColor = fallbackColor
            lyricsView.modernBackgroundOpacity = CGFloat(defaults[.desktopLyricsModernBackgroundOpacity])
            lyricsView.albumBlurDimAmount = CGFloat(defaults[.desktopLyricsAlbumBlurDimAmount])
            lyricsView.modernBlurEnabled = defaults[.desktopLyricsModernBlurEnabled]
            lyricsView.modernCornerRadius = CGFloat(defaults[.desktopLyricsModernCornerRadius])
            lyricsView.inactiveLineBlurRadius = CGFloat(defaults[.desktopLyricsModernInactiveLineBlurRadius]).clamped(to: 0...2)
        case .albumBlur:
            lyricsView.font = defaults.desktopLyricsAlbumBlurFont
            lyricsView.textColor = defaults.color(for: .desktopLyricsAlbumBlurTextColor, fallback: .white)
            lyricsView.progressColor = defaults.color(for: .desktopLyricsAlbumBlurProgressColor, fallback: desktopLyricsAlbumBlurDefaultProgressColor)
            lyricsView.progressGradientColors = albumBlurProgressColors
            lyricsView.reversesProgressGradient = defaults[.desktopLyricsAlbumBlurReverseProgressGradient]
            lyricsView.shadowColor = .clear
            let fallbackColor = defaults.color(for: .desktopLyricsAlbumBlurFallbackColor, fallback: NSColor(calibratedRed: 0.176, green: 0.235, blue: 0.8, alpha: 1))
            let albumArtwork = modernAlbumArtwork
            lyricsView.backgroundColor = albumArtwork == nil
                ? modernAlbumColor ?? fallbackColor
                : defaults.color(for: .desktopLyricsAlbumBlurTintColor, fallback: .black)
            lyricsView.modernAlbumArtwork = albumArtwork
            lyricsView.modernBackgroundOpacity = CGFloat(defaults[.desktopLyricsAlbumBlurBackgroundOpacity])
            lyricsView.albumBlurDimAmount = CGFloat(defaults[.desktopLyricsAlbumBlurDimAmount])
            lyricsView.modernBlurEnabled = false
            lyricsView.modernCornerRadius = CGFloat(defaults[.desktopLyricsAlbumBlurCornerRadius])
            lyricsView.inactiveLineBlurRadius = CGFloat(defaults[.desktopLyricsAlbumBlurInactiveLineBlurRadius]).clamped(to: 0...2)
            lyricsView.amllDynamicColors = nil
        case .amllDynamic:
            lyricsView.font = defaults.desktopLyricsAMLLDynamicFont
            lyricsView.textColor = defaults.color(for: .desktopLyricsAMLLDynamicTextColor, fallback: .white)
            lyricsView.progressColor = defaults.color(for: .desktopLyricsAMLLDynamicProgressColor, fallback: desktopLyricsAMLLDynamicDefaultProgressColor)
            lyricsView.progressGradientColors = albumBlurProgressColors
            lyricsView.reversesProgressGradient = defaults[.desktopLyricsAMLLDynamicReverseProgressGradient]
            lyricsView.shadowColor = .clear
            let fallbackColor = defaults.color(for: .desktopLyricsAMLLDynamicFallbackColor, fallback: desktopLyricsAMLLDynamicDefaultFallbackColor)
            let tintColor = defaults.color(for: .desktopLyricsAMLLDynamicTintColor, fallback: .black)
            lyricsView.backgroundColor = modernAlbumColor ?? fallbackColor
            lyricsView.modernAlbumArtwork = nil
            lyricsView.modernBackgroundOpacity = CGFloat(defaults[.desktopLyricsAMLLDynamicBackgroundOpacity])
            lyricsView.albumBlurDimAmount = CGFloat(defaults[.desktopLyricsAlbumBlurDimAmount])
            lyricsView.modernBlurEnabled = false
            lyricsView.modernCornerRadius = CGFloat(defaults[.desktopLyricsAMLLDynamicCornerRadius])
            lyricsView.inactiveLineBlurRadius = CGFloat(defaults[.desktopLyricsAMLLDynamicInactiveLineBlurRadius]).clamped(to: 0...2)
            lyricsView.amllDynamicDimAmount = CGFloat(defaults[.desktopLyricsAMLLDynamicDimAmount])
            lyricsView.amllDynamicFlowSpeed = CGFloat(defaults[.desktopLyricsAMLLDynamicFlowSpeed])
            lyricsView.amllDynamicIntensity = CGFloat(defaults[.desktopLyricsAMLLDynamicIntensity])
            lyricsView.amllDynamicColors = amllDynamicPalette(fallback: fallbackColor, tint: tintColor)
        }
    }

    private func refreshModernAlbumColor() {
        refreshModernAlbumColor(for: selectedPlayer.currentTrack)
    }

    private func refreshModernAlbumColor(for track: MusicTrack?) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.refreshModernAlbumColor(for: track)
            }
            return
        }

        let theme = DesktopLyricsTheme(rawValue: defaults[.desktopLyricsTheme]) ?? .classic
        guard theme.usesAlbumDerivedPalette else {
            modernAlbumColorRenderToken?.cancel()
            modernAlbumColorRenderToken = nil
            modernAlbumColor = nil
            modernAlbumArtwork = nil
            albumBlurProgressColors = nil
            albumBlurAmount = nil
            modernAlbumColorTrackID = nil
            modernAlbumColorGeneration += 1
            applyDesktopLyricsAppearance()
            return
        }

        guard let track = track else {
            modernAlbumColorRenderToken?.cancel()
            modernAlbumColorRenderToken = nil
            modernAlbumColor = nil
            modernAlbumArtwork = nil
            albumBlurProgressColors = nil
            albumBlurAmount = nil
            modernAlbumColorTrackID = nil
            modernAlbumColorGeneration += 1
            applyDesktopLyricsAppearance()
            return
        }

        let blurAmount = theme == .albumBlur ? defaults[.desktopLyricsAlbumBlurBlurAmount] : -1
        let canReuseAlbumPalette = theme == .albumBlur
            && modernAlbumColorTrackID == track.id
            && modernAlbumColor != nil
            && albumBlurProgressColors != nil
        let shouldDebounceBlurRender = canReuseAlbumPalette
            && albumBlurAmount != nil
            && albumBlurAmount != blurAmount
        guard modernAlbumColorTrackID != track.id
            || modernAlbumColor == nil
            || (theme == .albumBlur && modernAlbumArtwork == nil)
            || albumBlurProgressColors == nil
            || albumBlurAmount != blurAmount else {
            applyDesktopLyricsAppearance()
            return
        }

        modernAlbumColorRenderToken?.cancel()
        modernAlbumColorRenderToken = nil
        modernAlbumColorTrackID = track.id
        let cachedColor = canReuseAlbumPalette ? modernAlbumColor : nil
        let cachedProgressColors = canReuseAlbumPalette ? albumBlurProgressColors : nil
        if !shouldDebounceBlurRender {
            modernAlbumColor = nil
            modernAlbumArtwork = nil
            albumBlurProgressColors = nil
        }
        albumBlurAmount = blurAmount
        modernAlbumColorGeneration += 1
        let generation = modernAlbumColorGeneration
        let trackID = track.id
        applyDesktopLyricsAppearance()

        guard let artworkResult = artworkImage(for: track),
              let cgImage = DesktopLyricsAlbumColorExtractor.cgImage(from: artworkResult.image) else {
            log("DesktopLyrics modern album background: no artwork available")
            return
        }
        log("DesktopLyrics modern album background: artwork source=\(artworkResult.source) size=\(Int(artworkResult.image.size.width))x\(Int(artworkResult.image.size.height))")

        let renderToken = AlbumColorRenderToken()
        modernAlbumColorRenderToken = renderToken
        modernAlbumColorQueue.asyncAfter(deadline: .now() + (shouldDebounceBlurRender ? .milliseconds(140) : .milliseconds(0))) { [weak self] in
            guard !renderToken.isCancelled else {
                return
            }

            let color = cachedColor ?? DesktopLyricsAlbumColorExtractor.backgroundColor(from: cgImage)
            let progressColors = cachedProgressColors ?? DesktopLyricsAlbumColorExtractor.progressColors(from: cgImage)
            guard !renderToken.isCancelled else {
                return
            }

            let artwork = theme == .albumBlur
                ? DesktopLyricsAlbumColorExtractor.blurredArtwork(from: cgImage, blurAmount: blurAmount)
                : nil
            guard !renderToken.isCancelled else {
                return
            }

            DispatchQueue.main.async {
                guard let self = self,
                      self.modernAlbumColorRenderToken === renderToken,
                      self.modernAlbumColorGeneration == generation,
                      self.modernAlbumColorTrackID == trackID else {
                    return
                }
                self.modernAlbumColorRenderToken = nil
                self.modernAlbumColor = color
                self.modernAlbumArtwork = artwork
                self.albumBlurProgressColors = progressColors
                log("DesktopLyrics modern album progress colors: \(self.progressColorSummary(progressColors))")
                self.applyDesktopLyricsAppearance()
                self.refreshDisplayedProgress()
            }
        }
    }

    private func amllDynamicPalette(fallback: NSColor, tint: NSColor) -> [NSColor] {
        var colors = [NSColor]()
        if let modernAlbumColor {
            colors.append(modernAlbumColor)
        } else {
            colors.append(fallback)
        }
        colors.append(contentsOf: albumBlurProgressColors ?? [defaults.color(for: .desktopLyricsAMLLDynamicProgressColor, fallback: desktopLyricsAMLLDynamicDefaultProgressColor)])
        colors.append(tint)
        return colors
    }

    private func progressColorSummary(_ colors: [NSColor]) -> String {
        return colors
            .compactMap { $0.usingColorSpace(.deviceRGB) }
            .map {
                String(
                    format: "#%02X%02X%02X",
                    Int($0.redComponent * 255),
                    Int($0.greenComponent * 255),
                    Int($0.blueComponent * 255)
                )
            }
            .joined(separator: ", ")
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

    private func refreshDisplayedProgress() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.refreshDisplayedProgress()
            }
            return
        }
        guard defaults[.desktopLyricsEnabled],
              !defaults[.disableLyricsWhenPaused] || selectedPlayer.playbackState.isPlaying,
              let lyrics = AppController.shared.currentLyrics,
              let index = AppController.shared.currentLineIndex,
              let upperTextField = lyricsView.displayLine1 else {
            lyricsView.refreshProgressColor()
            return
        }

        let position = selectedPlayer.playbackTime
        let timeDelay = lyrics.adjustedTimeDelay
        guard let progress = progressPoints(forLineAt: index, position: position, timeDelay: timeDelay) else {
            lyricsView.refreshProgressColor()
            return
        }
        setProgressAnimation(on: upperTextField, progress: progress)
        if !selectedPlayer.playbackState.isPlaying {
            upperTextField.pauseProgressAnimation()
        }
    }

    private func updateWindowFrame(toScreen: NSScreen? = nil, animate: Bool) {
        let screen = toScreen ?? window?.screen ?? NSScreen.screens[0]
        let fullScreen = screen.isFullScreen || defaults.bool(forKey: "DesktopLyricsIgnoreSafeArea")
        let frame = fullScreen ? screen.frame : screen.visibleFrame
        window?.setFrame(frame, display: false, animate: animate)
        window?.saveFrame(usingName: KaraokeLyricsWindowController.windowFrame)
    }

    private func restoreDesktopLyricsPlacement(animate: Bool) {
        if let placement = LyricsWindowPlacementStore.restoreDesktopLyrics() {
            defaults[.desktopLyricsXPositionFactor] = placement.xFactor
            defaults[.desktopLyricsYPositionFactor] = placement.yFactor
            updateWindowFrame(toScreen: placement.screen, animate: animate)
        } else {
            updateWindowFrame(animate: animate)
            if let screen = window?.screen ?? NSScreen.main {
                LyricsWindowPlacementStore.saveDesktopLyrics(
                    screen: screen,
                    xFactor: defaults[.desktopLyricsXPositionFactor],
                    yFactor: defaults[.desktopLyricsYPositionFactor]
                )
            }
        }
        makeConstraints()
        window?.layoutIfNeeded()
    }

    @objc private func handleLyricsDisplay() {
        interludeStartSchedule?.cancel()
        interludeStartSchedule = nil

        guard defaults[.desktopLyricsEnabled],
              !defaults[.disableLyricsWhenPaused] || selectedPlayer.playbackState.isPlaying,
              let lyrics = AppController.shared.currentLyrics else {
            DispatchQueue.main.async {
                self.lyricsView.displayLrc("", secondLine: "")
            }
            return
        }

        let playbackState = selectedPlayer.playbackState
        let lyricPosition = playbackState.time + lyrics.adjustedTimeDelay
        guard let index = AppController.shared.currentLineIndex else {
            let firstLine = lyrics.lines.first { $0.enabled }
            let hasLongPrelude = firstLine.map {
                $0.position >= Self.minimumInterludeDuration && lyricPosition < $0.position
            } == true
            DispatchQueue.main.async {
                if hasLongPrelude, let firstLine {
                    self.lyricsView.displayLrc(
                        "",
                        secondLine: self.convertedLyricContent(firstLine.content, lyrics: lyrics),
                        interludePlacement: .firstLine,
                        isPlaying: playbackState.isPlaying
                    )
                } else {
                    self.lyricsView.displayLrc("", secondLine: "")
                }
            }
            return
        }

        let lrc = lyrics.lines[index]
        let next = lyrics.lines[(index + 1)...].first { $0.enabled }

        let longInterlude = interludeInterval(after: lrc, before: next)
        let isInsideInterlude = longInterlude?.contains(lyricPosition) == true
        let isBeforeInterlude = longInterlude.map { lyricPosition < $0.lowerBound } == true
        if let interval = longInterlude {
            if playbackState.isPlaying, lyricPosition < interval.lowerBound {
                scheduleInterludeStart(after: interval.lowerBound - lyricPosition)
            }
        }

        if isInsideInterlude, let next {
            let nextContent = convertedLyricContent(next.content, lyrics: lyrics)
            DispatchQueue.main.async {
                self.lyricsView.displayLrc(
                    "",
                    secondLine: nextContent,
                    interludePlacement: .firstLine,
                    isPlaying: playbackState.isPlaying
                )
            }
            return
        }

        let languageCode = lyrics.metadata.translationLanguages.first

        var firstLine = lrc.content
        var secondLine: String
        var secondLineIsTranslation = false
        if defaults[.desktopLyricsOneLineMode] {
            secondLine = ""
        } else if defaults[.preferBilingualLyrics],
                  let translation = lrc.attachments[.translation(languageCode: languageCode)] {
            secondLine = translation
            secondLineIsTranslation = true
        } else {
            secondLine = next?.content ?? ""
        }

        if let converter = ChineseConverter.shared {
            if lyrics.metadata.language?.hasPrefix("zh") == true {
                firstLine = converter.convert(firstLine)
                if !secondLineIsTranslation {
                    secondLine = converter.convert(secondLine)
                }
            }
            if languageCode?.hasPrefix("zh") == true {
                secondLine = converter.convert(secondLine)
            }
        }

        DispatchQueue.main.async {
            self.lyricsView.displayLrc(
                firstLine,
                secondLine: secondLine,
                interludePlacement: isBeforeInterlude ? .secondLine : nil,
                isPlaying: playbackState.isPlaying
            )
            if let upperTextField = self.lyricsView.displayLine1 {
                let position = selectedPlayer.playbackTime
                let timeDelay = AppController.shared.currentLyrics?.adjustedTimeDelay ?? 0
                if let progress = self.progressPoints(forLineAt: index, position: position, timeDelay: timeDelay) {
                    self.setProgressAnimation(on: upperTextField, progress: progress)
                }
                if !selectedPlayer.playbackState.isPlaying {
                    upperTextField.pauseProgressAnimation()
                }
            }
        }
    }

    private func convertedLyricContent(_ content: String, lyrics: Lyrics) -> String {
        guard let converter = ChineseConverter.shared,
              lyrics.metadata.language?.hasPrefix("zh") == true else {
            return content
        }
        return converter.convert(content)
    }

    private func interludeInterval(after line: LyricsLine, before nextLine: LyricsLine?) -> Range<TimeInterval>? {
        guard let nextLine,
              let lineEnd = visualEndPosition(for: line),
              nextLine.position - lineEnd >= Self.minimumInterludeDuration else {
            return nil
        }
        return lineEnd..<nextLine.position
    }

    private func visualEndPosition(for line: LyricsLine) -> TimeInterval? {
        guard let timetag = line.attachments.timetag else {
            return nil
        }
        if let duration = timetag.duration, duration.isFinite, duration > 0 {
            return line.position + duration
        }

        let textLength = (line.content as NSString).length
        guard textLength > 0,
              let finalBoundary = timetag.tags.max(by: { $0.time < $1.time }),
              finalBoundary.time.isFinite,
              finalBoundary.time > 0,
              finalBoundary.index >= textLength else {
            return nil
        }
        return line.position + finalBoundary.time
    }

    private func scheduleInterludeStart(after delay: TimeInterval) {
        guard delay > 0 else {
            handleLyricsDisplay()
            return
        }
        let queue = DispatchQueue.lyricsDisplay
        interludeStartSchedule = queue.schedule(
            after: queue.now.advanced(by: .seconds(delay)),
            interval: .seconds(42),
            tolerance: .milliseconds(20)
        ) { [weak self] in
            self?.handleLyricsDisplay()
        }
    }

    private func makeConstraints() {
        let position = clampedDesktopLyricsPosition()
        lyricsView.snp.remakeConstraints { make in
            make.centerX.equalToSuperview().safeMultipliedBy(position.xFactor * 2).priority(.low)
            make.centerY.equalToSuperview().safeMultipliedBy(position.yFactor * 2).priority(.low)

            make.leading.greaterThanOrEqualToSuperview().priority(.keepWindowSize)
            make.trailing.lessThanOrEqualToSuperview().priority(.keepWindowSize)
            make.top.greaterThanOrEqualToSuperview().priority(.keepWindowSize)
            make.bottom.lessThanOrEqualToSuperview().priority(.keepWindowSize)
        }
    }

    private func clampedDesktopLyricsPosition() -> (xFactor: CGFloat, yFactor: CGFloat) {
        guard let window = window else {
            return (defaults[.desktopLyricsXPositionFactor], defaults[.desktopLyricsYPositionFactor])
        }
        let center = NSPoint(
            x: defaults[.desktopLyricsXPositionFactor] * window.frame.width,
            y: (1 - defaults[.desktopLyricsYPositionFactor]) * window.frame.height
        )
        let clampedCenter = clampedCenterInWindow(center, window: window)
        return positionFactors(forCenter: clampedCenter, in: window)
    }

    private func progressPoints(forLineAt index: Int, position: TimeInterval, timeDelay: TimeInterval) -> [(TimeInterval, Int)]? {
        guard let lyrics = AppController.shared.currentLyrics,
              lyrics.lines.indices.contains(index) else {
            return nil
        }

        let line = lyrics.lines[index]
        if let timetag = line.attachments.timetag, !timetag.tags.isEmpty {
            return timetag.tags.map { ($0.time + line.position - timeDelay - position, $0.index) }
        }

        let textLength = (line.content as NSString).length
        guard textLength > 0 else {
            return nil
        }

        let fallbackEndPosition = lyrics.lines[(index + 1)...].first { $0.enabled }?.position
            ?? selectedPlayer.currentTrack?.duration
            ?? (line.position + 4)
        guard fallbackEndPosition - line.position > 0.25 else {
            return nil
        }

        return [
            (line.position - timeDelay - position, 0),
            (fallbackEndPosition - timeDelay - position, textLength),
        ]
    }

    private func setProgressAnimation(on label: KaraokeLabel, progress: [(TimeInterval, Int)]) {
        if let colors = lyricsView.progressGradientColors, colors.count >= 2 {
            label.setProgressAnimation(colors: colors, progress: progress)
        } else {
            label.setProgressAnimation(color: lyricsView.progressColor, progress: progress)
        }
    }

    // MARK: Dragging

    private var vecToCenter: CGVector?

    override func mouseDown(with event: NSEvent) {
        let location = lyricsView.convert(event.locationInWindow, from: nil)
        vecToCenter = CGVector(from: location, to: lyricsView.bounds.center)
    }

    override func mouseDragged(with event: NSEvent) {
        guard defaults[.desktopLyricsDraggable],
              let vecToCenter = vecToCenter,
              let window = window else {
            return
        }
        var center = event.locationInWindow + vecToCenter
        let centerInScreen = window.convertToScreen(CGRect(origin: center, size: .zero)).origin
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(centerInScreen) }),
           screen != window.screen {
            updateWindowFrame(toScreen: screen, animate: false)
            center = window.convertFromScreen(CGRect(origin: centerInScreen, size: .zero)).origin
        }
        center = clampedCenterInWindow(center, window: window)

        var (xFactor, yFactor) = positionFactors(forCenter: center, in: window)
        let bounds = window.frame
        if abs(center.x - bounds.width / 2) < 8 {
            xFactor = 0.5
        }
        if abs(center.y - bounds.height / 2) < 8 {
            yFactor = 0.5
        }
        defaults[.desktopLyricsXPositionFactor] = xFactor
        defaults[.desktopLyricsYPositionFactor] = yFactor
        let centerInScreenAfterClamping = window.convertToScreen(CGRect(origin: center, size: .zero)).origin
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(centerInScreenAfterClamping) }) ?? window.screen {
            LyricsWindowPlacementStore.saveDesktopLyrics(
                screen: screen,
                xFactor: xFactor,
                yFactor: yFactor
            )
        }
        makeConstraints()
        window.layoutIfNeeded()
    }

    private func clampedCenterInWindow(_ center: NSPoint, window: NSWindow) -> NSPoint {
        let centerInScreen = window.convertToScreen(CGRect(origin: center, size: .zero)).origin
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(centerInScreen) }) ?? window.screen else {
            return center
        }
        let visibleFrame = screen.visibleFrame.insetBy(
            dx: KaraokeLyricsWindowController.dragHandleSafeInset,
            dy: KaraokeLyricsWindowController.dragHandleSafeInset
        )
        let safeFrame = visibleFrame.isEmpty ? screen.visibleFrame : visibleFrame
        let clampedCenterInScreen = NSPoint(
            x: centerInScreen.x.clamped(to: safeFrame.minX ... safeFrame.maxX),
            y: centerInScreen.y.clamped(to: safeFrame.minY ... safeFrame.maxY)
        )
        return window.convertFromScreen(CGRect(origin: clampedCenterInScreen, size: .zero)).origin
    }

    private func positionFactors(forCenter center: NSPoint, in window: NSWindow) -> (xFactor: CGFloat, yFactor: CGFloat) {
        let bounds = window.frame
        let xFactor = (center.x / bounds.width).clamped(to: 0 ... 1)
        let yFactor = (1 - center.y / bounds.height).clamped(to: 0 ... 1)
        return (xFactor, yFactor)
    }
}

extension NSScreen {
    fileprivate var isFullScreen: Bool {
        guard let windowInfoList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return !windowInfoList.contains { info in
            guard info[kCGWindowOwnerName as String] as? String == "Window Server",
                  info[kCGWindowName as String] as? String == "Menubar",
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary as CFDictionary?,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else {
                return false
            }
            return frame.contains(bounds)
        }
    }
}

extension ConstraintMakerEditable {
    @discardableResult
    fileprivate func safeMultipliedBy(_ amount: ConstraintMultiplierTarget) -> ConstraintMakerEditable {
        var factor = amount.constraintMultiplierTargetValue
        if factor.isZero {
            factor = .leastNonzeroMagnitude
        }
        return multipliedBy(factor)
    }
}

extension ConstraintPriority {
    static let windowSizeStayPut = ConstraintPriority(NSLayoutConstraint.Priority.windowSizeStayPut.rawValue)
    static let keepWindowSize = ConstraintPriority.windowSizeStayPut.advanced(by: -1)
}

private extension DesktopLyricsTheme {
    var usesAlbumDerivedPalette: Bool {
        switch self {
        case .albumBlur, .amllDynamic:
            return true
        case .classic, .modern:
            return false
        }
    }
}
