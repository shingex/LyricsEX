import AppKit
import LyricsXFoundation
import MusicPlayer
import Regex

extension MusicPlayerName {
    init?(index: Int) {
        switch index {
        case 0: self = .appleMusic
        case 1: self = .spotify
        case 2: self = .vox
        case 3: self = .audirvana
        case 4: self = .swinsian
        default: return nil
        }
    }

    var icon: NSImage {
        switch self {
        case .appleMusic: return #imageLiteral(resourceName: "iTunes_icon")
        case .spotify: return #imageLiteral(resourceName: "spotify_icon")
        case .vox: return #imageLiteral(resourceName: "vox_icon")
        case .audirvana: return #imageLiteral(resourceName: "audirvana_icon")
        case .swinsian: return #imageLiteral(resourceName: "swinsian_icon")
        }
    }
}

extension MusicTrack {
    var lyrics: String? {
        guard let originalTrack = originalTrack,
              originalTrack.responds(to: Selector(("lyrics"))) else {
            return nil
        }
        return originalTrack.value(forKey: "lyrics") as? String
    }

    func setLyrics(_ lyrics: String) {
        guard let originalTrack = originalTrack,
              originalTrack.responds(to: Selector(("setLyrics:"))) else {
            return
        }
        originalTrack.setValue(lyrics, forKey: "lyrics")
    }
    
    var localFileURL: URL? {
        if let url = fileURL {
            return url
        }
        guard let originalTrack = originalTrack,
              originalTrack.responds(to: Selector(("location"))) else {
            return nil
        }
        return originalTrack.value(forKey: "location") as? URL
    }
}

extension NSFont {
    convenience init?(name fontName: String, size fontSize: CGFloat, fallback fallbackNames: [String]) {
        let cascadeList = fallbackNames.compactMap {
            NSFontDescriptor(name: $0, size: fontSize)
                .matchingFontDescriptor(withMandatoryKeys: [.name, .size])
        }
        let descriptor = NSFontDescriptor(fontAttributes: [.name: fontName, .cascadeList: cascadeList])
        self.init(descriptor: descriptor, size: fontSize)
    }
}

extension UserDefaults {
    var desktopLyricsFont: NSFont {
        return NSFont(
            name: self[.desktopLyricsFontName],
            size: CGFloat(self[.desktopLyricsFontSize]),
            fallback: self[.desktopLyricsFontNameFallback]
        )
            ?? NSFont.systemFont(ofSize: CGFloat(self[.desktopLyricsFontSize]))
    }

    var lyricsWindowFont: NSFont {
        return NSFont(
            name: defaults[.lyricsWindowFontName],
            size: CGFloat(defaults[.lyricsWindowFontSize])
        )
            ?? NSFont.labelFont(ofSize: CGFloat(defaults[.desktopLyricsFontSize]))
    }

    var lyricsWindowAMLLOriginalFont: NSFont {
        return NSFont(
            name: defaults[.lyricsWindowAMLLOriginalFontName],
            size: CGFloat(defaults[.lyricsWindowAMLLOriginalFontSize])
        )
            ?? NSFont.boldSystemFont(ofSize: CGFloat(defaults[.lyricsWindowAMLLOriginalFontSize]))
    }

    var desktopLyricsModernFont: NSFont {
        return NSFont(
            name: self[.desktopLyricsModernFontName],
            size: CGFloat(self[.desktopLyricsModernFontSize])
        )
            ?? NSFont.boldSystemFont(ofSize: CGFloat(self[.desktopLyricsModernFontSize]))
    }

    var desktopLyricsAlbumBlurFont: NSFont {
        return NSFont(
            name: self[.desktopLyricsAlbumBlurFontName],
            size: CGFloat(self[.desktopLyricsAlbumBlurFontSize])
        )
            ?? NSFont.boldSystemFont(ofSize: CGFloat(self[.desktopLyricsAlbumBlurFontSize]))
    }

    var desktopLyricsAMLLDynamicFont: NSFont {
        return NSFont(
            name: self[.desktopLyricsAMLLDynamicFontName],
            size: CGFloat(self[.desktopLyricsAMLLDynamicFontSize])
        )
            ?? NSFont.boldSystemFont(ofSize: CGFloat(self[.desktopLyricsAMLLDynamicFontSize]))
    }

    func color(for key: DefaultsKey<NSColor>, fallback: NSColor) -> NSColor {
        let color: NSColor? = self[key]
        return color ?? fallback
    }

    func setColor(_ color: NSColor, for key: DefaultsKey<NSColor>) {
        self[key] = Optional(color)
    }
}

enum LyricsWindowPlacementKey: String {
    case desktopLyrics = "LyricsX.WindowPlacement.DesktopLyrics.v1"
    case lyricsHUD = "LyricsX.WindowPlacement.LyricsHUD.v1"
    case amllOriginalLyrics = "LyricsX.WindowPlacement.AMLLOriginalLyrics.v1"
}

struct RestoredDesktopLyricsPlacement {
    let screen: NSScreen
    let xFactor: CGFloat
    let yFactor: CGFloat
}

private struct StoredLyricsScreen: Codable {
    let identifier: String?
    let name: String
    let frameX: Double
    let frameY: Double
    let frameWidth: Double
    let frameHeight: Double

    init(screen: NSScreen) {
        identifier = screen.lyricsPlacementIdentifier
        name = screen.localizedName
        frameX = Double(screen.frame.minX)
        frameY = Double(screen.frame.minY)
        frameWidth = Double(screen.frame.width)
        frameHeight = Double(screen.frame.height)
    }

    func resolve() -> NSScreen? {
        if let identifier,
           let screen = NSScreen.screens.first(where: { $0.lyricsPlacementIdentifier == identifier }) {
            return screen
        }

        let namedScreens = NSScreen.screens.filter { $0.localizedName == name }
        if let screen = namedScreens.min(by: { screenDistance($0) < screenDistance($1) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func screenDistance(_ screen: NSScreen) -> Double {
        return abs(Double(screen.frame.minX) - frameX)
            + abs(Double(screen.frame.minY) - frameY)
            + abs(Double(screen.frame.width) - frameWidth)
            + abs(Double(screen.frame.height) - frameHeight)
    }
}

private struct StoredDesktopLyricsPlacement: Codable {
    let screen: StoredLyricsScreen
    let xFactor: Double
    let yFactor: Double
}

private struct StoredLyricsWindowFrame: Codable {
    let screen: StoredLyricsScreen
    let xFactor: Double
    let yFactor: Double
    let width: Double
    let height: Double
}

enum LyricsWindowPlacementStore {
    static func saveDesktopLyrics(screen: NSScreen, xFactor: CGFloat, yFactor: CGFloat) {
        let placement = StoredDesktopLyricsPlacement(
            screen: StoredLyricsScreen(screen: screen),
            xFactor: Double(clamp(xFactor, to: 0...1)),
            yFactor: Double(clamp(yFactor, to: 0...1))
        )
        save(placement, key: .desktopLyrics)
    }

    static func restoreDesktopLyrics() -> RestoredDesktopLyricsPlacement? {
        guard let placement: StoredDesktopLyricsPlacement = load(key: .desktopLyrics),
              let screen = placement.screen.resolve() else {
            return nil
        }
        return RestoredDesktopLyricsPlacement(
            screen: screen,
            xFactor: clamp(CGFloat(placement.xFactor), to: 0...1),
            yFactor: clamp(CGFloat(placement.yFactor), to: 0...1)
        )
    }

    static func saveWindow(_ window: NSWindow, key: LyricsWindowPlacementKey) {
        let frame = window.frame
        guard frame.width > 0, frame.height > 0,
              let screen = screen(containingMostOf: frame) ?? window.screen else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let availableWidth = max(0, visibleFrame.width - frame.width)
        let availableHeight = max(0, visibleFrame.height - frame.height)
        let xFactor = availableWidth > 0 ? (frame.minX - visibleFrame.minX) / availableWidth : 0.5
        let yFactor = availableHeight > 0 ? (frame.minY - visibleFrame.minY) / availableHeight : 0.5
        let placement = StoredLyricsWindowFrame(
            screen: StoredLyricsScreen(screen: screen),
            xFactor: Double(clamp(xFactor, to: 0...1)),
            yFactor: Double(clamp(yFactor, to: 0...1)),
            width: Double(frame.width),
            height: Double(frame.height)
        )
        save(placement, key: key)
    }

    static func restoredWindowFrame(
        key: LyricsWindowPlacementKey,
        minimumSize: NSSize
    ) -> NSRect? {
        guard let placement: StoredLyricsWindowFrame = load(key: key),
              let screen = placement.screen.resolve() else {
            return nil
        }

        let visibleFrame = screen.visibleFrame
        let width = min(max(CGFloat(placement.width), minimumSize.width), visibleFrame.width)
        let height = min(max(CGFloat(placement.height), minimumSize.height), visibleFrame.height)
        let availableWidth = max(0, visibleFrame.width - width)
        let availableHeight = max(0, visibleFrame.height - height)
        let origin = NSPoint(
            x: visibleFrame.minX + availableWidth * clamp(CGFloat(placement.xFactor), to: 0...1),
            y: visibleFrame.minY + availableHeight * clamp(CGFloat(placement.yFactor), to: 0...1)
        )
        return NSRect(origin: origin, size: NSSize(width: width, height: height)).integral
    }

    private static func save<T: Encodable>(_ value: T, key: LyricsWindowPlacementKey) {
        guard let data = try? PropertyListEncoder().encode(value) else {
            return
        }
        defaults.set(data, forKey: key.rawValue)
    }

    private static func load<T: Decodable>(key: LyricsWindowPlacementKey) -> T? {
        guard let data = defaults.data(forKey: key.rawValue) else {
            return nil
        }
        return try? PropertyListDecoder().decode(T.self, from: data)
    }

    private static func screen(containingMostOf frame: NSRect) -> NSScreen? {
        return NSScreen.screens.max { lhs, rhs in
            intersectionArea(lhs.visibleFrame, frame) < intersectionArea(rhs.visibleFrame, frame)
        }
    }

    private static func intersectionArea(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private static func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

private extension NSScreen {
    var lyricsPlacementIdentifier: String? {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = deviceDescription[screenNumberKey] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

extension NSColor {
    func isVisuallyClose(to other: NSColor, tolerance: CGFloat = 0.02) -> Bool {
        guard let lhs = usingColorSpace(.deviceRGB),
              let rhs = other.usingColorSpace(.deviceRGB) else {
            return false
        }
        return abs(lhs.redComponent - rhs.redComponent) <= tolerance
            && abs(lhs.greenComponent - rhs.greenComponent) <= tolerance
            && abs(lhs.blueComponent - rhs.blueComponent) <= tolerance
            && abs(lhs.alphaComponent - rhs.alphaComponent) <= tolerance
    }
}

extension UserDefaults {
    func lyricsSavingPath() -> (URL, security: Bool) {
        if self[.lyricsSavingPathPopUpIndex] != 0, let path = lyricsCustomSavingPath {
            return (path, true)
        } else {
            let userPath = String(cString: getpwuid(getuid()).pointee.pw_dir)
            return (URL(fileURLWithPath: userPath).appendingPathComponent("Music/LyricsX"), false)
        }
    }

    var lyricsCustomSavingPath: URL? {
        get {
            guard let data = self[.lyricsCustomSavingPathBookmark] else {
                return nil
            }
            var bookmarkDataIsStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [.withSecurityScope],
                    bookmarkDataIsStale: &bookmarkDataIsStale
                )
                guard bookmarkDataIsStale == false else {
                    return nil
                }
                return url
            } catch {
                log(error.localizedDescription)
                return nil
            }
        }
        set {
            self[.lyricsCustomSavingPathBookmark] = try? newValue?.bookmarkData(options: [.withSecurityScope])
        }
    }
}

extension Lyrics {
    func associateWithTrack(_ track: MusicTrack) {
        metadata.title = track.title
        metadata.artist = track.artist
    }

    var fileName: String? {
        guard let title = metadata.title?.replacingOccurrences(of: "/", with: ":"),
              let artist = metadata.artist?.replacingOccurrences(of: "/", with: ":") else {
            return nil
        }
        return "\(title) - \(artist).lrcx"
    }

    func persist() {
        let (url, security) = defaults.lyricsSavingPath()
        if security {
            guard url.startAccessingSecurityScopedResource() else {
                return
            }
        }
        defer {
            if security {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let fileManager = FileManager.default

        do {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
                if !isDir.boolValue {
                    return
                }
            } else {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            }

            guard let lrcFileURL = fileName.map(url.appendingPathComponent) else {
                return
            }

            if fileManager.fileExists(atPath: lrcFileURL.path) {
                try fileManager.removeItem(at: lrcFileURL)
            }
            try description.write(to: lrcFileURL, atomically: true, encoding: .utf8)
            metadata.localURL = lrcFileURL
            metadata.needsPersist = false
        } catch {
            log(error.localizedDescription)
            return
        }
    }
}

extension NSPredicate {
    fileprivate static var lyricsPredicate: NSPredicate {
        _ = NSPredicate.observer
        return _lyricsPredicate
    }

    private static var _lyricsPredicate: NSPredicate!

    private static let observer = defaults.observe(.lyricsFilterKeys, options: [.new, .initial]) { _, change in
        let predicates = change.newValue.compactMap { (key: String) -> NSPredicate? in
            let isRegex = key.hasPrefix("/")
            let pattern = isRegex ? String(key.dropFirst()) : key
            let options: NSRegularExpression.Options = isRegex ? [] : [.ignoreMetacharacters]
            guard let regex = try? Regex(pattern, options: options) else { return nil }
            return NSPredicate { object, _ in
                guard let object = object as? LyricsLine else { return false }
                return !regex.isMatch(object.content)
            }
        }
        _lyricsPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }
}

extension Lyrics {
    func filtrate() {
        filtrate(isIncluded: NSPredicate.lyricsPredicate)
    }
}

extension Lyrics {
    var adjustedOffset: Int {
        return offset + defaults[.globalLyricsOffset]
    }

    var adjustedTimeDelay: TimeInterval {
        return TimeInterval(adjustedOffset) / 1000
    }
}

extension NSImage {
    func scaled(to size: NSSize) -> NSImage {
        return NSImage(size: size, flipped: false) { rect in
            let srcRect = NSRect(origin: .zero, size: self.size)
            self.draw(in: rect, from: srcRect, operation: .copy, fraction: 1)
            return true
        }
    }
}
