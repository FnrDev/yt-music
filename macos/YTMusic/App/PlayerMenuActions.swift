import AppKit
import SwiftUI

/// Menu actions shared by the main menu bar, the Dock menu and the status item menu.
@MainActor
final class PlayerMenuActions: NSObject, NSMenuItemValidation {
    private let model: PlayerModel
    private let windowController: MainWindowController
    private var settingsWindow: NSWindow?

    init(model: PlayerModel, windowController: MainWindowController) {
        self.model = model
        self.windowController = windowController
    }

    // MARK: - Actions

    @objc func playPause(_ sender: Any?) { model.send(.playPause) }
    @objc func nextTrack(_ sender: Any?) { model.send(.next) }
    @objc func previousTrack(_ sender: Any?) { model.send(.previous) }
    @objc func like(_ sender: Any?) { model.send(.like) }
    @objc func dislike(_ sender: Any?) { model.send(.dislike) }
    @objc func volumeUp(_ sender: Any?) { model.adjustVolume(by: 10) }
    @objc func volumeDown(_ sender: Any?) { model.adjustVolume(by: -10) }
    @objc func seekForward(_ sender: Any?) { model.send(.seek(model.position() + 10)) }
    @objc func seekBackward(_ sender: Any?) { model.send(.seek(max(model.position() - 10, 0))) }

    @objc func search(_ sender: Any?) {
        windowController.show()
        model.send(.focusSearch)
    }

    @objc func showMainWindow(_ sender: Any?) {
        windowController.show()
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let state = model.state
        switch item.action {
        case #selector(playPause(_:)):
            item.title = state.isPlaying ? "Pause" : "Play"
            return state.hasTrack
        case #selector(like(_:)):
            item.state = state.likeStatus == .like ? .on : .off
            return state.hasTrack
        case #selector(dislike(_:)):
            item.state = state.likeStatus == .dislike ? .on : .off
            return state.hasTrack
        case #selector(nextTrack(_:)), #selector(previousTrack(_:)),
             #selector(seekForward(_:)), #selector(seekBackward(_:)),
             #selector(volumeUp(_:)), #selector(volumeDown(_:)):
            return state.hasTrack
        default:
            return true
        }
    }

    // MARK: - Menus

    /// Playback items with now-playing info on top; used by the Dock and status item.
    func makePlayerMenu(includeAppItems: Bool) -> NSMenu {
        let menu = NSMenu()
        let state = model.state

        if state.hasTrack {
            menu.addItem(infoItem(state.title, font: .boldSystemFont(ofSize: NSFont.systemFontSize)))
            if !state.artist.isEmpty {
                menu.addItem(infoItem(state.artist, font: .menuFont(ofSize: 0)))
            }
        } else {
            menu.addItem(infoItem("Nothing playing", font: .menuFont(ofSize: 0)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Play", #selector(playPause(_:)), symbol: state.isPlaying ? "pause.fill" : "play.fill"))
        menu.addItem(item("Next", #selector(nextTrack(_:)), symbol: "forward.fill"))
        menu.addItem(item("Previous", #selector(previousTrack(_:)), symbol: "backward.fill"))
        menu.addItem(.separator())
        menu.addItem(item("Like", #selector(like(_:)), symbol: "hand.thumbsup"))
        menu.addItem(item("Dislike", #selector(dislike(_:)), symbol: "hand.thumbsdown"))

        if includeAppItems {
            menu.addItem(.separator())
            menu.addItem(item("Show YT Music", #selector(showMainWindow(_:))))
            menu.addItem(item("Settings…", #selector(showSettings(_:))))
            menu.addItem(.separator())
            let quit = NSMenuItem(title: "Quit YT Music", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
            menu.addItem(quit)
        }
        return menu
    }

    /// Items for the main menu bar's Playback menu, with shortcuts.
    func makePlaybackMenu() -> NSMenu {
        let menu = NSMenu(title: "Playback")
        menu.addItem(item("Play", #selector(playPause(_:)), key: "\r", modifiers: [.command]))
        menu.addItem(item("Next", #selector(nextTrack(_:)), key: arrow(NSRightArrowFunctionKey), modifiers: [.command]))
        menu.addItem(item("Previous", #selector(previousTrack(_:)), key: arrow(NSLeftArrowFunctionKey), modifiers: [.command]))
        menu.addItem(.separator())
        menu.addItem(item("Skip Forward 10 s", #selector(seekForward(_:)), key: arrow(NSRightArrowFunctionKey), modifiers: [.command, .option]))
        menu.addItem(item("Skip Back 10 s", #selector(seekBackward(_:)), key: arrow(NSLeftArrowFunctionKey), modifiers: [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Volume Up", #selector(volumeUp(_:)), key: arrow(NSUpArrowFunctionKey), modifiers: [.command]))
        menu.addItem(item("Volume Down", #selector(volumeDown(_:)), key: arrow(NSDownArrowFunctionKey), modifiers: [.command]))
        menu.addItem(.separator())
        menu.addItem(item("Like", #selector(like(_:)), key: "l", modifiers: [.command]))
        menu.addItem(item("Dislike", #selector(dislike(_:)), key: "l", modifiers: [.command, .shift]))
        return menu
    }

    private func item(
        _ title: String,
        _ action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [],
        symbol: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return item
    }

    private func infoItem(_ title: String, font: NSFont) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])
        item.isEnabled = false
        return item
    }

    private func arrow(_ key: Int) -> String {
        String(Character(UnicodeScalar(UInt16(key))!))
    }
}
