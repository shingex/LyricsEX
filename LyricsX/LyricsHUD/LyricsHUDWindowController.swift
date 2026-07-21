import AppKit
import UIFoundation

final class LyricsHUDWindowController: NSWindowController, NSWindowDelegate, StoryboardWindowController {}

final class AMLLOriginalLyricsWindowController: NSWindowController, NSWindowDelegate {
    let lyricsView = AMLLOriginalLyricsWebView(frame: .zero)
    var onClose: (() -> Void)?
    private var isClosingProgrammatically = false
    private static let fallbackFrame = NSRect(x: 240, y: 240, width: 640, height: 560)

    init(frame: NSRect? = nil) {
        let requestedFrame = frame ?? Self.fallbackFrame
        let initialFrame = LyricsWindowPlacementStore.restoredWindowFrame(
            key: .amllOriginalLyrics,
            minimumSize: NSSize(width: 520, height: 360)
        ) ?? Self.normalizedFrame(requestedFrame, on: Self.screen(for: requestedFrame))
        let window = NSPanel(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "AMLL Original Source"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false

        lyricsView.autoresizingMask = [.width, .height]
        lyricsView.frame = NSRect(origin: .zero, size: window.contentView?.bounds.size ?? window.frame.size)
        window.contentView = lyricsView

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(relativeTo sourceWindow: NSWindow?) {
        syncWindowState(from: sourceWindow)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func syncWindowState(from sourceWindow: NSWindow?) {
        guard let window else {
            return
        }
        let sourceFrame = sourceWindow?.frame ?? Self.fallbackFrame
        let candidateFrame = sourceFrame.width >= 320 && sourceFrame.height >= 220 ? sourceFrame : Self.fallbackFrame
        let restoredFrame = LyricsWindowPlacementStore.restoredWindowFrame(
            key: .amllOriginalLyrics,
            minimumSize: NSSize(width: 520, height: 360)
        )
        window.setFrame(
            restoredFrame ?? Self.normalizedFrame(candidateFrame, on: Self.screen(for: candidateFrame)),
            display: true
        )
        if let sourceWindow {
            window.level = max(sourceWindow.level, .floating)
        } else {
            window.level = .floating
        }
    }

    private static func screen(for frame: NSRect) -> NSScreen? {
        let candidates = NSScreen.screens.map { screen in
            let intersection = screen.visibleFrame.intersection(frame)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            return (screen: screen, visibleArea: area)
        }
        guard let best = candidates.max(by: { $0.visibleArea < $1.visibleArea }),
              best.visibleArea > 0 else {
            return NSScreen.main
        }
        return best.screen
    }

    private static func normalizedFrame(_ frame: NSRect, on screen: NSScreen?) -> NSRect {
        guard let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame else {
            return frame
        }
        var result = frame
        result.size.width = min(max(result.width, 520), visibleFrame.width)
        result.size.height = min(max(result.height, 360), visibleFrame.height)

        let visibleIntersection = result.intersection(visibleFrame)
        let visibleArea = visibleIntersection.isNull ? 0 : visibleIntersection.width * visibleIntersection.height
        let requiredVisibleArea = min(result.width * result.height * 0.35, 160 * 120)
        if visibleArea < requiredVisibleArea {
            result.origin.x = visibleFrame.midX - result.width / 2
            result.origin.y = visibleFrame.midY - result.height / 2
        } else {
            result.origin.x = min(max(result.minX, visibleFrame.minX), visibleFrame.maxX - result.width)
            result.origin.y = min(max(result.minY, visibleFrame.minY), visibleFrame.maxY - result.height)
        }
        return result.integral
    }

    func closeProgrammatically() {
        saveWindowPlacement()
        isClosingProgrammatically = true
        close()
        isClosingProgrammatically = false
    }

    func windowDidMove(_ notification: Notification) {
        saveWindowPlacement()
    }

    func windowDidResize(_ notification: Notification) {
        saveWindowPlacement()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        saveWindowPlacement()
    }

    func windowWillClose(_ notification: Notification) {
        saveWindowPlacement()
        guard !isClosingProgrammatically else {
            return
        }
        onClose?()
    }

    private func saveWindowPlacement() {
        guard let window else {
            return
        }
        LyricsWindowPlacementStore.saveWindow(window, key: .amllOriginalLyrics)
    }
}
