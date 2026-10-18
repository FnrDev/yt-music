import AppKit
import WebKit

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    static let homeURL = URL(string: "https://music.youtube.com/")!

    let webView: HostWebView
    private let navigation = WebNavigationHandler()
    private let theme: ThemeController
    private let spinner = NSProgressIndicator()
    private var loadObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private let navigationAccessory = NSTitlebarAccessoryViewController()
    private var topBar: UnifiedTopBar!
    private var isOffYTMusic = false

    init(bridge: WebBridge) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default() // persist the Google sign-in
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        // Without a Safari token Google sign-in rejects the view as an "insecure browser".
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        bridge.install(into: configuration.userContentController)
        theme = ThemeController(bridge: bridge)
        theme.install(into: configuration.userContentController)

        webView = HostWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.underPageBackgroundColor = .ytBackground
        #if DEBUG
        webView.isInspectable = true
        #endif

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "YT Music"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .ytBackground
        window.appearance = NSAppearance(named: .darkAqua) // YouTube Music is dark-only
        window.minSize = NSSize(width: 820, height: 560)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.delegate = self
        let content = makeContentView()
        window.contentView = content
        topBar = UnifiedTopBar(window: window, webView: webView, in: content)
        window.center()
        window.setFrameAutosaveName("MainWindow")

        webView.navigationDelegate = navigation
        webView.uiDelegate = navigation
        bridge.attach(to: webView)
        bridge.onWindowDrag = { [weak self] in self?.topBar.beginDrag() }
        bridge.onTitleBarDoubleClick = { [weak self] in self?.topBar.titleBarDoubleClicked() }
        theme.attach(to: webView)
        // The Spotify-style theme draws its own top bar under the traffic lights.
        theme.onThemeApplied = { [weak self] theme in self?.applyChrome(for: theme) }
        applyChrome(for: AppSettings.theme)

        loadObservation = webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                // Only cover the very first load; later navigations are in-page.
                if !webView.isLoading { self?.spinner.removeFromSuperview() }
            }
        }

        installNavigationAccessory(in: window)
        updateNavigationAccessory()
        urlObservation = webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                // YT Music has its own navigation; Google sign-in and other
                // in-app pages don't, so offer a way back from those.
                let onYTMusic = webView.url?.host?.lowercased() == Self.homeURL.host
                self?.isOffYTMusic = webView.url != nil && !onYTMusic
                self?.updateNavigationAccessory()
            }
        }

        webView.load(URLRequest(url: Self.homeURL))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Back / "YT Music" buttons in the title bar, shown only away from music.youtube.com.
    private func installNavigationAccessory(in window: NSWindow) {
        let back = NSButton(
            image: NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: "Back")!,
            target: self,
            action: #selector(goBack(_:))
        )
        back.toolTip = "Back"

        let home = NSButton(title: "YT Music", target: self, action: #selector(goHome(_:)))
        home.image = NSImage(systemSymbolName: "music.note.house", accessibilityDescription: nil)
        home.imagePosition = .imageLeading
        home.toolTip = "Return to YouTube Music"

        for button in [back, home] {
            button.bezelStyle = .accessoryBarAction
            button.controlSize = .small
        }

        let stack = NSStackView(views: [back, home])
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        stack.frame.size = stack.fittingSize

        navigationAccessory.view = stack
        navigationAccessory.layoutAttribute = .leading
        navigationAccessory.isHidden = true
        window.addTitlebarAccessoryViewController(navigationAccessory)
    }

    private func applyChrome(for theme: ThemeController.Theme) {
        topBar?.setEnabled(theme == .spotifyStyle)
        updateNavigationAccessory()
    }

    private func updateNavigationAccessory() {
        guard let window else { return }
        // The unified top bar has its own back/forward arrows, so the accessory
        // is detached there (AppKit re-shows hidden accessories when the window
        // style changes).
        let unified = topBar?.isEnabled ?? false
        let attached = window.titlebarAccessoryViewControllers.contains(navigationAccessory)
        if unified, attached, let index = window.titlebarAccessoryViewControllers.firstIndex(of: navigationAccessory) {
            window.removeTitlebarAccessoryViewController(at: index)
        } else if !unified, !attached, navigationAccessory.view.frame.width > 0 {
            window.addTitlebarAccessoryViewController(navigationAccessory)
        }
        navigationAccessory.isHidden = !isOffYTMusic
    }

    private func makeContentView() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.ytBackground.cgColor

        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)

        spinner.style = .spinning
        spinner.controlSize = .large
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimation(nil)
        container.addSubview(spinner)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            spinner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        topBar.setNeedsTrafficLightLayout()
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard AppSettings.keepPlayingWhenClosed else {
            NSApp.terminate(nil)
            return false
        }
        // Hide instead of closing so the web view (and the music) keeps running.
        if sender.styleMask.contains(.fullScreen) {
            sender.toggleFullScreen(nil)
        }
        sender.orderOut(nil)
        return false
    }

    // MARK: - Menu actions

    @objc func goHome(_ sender: Any?) {
        webView.load(URLRequest(url: Self.homeURL))
    }

    @objc func goBack(_ sender: Any?) { webView.goBack() }
    @objc func goForward(_ sender: Any?) { webView.goForward() }
    @objc func reload(_ sender: Any?) { webView.reload() }

    #if DEBUG
    /// Debug builds only: runs the clipboard as an async JS function body in the
    /// page and puts the JSON result back on the clipboard. Lets tooling inspect
    /// the live DOM without the Web Inspector.
    @objc func evaluateClipboardJavaScript(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        guard let body = pasteboard.string(forType: .string) else { return }
        let wrapped = "const result = await (async () => { \(body) })(); return JSON.stringify(result ?? null);"
        Task {
            let output: String
            do {
                output = (try await webView.callAsyncJavaScript(wrapped, contentWorld: .page) as? String) ?? "null"
            } catch {
                output = "ERROR: \(error)"
            }
            pasteboard.clearContents()
            pasteboard.setString(output, forType: .string)
        }
    }
    #endif

    @objc func zoomIn(_ sender: Any?) { webView.pageZoom = min(webView.pageZoom + 0.1, 2.0) }
    @objc func zoomOut(_ sender: Any?) { webView.pageZoom = max(webView.pageZoom - 0.1, 0.5) }
    @objc func actualSize(_ sender: Any?) { webView.pageZoom = 1.0 }
}

extension MainWindowController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(goBack(_:)): webView.canGoBack
        case #selector(goForward(_:)): webView.canGoForward
        default: true
        }
    }
}

extension NSColor {
    /// YouTube Music's page background.
    static let ytBackground = NSColor(srgbRed: 0.012, green: 0.012, blue: 0.012, alpha: 1)
}
