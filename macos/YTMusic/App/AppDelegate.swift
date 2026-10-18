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
    private var volumeKeeper: VolumeKeeper!
    private var search: SearchModel!
    private var library: LibraryModel!
    private var queue: QueueModel!
    private var lyrics: LyricsModel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.registerDefaults()

        artworkLoader.bind(to: model)
        volumeKeeper = VolumeKeeper(model: model)
        bridge = WebBridge(model: model)
        search = SearchModel(player: model)
        library = LibraryModel(player: model)
        queue = QueueModel(player: model)
        lyrics = LyricsModel(player: model)
        bridge.onSearchResults = { [weak search] requestId, results, filters, error in
            search?.receive(requestId: requestId, results: results, filters: filters, error: error)
        }
        bridge.onLibrary = { [weak library] requestId, recent, playlists in
            library?.receive(requestId: requestId, recent: recent, playlists: playlists)
        }
        bridge.onQueue = { [weak queue] requestId, items in
            queue?.receive(requestId: requestId, items: items)
        }
        bridge.onLyrics = { [weak lyrics] requestId, _, text, source, error in
            lyrics?.receive(requestId: requestId, text: text, source: source, error: error)
        }
        windowController = MainWindowController(bridge: bridge)
        actions = PlayerMenuActions(model: model, windowController: windowController)
        nowPlaying = NowPlayingController(model: model, artworkLoader: artworkLoader)
        notifier = TrackNotifier(model: model, artworkLoader: artworkLoader)
        statusItem = StatusItemController(
            model: model,
            panels: PopoverPanels(search: search, library: library, queue: queue, lyrics: lyrics),
            actions: actions
        )

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
