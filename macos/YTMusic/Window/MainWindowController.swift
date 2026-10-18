import AppKit
import WebKit

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    static let homeURL = URL(string: "https://music.youtube.com/")!

    let webView: WKWebView
    private let navigation = WebNavigationHandler()
    private let spinner = NSProgressIndicator()
    private var loadObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private let navigationAccessory = NSTitlebarAccessoryViewController()

    init(bridge: WebBridge) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default() // persist the Google sign-in
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        // Without a Safari token Google sign-in rejects the view as an "insecure browser".
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        bridge.install(into: configuration.userContentController)

        webView = WKWebView(frame: .zero, configuration: configuration)
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
        window.contentView = makeContentView()
        window.center()
        window.setFrameAutosaveName("MainWindow")

        webView.navigationDelegate = navigation
        webView.uiDelegate = navigation
        bridge.attach(to: webView)

        loadObservation = webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                // Only cover the very first load; later navigations are in-page.
                if !webView.isLoading { self?.spinner.removeFromSuperview() }
            }
        }

        installNavigationAccessory(in: window)
        urlObservation = webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                // YT Music has its own navigation; Google sign-in and other
                // in-app pages don't, so offer a way back from those.
                let onYTMusic = webView.url?.host?.lowercased() == Self.homeURL.host
                self?.navigationAccessory.isHidden = webView.url == nil || onYTMusic
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
