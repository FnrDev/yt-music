import AppKit

/// Builds the menu bar in code (no storyboard).
@MainActor
enum MainMenu {
    static func build(actions: PlayerMenuActions, windowController: MainWindowController) -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu(actions: actions)))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(viewMenu(windowController: windowController, actions: actions)))
        main.addItem(submenu(actions.makePlaybackMenu()))
        let window = windowMenu(actions: actions)
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        return main
    }

    private static func appMenu(actions: PlayerMenuActions) -> NSMenu {
        let menu = NSMenu(title: "YT Music")
        menu.addItem(withTitle: "About YT Music", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(PlayerMenuActions.showSettings(_:)), ",", target: actions))
        menu.addItem(.separator())
        let services = NSMenu(title: "Services")
        menu.addItem(submenu(services, title: "Services"))
        NSApp.servicesMenu = services
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide YT Music", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit YT Music", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func editMenu() -> NSMenu {
        // Needed for ⌘C/⌘V/⌘A to reach the web view's text fields.
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        menu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return menu
    }

    private static func viewMenu(windowController: MainWindowController, actions: PlayerMenuActions) -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Search", #selector(PlayerMenuActions.search(_:)), "f", target: actions))
        menu.addItem(item("Home", #selector(MainWindowController.goHome(_:)), "h", [.command, .shift], target: windowController))
        menu.addItem(item("Back", #selector(MainWindowController.goBack(_:)), "[", target: windowController))
        menu.addItem(item("Forward", #selector(MainWindowController.goForward(_:)), "]", target: windowController))
        menu.addItem(item("Reload", #selector(MainWindowController.reload(_:)), "r", target: windowController))
        menu.addItem(.separator())
        menu.addItem(item("Actual Size", #selector(MainWindowController.actualSize(_:)), "0", target: windowController))
        menu.addItem(item("Zoom In", #selector(MainWindowController.zoomIn(_:)), "+", target: windowController))
        menu.addItem(item("Zoom Out", #selector(MainWindowController.zoomOut(_:)), "-", target: windowController))
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func windowMenu(actions: PlayerMenuActions) -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(item("YT Music", #selector(PlayerMenuActions.showMainWindow(_:)), "1", target: actions))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        return menu
    }

    private static func item(
        _ title: String,
        _ action: Selector,
        _ key: String,
        _ modifiers: NSEvent.ModifierFlags = [.command],
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }

    private static func submenu(_ menu: NSMenu, title: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title ?? menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
