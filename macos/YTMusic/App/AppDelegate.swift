import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = PlayerModel()
    private let artworkLoader = ArtworkLoader()
    private var bridge: WebBridge!
    private var windowController: MainWindowController!
    private var actions: PlayerMenuActions!
    private var nowPlaying: NowPlayingController!
    private var notifier: TrackNotifier!
    private var statusItem: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.registerDefaults()

        bridge = WebBridge(model: model)
        windowController = MainWindowController(bridge: bridge)
        actions = PlayerMenuActions(model: model, windowController: windowController)
        nowPlaying = NowPlayingController(model: model, artworkLoader: artworkLoader)
        notifier = TrackNotifier(model: model, artworkLoader: artworkLoader)
        statusItem = StatusItemController(model: model, actions: actions)

        NSApp.mainMenu = MainMenu.build(actions: actions, windowController: windowController)
        windowController.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { windowController.show() }
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        actions.makePlayerMenu(includeAppItems: false)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
