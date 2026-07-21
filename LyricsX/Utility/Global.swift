import AppKit
import Combine
import GenericID
import LyricsXFoundation
import MusicPlayer

let fontNameFallbackCountMax = 1
// 7 days. after this period of time since the app built, the app is not considered as "in review".
let masReviewPeriodLimit: TimeInterval = 60 * 60 * 24 * 7

// NOTE: to build your own product, replace these identifiers with yours and
// do the same in LyricsXHelper.
#if DEBUG
let lyricsXSharedSuiteName = "dev.JH.LyricsX.shared"
let lyricsXHelperIdentifier = "dev.JH.LyricsXHelper"
let lyricsXErrorDomain = "dev.JH.LyricsX"
#else
let lyricsXSharedSuiteName = "com.JH.LyricsX.shared"
let lyricsXHelperIdentifier = "com.JH.LyricsXHelper"
let lyricsXErrorDomain = "com.JH.LyricsX"
#endif

let crowdinProjectURL = URL(string: "https://crowdin.com/project/lyricsx")!

let defaults = UserDefaults.standard
// Shared between the app and the (non-sandboxed) LyricsXHelper via a plain
// preferences suite at ~/Library/Preferences/<suite>.plist. Deliberately NOT an
// App Group container: a non-sandboxed process can't read App Group preferences
// through cfprefsd ("kCFPreferencesAnyUser ... only allowed for System
// Containers"); a plain suite works for both processes.
let sharedDefaults = UserDefaults(suiteName: lyricsXSharedSuiteName)!
let defaultNC = NotificationCenter.default
let workspaceNC = NSWorkspace.shared.notificationCenter
let selectedPlayer = MusicPlayers.Selected.shared
let desktopLyricsModernDefaultProgressColor = NSColor(calibratedRed: 0.08, green: 0.52, blue: 0.98, alpha: 1)
let desktopLyricsAlbumBlurDefaultProgressColor = NSColor(calibratedRed: 0.2, green: 0.68, blue: 1, alpha: 1)
let desktopLyricsAMLLDynamicDefaultProgressColor = NSColor(calibratedRed: 1, green: 0.33, blue: 0.48, alpha: 1)
let desktopLyricsAMLLDynamicDefaultFallbackColor = NSColor(calibratedRed: 0.14, green: 0.16, blue: 0.24, alpha: 1)

let isInSandbox = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
let isFromMacAppStore = (try? Bundle.main.appStoreReceiptURL?.checkResourceIsReachable()) == true

extension DispatchQueue {
    static let lyricsDisplay = DispatchQueue(label: "LyricsDisplay")
}

extension CAMediaTimingFunction {
    static let mystery = CAMediaTimingFunction(controlPoints: 0.2, 0.1, 0.2, 1)
    static let swiftOut = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1)
}

func log(_ message: @autoclosure () -> String, file: String = #file, line: UInt = #line) {
    let fileName = (file as NSString).lastPathComponent
    // Adding prefix to distinguish from ton of AppleEvent error log.
    NSLog("CustomLog:\(fileName):\(line): \(message())")
}

// MARK: - Identifier

extension NSUserInterfaceItemIdentifier {
//    static let WriteToiTunes = NSUserInterfaceItemIdentifier("MainMenu.WriteToiTunes")
//    static let SearchLyrics = NSUserInterfaceItemIdentifier("MainMenu.SearchLyrics")
//    static let LyricsMenu = NSUserInterfaceItemIdentifier("MainMenu.Lyrics")

    static let searchResultColumnTitle = NSUserInterfaceItemIdentifier("SearchResult.TableColumn.Title")
    static let searchResultColumnArtist = NSUserInterfaceItemIdentifier("SearchResult.TableColumn.Artist")
    static let searchResultColumnAlbum = NSUserInterfaceItemIdentifier("SearchResult.TableColumn.Album")
    static let searchResultColumnSource = NSUserInterfaceItemIdentifier("SearchResult.TableColumn.Source")
}

extension NSStoryboard.SceneIdentifier {
    static let desktopLyricsWindow = NSStoryboard.SceneIdentifier("DesktopLyricsWindow")
    static let lyricsHUDAccessory = NSStoryboard.SceneIdentifier("LyricsHUDAccessory")
}

// MARK: - User Defaults

extension UserDefaults.DefaultsKeys {
    static let notifiedUpdateVersion = Key<String?>("NotifiedUpdateVersion")
    static let noSearchingTrackIds = Key<[String]>("NoSearchingTrackIds")
    static let noSearchingAlbumNames = Key<[String]>("NoSearchingAlbumNames")

    // Menu
    static let desktopLyricsEnabled = Key<Bool>("DesktopLyricsEnabled")
    static let menuBarLyricsEnabled = Key<Bool>("MenuBarLyricsEnabled")
    static let touchBarLyricsEnabled = Key<Bool>("TouchBarLyricsEnabled")

    // General
    static let preferredPlayerIndex = Key<Int>("PreferredPlayerIndex")
    static let launchAndQuitWithPlayer = Key<Bool>("LaunchAndQuitWithPlayer")

    static let lyricsSavingPathPopUpIndex = Key<Int>("LyricsSavingPathPopUpIndex")
    static let lyricsCustomSavingPathBookmark = Key<Data?>("LyricsCustomSavingPathBookmark")
    static let loadLyricsBesideTrack = Key<Bool>("LoadLyricsBesideTrack")

    static let selectedLanguage = Key<String?>("SelectedLanguage")

    static let strictSearchEnabled = Key<Bool>("StrictSearchEnabled")
    static let preferBilingualLyrics = Key<Bool>("PreferBilingualLyrics")
    static let chineseConversionIndex = Key<Int>("ChineseConversionIndex")

    static let combinedMenubarLyrics = Key<Bool>("CombinedMenubarLyrics")

    static let hideLyricsWhenMousePassingBy = Key<Bool>("HideLyricsWhenMousePassingBy")
    static let disableLyricsWhenPaused = Key<Bool>("DisableLyricsWhenPaused")
    static let disableLyricsWhenSreenShot = Key<Bool>("DisableLyricsWhenSreenShot")

    static let hideMenuBarItems = Key<Bool>("HideMenuBarItems")

    // Display
    static let desktopLyricsOneLineMode = Key<Bool>("DesktopLyricsOneLineMode")
    static let desktopLyricsVerticalMode = Key<Bool>("DesktopLyricsVerticalMode")
    static let desktopLyricsDraggable = Key<Bool>("DesktopLyricsDraggable")

    static let desktopLyricsXPositionFactor = Key<CGFloat>("DesktopLyricsXPositionFactor")
    static let desktopLyricsYPositionFactor = Key<CGFloat>("DesktopLyricsYPositionFactor")

    static let desktopLyricsEnableFurigana = Key<Bool>("DesktopLyricsEnableFurigana")
    static let desktopLyricsEnableRomajin = Key<Bool>("DesktopLyricsEnableRomajin")

    static let desktopLyricsFontName = Key<String>("DesktopLyricsFontName")
    static let desktopLyricsFontSize = Key<Int>("DesktopLyricsFontSize")
    static let desktopLyricsFontNameFallback = Key<[String]>("DesktopLyricsFontNameFallback")

    static let desktopLyricsColor = Key<NSColor>("DesktopLyricsColor", transformer: .keyedArchive)
    static let desktopLyricsProgressColor = Key<NSColor>("DesktopLyricsProgressColor", transformer: .keyedArchive)
    static let desktopLyricsShadowColor = Key<NSColor>("DesktopLyricsShadowColor", transformer: .keyedArchive)
    static let desktopLyricsBackgroundColor = Key<NSColor>("DesktopLyricsBackgroundColor", transformer: .keyedArchive)
    static let desktopLyricsInactiveLineBlurRadius = Key<Double>("DesktopLyricsInactiveLineBlurRadius")

    static let desktopLyricsTheme = Key<Int>("DesktopLyricsTheme")
    static let desktopLyricsModernFontName = Key<String>("DesktopLyricsModernFontName")
    static let desktopLyricsModernFontSize = Key<Int>("DesktopLyricsModernFontSize")
    static let desktopLyricsModernTextColor = Key<NSColor>("DesktopLyricsModernTextColor", transformer: .keyedArchive)
    static let desktopLyricsModernProgressColor = Key<NSColor>("DesktopLyricsModernProgressColor", transformer: .keyedArchive)
    static let desktopLyricsModernBackgroundColor = Key<NSColor>("DesktopLyricsModernBackgroundColor", transformer: .keyedArchive)
    static let desktopLyricsModernUseAlbumColor = Key<Bool>("DesktopLyricsModernUseAlbumColor")
    static let desktopLyricsModernBackgroundOpacity = Key<Double>("DesktopLyricsModernBackgroundOpacity")
    static let desktopLyricsModernBlurEnabled = Key<Bool>("DesktopLyricsModernBlurEnabled")
    static let desktopLyricsModernCornerRadius = Key<Double>("DesktopLyricsModernCornerRadius")
    static let desktopLyricsModernInactiveLineBlurRadius = Key<Double>("DesktopLyricsModernInactiveLineBlurRadius")
    static let desktopLyricsModernProgressColorMigratedV1 = Key<Bool>("DesktopLyricsModernProgressColorMigratedV1")

    static let desktopLyricsAlbumBlurFontName = Key<String>("DesktopLyricsAlbumBlurFontName")
    static let desktopLyricsAlbumBlurFontSize = Key<Int>("DesktopLyricsAlbumBlurFontSize")
    static let desktopLyricsAlbumBlurTextColor = Key<NSColor>("DesktopLyricsAlbumBlurTextColor", transformer: .keyedArchive)
    static let desktopLyricsAlbumBlurProgressColor = Key<NSColor>("DesktopLyricsAlbumBlurProgressColor", transformer: .keyedArchive)
    static let desktopLyricsAlbumBlurTintColor = Key<NSColor>("DesktopLyricsAlbumBlurTintColor", transformer: .keyedArchive)
    static let desktopLyricsAlbumBlurFallbackColor = Key<NSColor>("DesktopLyricsAlbumBlurFallbackColor", transformer: .keyedArchive)
    static let desktopLyricsAlbumBlurBackgroundOpacity = Key<Double>("DesktopLyricsAlbumBlurBackgroundOpacity")
    static let desktopLyricsAlbumBlurDimAmount = Key<Double>("DesktopLyricsAlbumBlurDimAmount")
    static let desktopLyricsAlbumBlurBlurAmount = Key<Double>("DesktopLyricsAlbumBlurBlurAmount")
    static let desktopLyricsAlbumBlurCornerRadius = Key<Double>("DesktopLyricsAlbumBlurCornerRadius")
    static let desktopLyricsAlbumBlurInactiveLineBlurRadius = Key<Double>("DesktopLyricsAlbumBlurInactiveLineBlurRadius")
    static let desktopLyricsAlbumBlurReverseProgressGradient = Key<Bool>("DesktopLyricsAlbumBlurReverseProgressGradient")
    static let desktopLyricsAlbumBlurThemeSplitMigratedV1 = Key<Bool>("DesktopLyricsAlbumBlurThemeSplitMigratedV1")

    static let desktopLyricsAMLLDynamicFontName = Key<String>("DesktopLyricsAMLLDynamicFontName")
    static let desktopLyricsAMLLDynamicFontSize = Key<Int>("DesktopLyricsAMLLDynamicFontSize")
    static let desktopLyricsAMLLDynamicTextColor = Key<NSColor>("DesktopLyricsAMLLDynamicTextColor", transformer: .keyedArchive)
    static let desktopLyricsAMLLDynamicProgressColor = Key<NSColor>("DesktopLyricsAMLLDynamicProgressColor", transformer: .keyedArchive)
    static let desktopLyricsAMLLDynamicTintColor = Key<NSColor>("DesktopLyricsAMLLDynamicTintColor", transformer: .keyedArchive)
    static let desktopLyricsAMLLDynamicFallbackColor = Key<NSColor>("DesktopLyricsAMLLDynamicFallbackColor", transformer: .keyedArchive)
    static let desktopLyricsAMLLDynamicBackgroundOpacity = Key<Double>("DesktopLyricsAMLLDynamicBackgroundOpacity")
    static let desktopLyricsAMLLDynamicDimAmount = Key<Double>("DesktopLyricsAMLLDynamicDimAmount")
    static let desktopLyricsAMLLDynamicFlowSpeed = Key<Double>("DesktopLyricsAMLLDynamicFlowSpeed")
    static let desktopLyricsAMLLDynamicIntensity = Key<Double>("DesktopLyricsAMLLDynamicIntensity")
    static let desktopLyricsAMLLDynamicCornerRadius = Key<Double>("DesktopLyricsAMLLDynamicCornerRadius")
    static let desktopLyricsAMLLDynamicInactiveLineBlurRadius = Key<Double>("DesktopLyricsAMLLDynamicInactiveLineBlurRadius")
    static let desktopLyricsAMLLDynamicReverseProgressGradient = Key<Bool>("DesktopLyricsAMLLDynamicReverseProgressGradient")

    static let lyricsWindowFontName = Key<String>("LyricsWindowFontName")
    static let lyricsWindowFontSize = Key<Int>("LyricsWindowFontSize")
    static let lyricsWindowFontNameFallback = Key<[String]>("LyricsWindowFontNameFallback")

    static let lyricsWindowTextColor = Key<NSColor>("LyricsWindowTextColor", transformer: .keyedArchive)
    static let lyricsWindowHighlightColor = Key<NSColor>("LyricsWindowHighlightColor", transformer: .keyedArchive)
    static let lyricsWindowTheme = Key<Int>("LyricsWindowTheme")
    static let lyricsWindowAMLLOriginalFontName = Key<String>("LyricsWindowAMLLOriginalFontName")
    static let lyricsWindowAMLLOriginalFontSize = Key<Int>("LyricsWindowAMLLOriginalFontSize")
    static let lyricsWindowAMLLDynamicAlignment = Key<Int>("LyricsWindowAMLLDynamicAlignment")
    static let lyricsWindowAMLLDynamicLineSpacing = Key<Double>("LyricsWindowAMLLDynamicLineSpacing")
    static let lyricsWindowAMLLDynamicMotionAmount = Key<Double>("LyricsWindowAMLLDynamicMotionAmount")

    // Shortcut
    static let shortcutToggleMenuBarLyrics = Key<String>("ShortcutToggleMenuBarLyrics")
    static let shortcutToggleKaraokeLyrics = Key<String>("ShortcutToggleKaraokeLyrics")
    static let shortcutShowLyricsWindow = Key<String>("ShortcutShowLyricsWindow")
    static let shortcutOffsetIncrease = Key<String>("ShortcutOffsetIncrease")
    static let shortcutOffsetDecrease = Key<String>("ShortcutOffsetDecrease")
    static let shortcutWriteToiTunes = Key<String>("ShortcutWriteToiTunes")
    static let shortcutSearchLyrics = Key<String>("ShortcutSearchLyrics")
    static let shortcutWrongLyrics = Key<String>("ShortcutWrongLyrics")
    static let shortcutTogglePreferences = Key<String>("ShortcutTogglePreferences")

    // Filter
    static let lyricsFilterEnabled = Key<Bool>("LyricsFilterEnabled")
    static let lyricsSmartFilterEnabled = Key<Bool>("LyricsSmartFilterEnabled")
    static let lyricsFilterKeys = Key<[String]>("LyricsFilterKeys")

    // Lab
    static let useSystemWideNowPlaying = Key<Bool>("UseSystemWideNowPlaying")
    static let systemWideNowPlayingAppList = Key<[String]>("SystemWideNowPlayingAppList")

    static let writeiTunesWithTranslation = Key<Bool>("WriteiTunesWithTranslation")
    static let writeToiTunesAutomatically = Key<Bool>("WriteToiTunesAutomatically")
    static let writeiTunesConvertToPlainLRC = Key<Bool>("WriteiTunesConvertToPlainLRC")

    static let globalLyricsOffset = Key<Int>("GlobalLyricsOffset")

    static let musixmatchToken = Key<String?>("MusixmatchToken")

    //
    static let isInMASReview = Key<Bool?>("isInMASReview")

    static let launchHelperTime = Key<Date?>("launchHelperTime")

    static let appleLanguages = Key<[String]>("AppleLanguages")

    static let isShowLyricsHUD = Key<Bool>("isShowLyricsHUD")

    // Source Priority
    static let lyricsSourcePriorityEnabled = Key<Bool>("LyricsSourcePriorityEnabled")
    static let lyricsSourcePriorityOrder = Key<[String]>("LyricsSourcePriorityOrder")
    static let lyricsPriorityWindow = Key<Double>("LyricsPriorityWindow")
}

enum DesktopLyricsTheme: Int {
    case classic = 0
    case modern = 1
    case albumBlur = 2
    case amllDynamic = 3
}

enum LyricsWindowTheme: Int {
    case classic = 0
    case amllOriginalSource = 3
}

enum LyricsWindowAMLLAlignment: Int {
    case left = 0
    case center = 1

    var textAlignment: NSTextAlignment {
        switch self {
        case .left:
            return .left
        case .center:
            return .center
        }
    }
}

extension Notification.Name {
    static let desktopLyricsAppearanceDidChange = Notification.Name("DesktopLyricsAppearanceDidChange")
    static let lyricsWindowAppearanceDidChange = Notification.Name("LyricsWindowAppearanceDidChange")
}

// MARK: - Lyrics Priority

func lyricsHasHigherPriority(_ new: Lyrics, over existing: Lyrics) -> Bool {
    let newTier = lyricsMatchTier(new)
    let existingTier = lyricsMatchTier(existing)
    if newTier != existingTier {
        return newTier > existingTier
    }

    let newScore = lyricsRankingScore(new)
    let existingScore = lyricsRankingScore(existing)
    if newScore != existingScore {
        return newScore > existingScore
    }

    return lyricsSourcePriority(new) < lyricsSourcePriority(existing)
}

private let strictTitleMatchThreshold = 0.75
private let strictArtistMatchThreshold = 0.75
private let strictAlbumMismatchThreshold = 0.35
private let weakTitleMatchThreshold = 0.45
private let titleScoreWeight = 0.45
private let artistScoreWeight = 0.25
private let albumScoreWeight = 0.15
private let durationScoreWeight = 0.15
private let translationBonus = 0.05
private let inlineTimeTagBonus = 0.05

func lyricsMatchesSearchIdentity(_ lyrics: Lyrics) -> Bool {
    let request = lyricsRequestFields(lyrics)
    guard !request.title.isEmpty,
          !request.artist.isEmpty,
          let candidateTitle = lyrics.idTags[.title],
          let candidateArtist = lyrics.idTags[.artist] else {
        return false
    }

    let titleSimilarity = matchingStringSimilarity(candidateTitle, request.title)
    let artistSimilarity = matchingStringSimilarity(candidateArtist, request.artist)
    guard titleSimilarity >= strictTitleMatchThreshold,
          artistSimilarity >= strictArtistMatchThreshold else {
        return false
    }

    guard !request.album.isEmpty,
          let candidateAlbum = lyrics.idTags[.album],
          !candidateAlbum.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return true
    }

    return matchingStringSimilarity(candidateAlbum, request.album) > strictAlbumMismatchThreshold
}

private func lyricsMatchTier(_ lyrics: Lyrics) -> Int {
    let request = lyricsRequestFields(lyrics)
    guard !request.title.isEmpty,
          !request.artist.isEmpty,
          let candidateTitle = lyrics.idTags[.title],
          let candidateArtist = lyrics.idTags[.artist] else {
        return 0
    }

    let artistSimilarity = matchingStringSimilarity(candidateArtist, request.artist)
    guard artistSimilarity >= strictArtistMatchThreshold else {
        return 0
    }

    let titleSimilarity = matchingStringSimilarity(candidateTitle, request.title)
    let albumSimilarity = optionalMatchingStringSimilarity(lyrics.idTags[.album] ?? "", request.album)
    if titleSimilarity == 1,
       artistSimilarity == 1,
       albumSimilarity == 1 {
        return lyricsHasInlineTimeTags(lyrics) ? 5 : 4
    }
    if titleSimilarity >= strictTitleMatchThreshold {
        return 3
    }
    if titleSimilarity >= weakTitleMatchThreshold {
        return 2
    }
    return 1
}

private func lyricsRankingScore(_ lyrics: Lyrics) -> Double {
    let request = lyricsRequestFields(lyrics)
    let titleSimilarity = matchingStringSimilarity(lyrics.idTags[.title] ?? "", request.title)
    let artistSimilarity = matchingStringSimilarity(lyrics.idTags[.artist] ?? "", request.artist)
    let albumSimilarity = optionalMatchingStringSimilarity(lyrics.idTags[.album] ?? "", request.album)
    let durationSimilarity = lyricsDurationSimilarity(lyrics)

    var score = titleSimilarity * titleScoreWeight
        + artistSimilarity * artistScoreWeight
        + albumSimilarity * albumScoreWeight
        + durationSimilarity * durationScoreWeight

    if lyrics.metadata.hasTranslation {
        score += translationBonus
    }
    if lyricsHasInlineTimeTags(lyrics) {
        score += inlineTimeTagBonus
    }

    return score
}

private func lyricsRequestFields(_ lyrics: Lyrics) -> (title: String, artist: String, album: String) {
    let title: String
    let artist: String
    switch lyrics.metadata.request?.searchTerm {
    case .info(let requestTitle, let requestArtist)?:
        title = requestTitle
        artist = requestArtist
    case .keyword(let keyword)?:
        title = keyword
        artist = keyword
    case nil:
        title = ""
        artist = ""
    }

    return (
        normalizedMatchingString(title),
        normalizedMatchingString(artist),
        normalizedMatchingString(lyrics.metadata.request?.userInfo["album"] ?? "")
    )
}

private func lyricsSourcePriority(_ lyrics: Lyrics) -> Int {
    guard defaults[.lyricsSourcePriorityEnabled] else {
        return Int.max
    }
    let sourceOrder = defaults[.lyricsSourcePriorityOrder] ?? []
    let normalizedOrder = sourceOrder.map { $0.lowercased() }
    let source = (lyrics.metadata.service ?? "").lowercased()
    return normalizedOrder.firstIndex(of: source) ?? Int.max
}

private func matchingStringSimilarity(_ lhs: String, _ rhs: String) -> Double {
    let lhs = normalizedMatchingString(lhs)
    let rhs = normalizedMatchingString(rhs)
    guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
    if lhs == rhs { return 1 }

    let maxLength = max(lhs.count, rhs.count)
    guard maxLength > 0 else { return 1 }
    let distance = lhs.editDistance(to: rhs)
    return max(0, Double(maxLength - distance) / Double(maxLength))
}

private func optionalMatchingStringSimilarity(_ lhs: String, _ rhs: String) -> Double {
    let lhs = normalizedMatchingString(lhs)
    let rhs = normalizedMatchingString(rhs)
    guard !lhs.isEmpty, !rhs.isEmpty else { return 0.5 }
    return matchingStringSimilarity(lhs, rhs)
}

private func lyricsDurationSimilarity(_ lyrics: Lyrics) -> Double {
    guard let duration = lyrics.length,
          let requestDuration = lyrics.metadata.request?.duration,
          requestDuration > 0 else {
        return 0.5
    }
    let delta = abs(requestDuration - duration)
    guard delta < 10 else {
        return 0.3
    }
    return 1 - pow(delta / 10, 2) * 0.7
}

private func lyricsHasInlineTimeTags(_ lyrics: Lyrics) -> Bool {
    lyrics.metadata.attachmentTags.contains(.timetag)
        || lyrics.lines.contains { $0.attachments.timetag != nil }
}

private func normalizedMatchingString(_ string: String) -> String {
    let folded = string
        .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        .lowercased()
    let scalars = folded.unicodeScalars.map { scalar -> Character in
        CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
    }
    return String(scalars)
        .split(separator: " ")
        .joined(separator: " ")
}

private extension String {
    func editDistance(to other: String) -> Int {
        var distances = Array(0 ... other.count)
        for (sourceOffset, sourceCharacter) in enumerated() {
            var previousDiagonal = sourceOffset
            distances[0] = sourceOffset + 1
            for (targetOffset, targetCharacter) in other.enumerated() {
                let oldDistance = distances[targetOffset + 1]
                if sourceCharacter == targetCharacter {
                    distances[targetOffset + 1] = previousDiagonal
                } else {
                    distances[targetOffset + 1] = Swift.min(
                        previousDiagonal,
                        distances[targetOffset],
                        distances[targetOffset + 1]
                    ) + 1
                }
                previousDiagonal = oldDistance
            }
        }
        return distances.last ?? 0
    }
}

extension CGFloat: @retroactive DefaultConstructible {}
