import AppKit
import UIFoundation

class PreferenceWindowController: AutoActivateWindowController, StoryboardWindowController {
    static var storyboard: NSStoryboard { .init(name: "Preferences", bundle: .main) }

    override func windowDidLoad() {
        super.windowDidLoad()

        guard let window else { return }
        window.minSize = NSSize(width: 900, height: 700)
        window.title = preferenceLocalized("Settings")
    }
}
