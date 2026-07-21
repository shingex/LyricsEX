import AppKit
import LyricsXFoundation
import WebKit

final class AMLLOriginalLyricsWebView: NSView, WKNavigationDelegate, WKScriptMessageHandler {
    private let webView: AMLLOriginalHostWebView
    private let interactionOverlayView = AMLLOriginalInteractionOverlayView(frame: .zero)
    private let statusLabel = NSTextField(labelWithString: "AMLL Original Source loading...")
    private var isReady = false
    private var hasFinishedInitialLoad = false
    private var pendingScripts: [String] = []
    private var lastAlbumDataURL: String?

    override init(frame frameRect: NSRect) {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        let diagnosticsScript = """
        window.addEventListener("error", function(event) {
          window.webkit.messageHandlers.amllLog.postMessage("document-start error: " + event.message);
        });
        window.addEventListener("unhandledrejection", function(event) {
          window.webkit.messageHandlers.amllLog.postMessage("document-start unhandledrejection: " + String(event.reason));
        });
        window.webkit.messageHandlers.amllLog.postMessage("document-start");
        """
        let visibilityScript = """
        (function() {
          var style = document.createElement("style");
          style.textContent = [
            "html,body,#root,.amll-root{background:#16181f!important;}",
            ".amll-player,.amll-lyric-player{mix-blend-mode:normal!important;color:#fff!important;}",
            ".amll-shade{background:radial-gradient(circle at 20% 18%,rgba(255,255,255,.16),transparent 34%),linear-gradient(180deg,rgba(0,0,0,.18),rgba(0,0,0,.62))!important;}",
            ".amll-empty{color:rgba(255,255,255,.78)!important;}"
          ].join("\\n");
          document.head.appendChild(style);
          window.webkit.messageHandlers.amllLog.postMessage("visibility style injected");
        })();
        """
        configuration.userContentController = contentController
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.javaScriptEnabled = true
        #if compiler(>=5.3)
        if #available(macOS 11.0, *) {
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        } else {
            configuration.preferences.javaScriptEnabled = true
        }
        #else
        configuration.preferences.javaScriptEnabled = true
        #endif
        contentController.addUserScript(WKUserScript(source: diagnosticsScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        contentController.addUserScript(WKUserScript(source: visibilityScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        self.webView = AMLLOriginalHostWebView(frame: frameRect, configuration: configuration)
        super.init(frame: frameRect)

        contentController.add(self, name: "amllReady")
        contentController.add(self, name: "amllLog")
        webView.lineProvider = { [weak self] point, completion in
            self?.copyLyricLine(at: point, completion: completion)
        }
        interactionOverlayView.lineProvider = { [weak self] point, completion in
            self?.copyLyricLine(at: point, completion: completion)
        }
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.12, alpha: 1).cgColor
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        interactionOverlayView.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.alignment = .center
        statusLabel.textColor = NSColor.white.withAlphaComponent(0.72)
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        addSubview(webView)
        addSubview(interactionOverlayView)
        addSubview(statusLabel)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            interactionOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            interactionOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            interactionOverlayView.topAnchor.constraint(equalTo: topAnchor),
            interactionOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        loadBundle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "amllReady")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "amllLog")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "amllReady":
            inspectScriptState(allowMarkReady: true)
        case "amllLog":
            log("AMLL Original Source WebView: \(message.body)")
        default:
            break
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasFinishedInitialLoad = true
        if !isReady {
            showStatus("AMLL Original Source waiting for script...")
        }
        log("AMLL Original Source WebView: did finish navigation")
        inspectScriptState(allowMarkReady: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, !self.isReady else {
                return
            }
            self.inspectScriptState(allowMarkReady: true)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !shouldIgnoreNavigationError(error), !hasFinishedInitialLoad else {
            log("AMLL Original Source WebView: ignored navigation failure: \(error.localizedDescription)")
            return
        }
        showStatus("AMLL Original Source failed: \(error.localizedDescription)")
        log("AMLL Original Source WebView: navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !shouldIgnoreNavigationError(error), !hasFinishedInitialLoad else {
            log("AMLL Original Source WebView: ignored provisional navigation failure: \(error.localizedDescription)")
            return
        }
        showStatus("AMLL Original Source failed: \(error.localizedDescription)")
        log("AMLL Original Source WebView: provisional navigation failed: \(error.localizedDescription)")
    }

    func setLyrics(_ lyrics: Lyrics?, trackDuration: TimeInterval?) {
        let payload = Self.makeLyricPayload(lyrics, trackDuration: trackDuration)
        guard let json = Self.jsonString(payload) else {
            return
        }
        evaluate("window.AMLLHost?.setLyrics(\(json));")
    }

    func setCurrentTime(_ time: TimeInterval) {
        let timeMS = max(0, Int((time * 1000).rounded()))
        evaluate("window.AMLLHost?.setCurrentTime(\(timeMS));")
    }

    func setPlaying(_ playing: Bool) {
        evaluate("window.AMLLHost?.setPlaying(\(playing ? "true" : "false"));")
    }

    func setVisualOptions(alignment: LyricsWindowAMLLAlignment, lineSpacing: CGFloat, motionAmount: CGFloat, font: NSFont) {
        let payload = AMLLVisualOptions(
            alignment: alignment == .center ? "center" : "left",
            lineSpacing: Double(lineSpacing.clamped(to: 0.7...1.6)),
            motionAmount: Double(motionAmount.clamped(to: 0...1.5)),
            fontFamily: Self.cssFontFamily(for: font),
            fontSize: Double(font.pointSize.clamped(to: 12...96))
        )
        guard let json = Self.jsonString(payload) else {
            return
        }
        evaluate("window.AMLLHost?.setVisualOptions(\(json));")
    }

    func setAlbumImage(_ image: NSImage?) {
        let dataURL = image.flatMap(Self.pngDataURL)
        guard dataURL != lastAlbumDataURL else {
            return
        }
        lastAlbumDataURL = dataURL
        if let dataURL, let json = Self.jsonString(dataURL) {
            evaluate("window.AMLLHost?.setAlbum(\(json));")
        } else {
            evaluate("window.AMLLHost?.setAlbum(null);")
        }
    }

    private func loadBundle() {
        guard let resourceURL = Bundle.main.resourceURL else {
            showStatus("Missing bundle resource URL")
            loadFailureHTML("Missing bundle resource URL")
            return
        }
        let webRoot = resourceURL.appendingPathComponent("AMLLOriginalThemeWeb", isDirectory: true)
        let indexURL = webRoot.appendingPathComponent("index.html")
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            showStatus("Missing AMLLOriginalThemeWeb/index.html")
            loadFailureHTML("Missing AMLLOriginalThemeWeb/index.html")
            return
        }
        guard let html = try? String(contentsOf: indexURL),
              let scriptPath = Self.firstMatch(in: html, pattern: #"<script\s+defer\s+src="([^"]+\.js)"></script>"#),
              let stylePath = Self.firstMatch(in: html, pattern: #"<link\s+rel="stylesheet"\s+href="([^"]+\.css)">"#) else {
            webView.loadFileURL(indexURL, allowingReadAccessTo: webRoot)
            return
        }
        let scriptURL = webRoot.appendingPathComponent(scriptPath.replacingOccurrences(of: "./", with: ""))
        let styleURL = webRoot.appendingPathComponent(stylePath.replacingOccurrences(of: "./", with: ""))
        guard let script = try? String(contentsOf: scriptURL),
              let style = try? String(contentsOf: styleURL) else {
            webView.loadFileURL(indexURL, allowingReadAccessTo: webRoot)
            return
        }
        let inlineHTML = html
            .replacingOccurrences(
                of: #"<script defer src="\#(scriptPath)"></script>"#,
                with: ""
            )
            .replacingOccurrences(
                of: #"<link rel="stylesheet" href="\#(stylePath)">"#,
                with: "<style>\n\(style)\n</style>"
            )
            .replacingOccurrences(
                of: "</body>",
                with: "<script>\n\(script.replacingOccurrences(of: "</script", with: "<\\/script"))\n</script>\n</body>"
            )
        webView.loadHTMLString(inlineHTML, baseURL: webRoot)
    }

    private static func firstMatch(in string: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, range: range),
              match.numberOfRanges > 1,
              let matchRange = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return String(string[matchRange])
    }

    private func showStatus(_ message: String) {
        statusLabel.stringValue = message
        statusLabel.isHidden = false
    }

    private func inspectScriptState(allowMarkReady: Bool) {
        webView.evaluateJavaScript(
            """
            JSON.stringify({
              hasHost: !!window.AMLLHost,
              hasRoot: !!document.querySelector(".amll-root"),
              hasPlayer: !!document.querySelector(".amll-player"),
              rootHTMLLength: document.getElementById("root") ? document.getElementById("root").innerHTML.length : 0,
              scriptCount: document.scripts.length,
              scripts: Array.from(document.scripts).map(function(script) { return script.src || "inline"; }),
              bodyText: document.body ? document.body.innerText : ""
            })
            """
        ) { [weak self] result, error in
            if let error {
                self?.showStatus("AMLL Original Source script inspection failed")
                log("AMLL Original Source WebView: script inspection failed: \(error.localizedDescription)")
                return
            }
            guard let json = result as? String else {
                return
            }
            log("AMLL Original Source WebView: script state \(json)")
            guard let self, !self.isReady else {
                return
            }
            guard allowMarkReady,
                  json.contains("\"hasHost\":true"),
                  json.contains("\"hasRoot\":true") else {
                if allowMarkReady, let status = Self.statusMessage(fromScriptStateJSON: json) {
                    self.showStatus(status)
                }
                return
            }
            self.isReady = true
            self.statusLabel.isHidden = true
            self.flushPendingScripts()
        }
    }

    private static func statusMessage(fromScriptStateJSON json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let hasHost = object["hasHost"] as? Bool ?? false
        let hasRoot = object["hasRoot"] as? Bool ?? false
        let rootHTMLLength = object["rootHTMLLength"] as? Int ?? 0
        let bodyText = (object["bodyText"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !bodyText.isEmpty, bodyText != "AMLL Original Source loading..." {
            return String(bodyText.prefix(160))
        }
        return "AMLL script did not mount. host=\(hasHost) root=\(hasRoot) html=\(rootHTMLLength)"
    }

    private func shouldIgnoreNavigationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func loadFailureHTML(_ message: String) {
        let escapedMessage = message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        webView.loadHTMLString(
            """
            <!doctype html>
            <html>
            <body style="margin:0;width:100vw;height:100vh;display:grid;place-items:center;background:#1d1d1f;color:white;font:15px -apple-system,BlinkMacSystemFont,sans-serif;">
            \(escapedMessage)
            </body>
            </html>
            """,
            baseURL: nil
        )
    }

    private func evaluate(_ script: String) {
        if isReady {
            webView.evaluateJavaScript(script)
        } else {
            pendingScripts.append(script)
        }
    }

    private func flushPendingScripts() {
        let scripts = pendingScripts
        pendingScripts.removeAll()
        scripts.forEach { webView.evaluateJavaScript($0) }
    }

    private static func makeLyricPayload(_ lyrics: Lyrics?, trackDuration: TimeInterval?) -> [AMLLLyricLine] {
        guard let lyrics else {
            return []
        }
        let enabledLines = lyrics.lines.enumerated().filter { $0.element.enabled && !$0.element.content.isEmpty }
        return enabledLines.enumerated().map { offset, item in
            let sourceIndex = item.offset
            let line = item.element
            let nextPosition = enabledLines.indices.contains(offset + 1)
                ? enabledLines[offset + 1].element.position
                : trackDuration
            let fallbackEndTime: TimeInterval
            if let nextPosition {
                fallbackEndTime = nextPosition
            } else if let duration = line.attachments.timetag?.duration {
                fallbackEndTime = line.position + duration
            } else {
                fallbackEndTime = line.position + 4
            }
            let endTime = max(line.position + 0.8, fallbackEndTime)
            let languageCode = lyrics.metadata.translationLanguages.first
            let translatedLyric = line.attachments.translation(languageCodeCandidate: [languageCode]) ?? ""
            return AMLLLyricLine(
                words: makeWords(line: line, endTime: endTime),
                translatedLyric: translatedLyric,
                romanLyric: "",
                startTime: Int((line.position * 1000).rounded()),
                endTime: Int((endTime * 1000).rounded()),
                isBG: false,
                isDuet: false
            )
        }
    }

    private func copyLyricLine(at pointInOverlay: NSPoint, completion: @escaping (String?) -> Void) {
        let point = webView.convert(pointInOverlay, from: interactionOverlayView)
        let x = point.x.clamped(to: 0...webView.bounds.width)
        let y = (webView.bounds.height - point.y).clamped(to: 0...webView.bounds.height)
        let script = """
        (function() {
          const x = \(Double(x));
          const y = \(Double(y));
          const cleanText = (value) => String(value || "")
            .replace(/\\u00a0/g, " ")
            .replace(/[ \\t]+/g, " ")
            .replace(/\\n+/g, "\\n")
            .trim();
          const className = (element) => String(element && element.className || "");
          const isLyricLine = (element) => {
            const name = className(element);
            return name.includes("lyricLine") && !name.includes("Wrapper");
          };
          const mainLineIn = (element) => {
            if (!element) return null;
            return element.querySelector('[class*="lyricMainLine"]') || element.querySelector('[class*="lyricLine"]') || element;
          };
          let element = document.elementFromPoint(x, y);
          let wrapper = element && element.closest ? element.closest('[class*="lyricLineWrapper"]') : null;
          var target = mainLineIn(wrapper);
          if (!target && element && element.closest) {
            target = element.closest('[class*="lyricMainLine"]') || element.closest('[class*="lyricLine"]');
          }
          if (!target) {
            const candidates = Array.from(document.querySelectorAll('[class*="lyricMainLine"],[class*="lyricLine"]'))
              .filter((candidate) => isLyricLine(candidate) || className(candidate).includes("lyricMainLine"))
              .filter((candidate) => cleanText(candidate.innerText).length > 0)
              .map((candidate) => {
                const rect = candidate.getBoundingClientRect();
                const clampedY = Math.max(rect.top, Math.min(y, rect.bottom));
                const clampedX = Math.max(rect.left, Math.min(x, rect.right));
                const dx = clampedX - x;
                const dy = clampedY - y;
                return { candidate, distance: Math.sqrt(dx * dx + dy * dy), rect };
              })
              .filter((item) => item.rect.width > 0 && item.rect.height > 0)
              .sort((a, b) => a.distance - b.distance);
            target = candidates[0] ? candidates[0].candidate : null;
          }
          return cleanText(target ? target.innerText : "");
        })();
        """
        webView.evaluateJavaScript(script) { result, error in
            if let error {
                log("AMLL Original Source WebView: lyric hit-test failed: \(error.localizedDescription)")
                completion(nil)
                return
            }
            let line = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let line, !line.isEmpty {
                completion(line)
            } else {
                completion(nil)
            }
        }
    }

    private static func makeWords(line: LyricsLine, endTime: TimeInterval) -> [AMLLLyricWord] {
        if let timetag = line.attachments.timetag, !timetag.tags.isEmpty {
            var words: [AMLLLyricWord] = []
            let content = line.content as NSString
            let sortedTags = timetag.tags.sorted { $0.index < $1.index }
            for (index, tag) in sortedTags.enumerated() {
                let nextIndex = sortedTags.indices.contains(index + 1) ? sortedTags[index + 1].index : content.length
                let location = min(max(tag.index, 0), content.length)
                let length = max(0, min(nextIndex, content.length) - location)
                guard length > 0 else {
                    continue
                }
                let word = content.substring(with: NSRange(location: location, length: length))
                let start = line.position + tag.time
                let nextTime = sortedTags.indices.contains(index + 1) ? line.position + sortedTags[index + 1].time : endTime
                words.append(AMLLLyricWord(
                    startTime: Int((start * 1000).rounded()),
                    endTime: Int((max(start + 0.05, nextTime) * 1000).rounded()),
                    word: word,
                    obscene: false
                ))
            }
            if !words.isEmpty {
                return words
            }
        }

        return [
            AMLLLyricWord(
                startTime: Int((line.position * 1000).rounded()),
                endTime: Int((endTime * 1000).rounded()),
                word: line.content,
                obscene: false
            ),
        ]
    }

    private static func pngDataURL(_ image: NSImage) -> String? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return "data:image/png;base64," + pngData.base64EncodedString()
    }

    private static func jsonString<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func cssFontFamily(for font: NSFont) -> String {
        var names: [String] = []
        [font.fontName, font.familyName].forEach { name in
            guard let name, !name.isEmpty, !names.contains(name) else {
                return
            }
            names.append(name)
        }
        let quotedNames = names.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }
        return (quotedNames + ["-apple-system", "BlinkMacSystemFont", "\"PingFang SC\"", "sans-serif"]).joined(separator: ", ")
    }
}

private struct AMLLLyricLine: Encodable {
    let words: [AMLLLyricWord]
    let translatedLyric: String
    let romanLyric: String
    let startTime: Int
    let endTime: Int
    let isBG: Bool
    let isDuet: Bool
}

private struct AMLLLyricWord: Encodable {
    let startTime: Int
    let endTime: Int
    let word: String
    let obscene: Bool
}

private struct AMLLVisualOptions: Encodable {
    let alignment: String
    let lineSpacing: Double
    let motionAmount: Double
    let fontFamily: String
    let fontSize: Double
}

private final class AMLLOriginalHostWebView: WKWebView {
    var lineProvider: ((NSPoint, @escaping (String?) -> Void) -> Void)?
    private var menuLine: String?

    override var mouseDownCanMoveWindow: Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0 else {
            super.mouseDown(with: event)
            return
        }
        window?.performDrag(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        return copyMenu()
    }

    @objc private func copyCurrentLyricLine(_ sender: Any?) {
        guard let line = menuLine, !line.isEmpty else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(line, forType: .string)
    }

    private func copyMenu() -> NSMenu {
        let menu = NSMenu()
        let item = NSMenuItem(title: "复制当前行歌词", action: #selector(copyCurrentLyricLine(_:)), keyEquivalent: "")
        item.target = self
        item.isEnabled = menuLine != nil
        menu.addItem(item)
        return menu
    }
}

private final class AMLLOriginalInteractionOverlayView: NSView {
    var lineProvider: ((NSPoint, @escaping (String?) -> Void) -> Void)?
    private var menuLine: String?

    override var mouseDownCanMoveWindow: Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0 else {
            super.mouseDown(with: event)
            return
        }
        window?.performDrag(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        lineProvider?(point) { [weak self] line in
            guard let self else {
                return
            }
            self.menuLine = line
            NSMenu.popUpContextMenu(self.copyMenu(), with: event, for: self)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        return copyMenu()
    }

    private func copyMenu() -> NSMenu {
        let menu = NSMenu()
        let item = NSMenuItem(title: "复制当前行歌词", action: #selector(copyCurrentLyricLine(_:)), keyEquivalent: "")
        item.target = self
        item.isEnabled = menuLine != nil
        menu.addItem(item)
        return menu
    }

    @objc private func copyCurrentLyricLine(_ sender: Any?) {
        guard let line = menuLine, !line.isEmpty else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(line, forType: .string)
    }
}
