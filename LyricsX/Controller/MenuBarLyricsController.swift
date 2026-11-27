import AppKit
import Combine
import GenericID
import LyricsXFoundation
import MusicPlayer
import OpenCC
import SwiftCF
import AccessibilityExt
import MarqueeLabel

private final class StatusItemMarqueeLabel: MarqueeLabel {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

class MenuBarLyricsController {
    static let shared = MenuBarLyricsController()

    var statusBarMenu: NSMenu? {
        didSet {
            setupStatusItemAction()
        }
    }

    private var statusItem: NSStatusItem?
    private var statusItemCanBeCreated = false
    private lazy var buttonImage: NSImage = {
        if #available(macOS 11.0, *) {
            return NSImage(
                systemSymbolName: "music.note",
                accessibilityDescription: "LyricsX"
            ) ?? #imageLiteral(resourceName: "status_bar_icon")
        }
        return #imageLiteral(resourceName: "status_bar_icon")
    }()

    private let marqueeLabel = StatusItemMarqueeLabel(frame: .init(x: 0, y: 0, width: 183, height: 22))

    private static let defaultLyric = "LyricsX"
    private var playbackIsPlaying = selectedPlayer.playbackState.isPlaying

    private var screenLyrics: (lyrics: String, duration: TimeInterval) = (MenuBarLyricsController.defaultLyric, 2) {
        didSet {
            DispatchQueue.main.async {
                self.updateStatusItems()
            }
        }
    }

    private var cancelBag = Set<AnyCancellable>()

    private init() {
        if !defaults[.hideMenuBarItems] {
            updateStatusItems()
        }
        AppController.shared.$currentLyrics
            .combineLatest(AppController.shared.$currentLineIndex)
            .receive(on: DispatchQueue.lyricsDisplay)
            .invoke(MenuBarLyricsController.handleLyricsDisplay, weaklyOn: self)
            .store(in: &cancelBag)
        selectedPlayer.playbackStateWillChange
            .receive(on: DispatchQueue.main)
            .invoke(MenuBarLyricsController.handlePlaybackState, weaklyOn: self)
            .store(in: &cancelBag)
        workspaceNC
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .signal()
            .invoke(MenuBarLyricsController.updateStatusItems, weaklyOn: self)
            .store(in: &cancelBag)
        defaults.publisher(for: [.menuBarLyricsEnabled, .combinedMenubarLyrics, .hideMenuBarItems])
            .prepend()
            .invoke(MenuBarLyricsController.updateStatusItems, weaklyOn: self)
            .store(in: &cancelBag)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.placeStatusItemOnPrimaryMenuBar()
            }
            .store(in: &cancelBag)
    }

    func install(statusItem: NSStatusItem, menu: NSMenu) {
        self.statusItem = statusItem
        statusBarMenu = menu
        statusItemCanBeCreated = true
        updateStatusItems()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.placeStatusItemOnPrimaryMenuBar()
        }
    }

    private func handlePlaybackState(_ state: PlaybackState) {
        playbackIsPlaying = state.isPlaying
        updateStatusItems()
    }

    private func handleLyricsDisplay(event: (lyrics: Lyrics?, index: Int?)) {
        guard !defaults[.disableLyricsWhenPaused] || selectedPlayer.playbackState.isPlaying,
              let lyrics = event.lyrics,
              let index = event.index else {
//            screenLyrics = (MenuBarLyricsController.defaultLyric, 2)
            return
        }
        let currentLine = lyrics.lines[index]
        var newScreenLyrics = currentLine.content
        if let converter = ChineseConverter.shared, lyrics.metadata.language?.hasPrefix("zh") == true {
            newScreenLyrics = converter.convert(newScreenLyrics)
        }
        if newScreenLyrics == screenLyrics.lyrics {
            return
        }
        let lineDisplayTime: TimeInterval
        if let duration = currentLine.attachments.timetag?.duration {
            lineDisplayTime = duration
        } else if let nextLine = lyrics.lines[safe: index + 1] {
            lineDisplayTime = nextLine.position - currentLine.position
        } else {
            lineDisplayTime = 2
        }
        screenLyrics = (newScreenLyrics, lineDisplayTime)
    }

    @objc private func updateStatusItems() {
        guard statusItemCanBeCreated else { return }
        guard !defaults[.hideMenuBarItems] else {
            marqueeLabel.removeFromSuperview()
            removeStatusItem()
            return
        }

        guard defaults[.menuBarLyricsEnabled] else {
            setupIconStatusItem()
            return
        }

        updateStatusLyrics()
    }

    private func updateStatusLyrics() {
        if playbackIsPlaying, needsMarquee(for: screenLyrics.lyrics) {
            setupMarqueeStatusItem()
            marqueeLabel.setStringValue(screenLyrics.lyrics, lineDisplayTime: screenLyrics.duration)
        } else {
            setupStaticLyricStatusItem()
        }
    }

    private func needsMarquee(for lyrics: String) -> Bool {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
        ]
        return (lyrics as NSString).size(withAttributes: attributes).width > marqueeLabel.bounds.width
    }

    private func setupMarqueeStatusItem() {
        marqueeLabel.removeFromSuperview()
        let item = makeStatusItemIfNeeded()
        item.button?.title = ""
        item.button?.image = nil
        item.length = marqueeLabel.bounds.width
        item.button?.frame = marqueeLabel.bounds
        item.button?.addSubview(marqueeLabel)
        setupStatusItemAction()
    }

    private func setupStaticLyricStatusItem() {
        marqueeLabel.removeFromSuperview()
        let item = makeStatusItemIfNeeded()
        item.button?.image = nil
        item.button?.title = screenLyrics.lyrics
        item.length = marqueeLabel.bounds.width
        setupStatusItemAction()
    }

    private func setupIconStatusItem() {
        marqueeLabel.removeFromSuperview()
        let item = makeStatusItemIfNeeded()
        item.button?.title = ""
        item.button?.image = buttonImage
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "LyricsX"
        item.length = NSStatusItem.squareLength
        setupStatusItemAction()
    }

    private func makeStatusItemIfNeeded() -> NSStatusItem {
        if let statusItem {
            return statusItem
        }
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem
        return statusItem
    }

    private func removeStatusItem() {
        guard let statusItem else {
            return
        }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func setupStatusItemAction() {
        guard let button = statusItem?.button else { return }
        statusItem?.menu = nil
        button.target = self
        button.action = #selector(showStatusBarMenu(_:))
        DispatchQueue.main.async { [weak self] in
            self?.placeStatusItemOnPrimaryMenuBar()
        }
    }

    private func placeStatusItemOnPrimaryMenuBar() {
        guard NSScreen.screens.count > 1,
              let primaryScreen = NSScreen.screens.first,
              let window = statusItem?.button?.window else {
            return
        }

        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        guard let currentScreen = NSScreen.screens.first(where: { $0.frame.contains(center) }),
              currentScreen != primaryScreen else {
            return
        }

        let trailingInset = max(0, currentScreen.frame.maxX - window.frame.maxX)
        let origin = NSPoint(
            x: primaryScreen.frame.maxX - trailingInset - window.frame.width,
            y: primaryScreen.frame.maxY - window.frame.height
        )
        window.setFrameOrigin(origin)
        window.orderFrontRegardless()
    }

    @objc private func showStatusBarMenu(_ sender: NSStatusBarButton) {
        statusBarMenu?.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: sender.bounds.maxY + 4),
            in: sender
        )
    }
}

// MARK: - Status Item Visibility

extension NSStatusItem {
    fileprivate var isVisibe: Bool {
        guard let buttonFrame = button?.frame,
              let frame = button?.window?.convertToScreen(buttonFrame) else {
            return false
        }

        let point = CGPoint(x: frame.midX, y: frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else {
            return false
        }
        let carbonPoint = CGPoint(x: point.x, y: screen.frame.height - point.y - 1)

        guard let element = try? AXUIElement.systemWide().element(at: carbonPoint),
              let pid = try? element.pid() else {
            return false
        }

        return getpid() == pid
    }
}

extension String {
    fileprivate func components(options: String.EnumerationOptions) -> [String] {
        var components: [String] = []
        let range = Range(uncheckedBounds: (startIndex, endIndex))
        enumerateSubstrings(in: range, options: options) { _, _, range, _ in
            components.append(String(self[range]))
        }
        return components
    }
}

extension Array {
    subscript(safe safeIndex: Int) -> Element? {
        if safeIndex >= 0, safeIndex < count {
            return self[safeIndex]
        } else {
            return nil
        }
    }
}
