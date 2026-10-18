import AppKit
import SwiftUI

/// Menu bar ("tray") controls.
/// Left-click opens the mini-player popover; right-click (or ⌃-click) opens a
/// quick controls menu.
@MainActor
final class StatusItemController: NSObject {
    private let model: PlayerModel
    private let actions: PlayerMenuActions
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var hosting: NSHostingController<MiniPlayerView>!
    private var defaultsObserver: NSObjectProtocol?

    private static let maxTitleLength = 32

    init(model: PlayerModel, actions: PlayerMenuActions) {
        self.model = model
        self.actions = actions
        super.init()

        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.animates = true
        hosting = NSHostingController(rootView: MiniPlayerView(
            model: model,
            onShowWindow: { [weak self] in
                self?.popover.performClose(nil)
                actions.showMainWindow(nil)
            },
            onShowSettings: { [weak self] in
                self?.popover.performClose(nil)
                actions.showSettings(nil)
            }
        ))
        // Size the popover ourselves (see togglePopover) rather than letting it
        // track SwiftUI's ideal size while open.
        hosting.sizingOptions = []
        popover.contentViewController = hosting

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.toolTip = "YT Music"
        }
        statusItem.autosaveName = "YTMusicStatusItem"

        model.observe { [weak self] old, new in
            if old.title != new.title || old.artist != new.artist
                || old.isPlaying != new.isPlaying || old.hasTrack != new.hasTrack {
                self?.refreshButton()
            }
        }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        }
        applySettings()
    }

    private func applySettings() {
        statusItem.isVisible = AppSettings.showMenuBarIcon
        if !statusItem.isVisible { popover.performClose(nil) }
        refreshButton()
    }

    private func refreshButton() {
        guard let button = statusItem.button else { return }
        let state = model.state
        let symbol = state.hasTrack && state.isPlaying ? "music.note" : "music.note.list"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "YT Music")
        image?.isTemplate = true
        button.image = image

        if AppSettings.showTitleInMenuBar, state.hasTrack {
            var title = [state.title, state.artist].filter { !$0.isEmpty }.joined(separator: " — ")
            if title.count > Self.maxTitleLength {
                title = String(title.prefix(Self.maxTitleLength - 1)) + "…"
            }
            button.title = " " + title
        } else {
            button.title = ""
        }
        button.toolTip = state.hasTrack ? "\(state.title)\n\(state.artist)" : "YT Music"
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            popover.performClose(nil)
            showMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.contentSize = hosting.sizeThatFits(in: NSSize(
                width: MiniPlayerView.width,
                height: .greatestFiniteMagnitude
            ))
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        let menu = actions.makePlayerMenu(includeAppItems: true)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // so left-click keeps opening the popover
    }
}
