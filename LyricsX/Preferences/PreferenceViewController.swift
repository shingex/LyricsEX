import Cocoa

class PreferenceTabViewController: NSTabViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        if !tabViewItems.contains(where: { $0.viewController is PreferenceThemeViewController }) {
            let themeViewController = PreferenceThemeViewController()
            let tabItem = NSTabViewItem(viewController: themeViewController)
            tabItem.label = "Desktop Theme"
            tabItem.image = NSImage(named: NSImage.Name("NSColorPanel"))
            insertTabViewItem(tabItem, at: min(2, tabViewItems.count))
        }

        if !tabViewItems.contains(where: { $0.viewController is PreferenceLyricsWindowThemeViewController }) {
            let themeViewController = PreferenceLyricsWindowThemeViewController()
            let tabItem = NSTabViewItem(viewController: themeViewController)
            tabItem.label = "Lyrics Window Theme"
            tabItem.image = NSImage(named: NSImage.Name("NSColorPanel"))
            insertTabViewItem(tabItem, at: min(3, tabViewItems.count))
        }
    }
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
