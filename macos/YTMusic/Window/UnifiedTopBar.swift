import AppKit
import WebKit

/// Spotify-style window chrome: no separate title strip. The page is drawn
/// under the title bar, the traffic lights are centred in the page's 64pt top
/// bar, native back/forward arrows sit beside them, and the top bar's empty
/// areas move the window (the page reports those clicks over the bridge).
@MainActor
final class UnifiedTopBar {
    /// Height of YT Music's top bar, which the traffic lights centre in.
    static let height: CGFloat = 64
    /// Page inset reserved on the left for the traffic lights and arrows.
    static let leadingInset: CGFloat = 160

    private static let trafficLightsX: CGFloat = 20
    private static let trafficLightsSpacing: CGFloat = 23
    private static let arrowsX: CGFloat = 92

    private weak var window: NSWindow?
    private weak var webView: HostWebView?
    private let arrows = NSStackView()
    private let back = UnifiedTopBar.arrowButton("chevron.left", label: "Back")
    private let forward = UnifiedTopBar.arrowButton("chevron.right", label: "Forward")
    private var observations: [NSKeyValueObservation] = []
    private var windowObservers: [NSObjectProtocol] = []
    private var standardContainerHeight: CGFloat?
    private(set) var isEnabled = false

    init(window: NSWindow, webView: HostWebView, in container: NSView) {
        self.window = window
        self.webView = webView

        back.target = webView
        back.action = #selector(WKWebView.goBack(_:))
        forward.target = webView
        forward.action = #selector(WKWebView.goForward(_:))

        arrows.orientation = .horizontal
        arrows.spacing = 0
        arrows.addArrangedSubview(back)
        arrows.addArrangedSubview(forward)
        arrows.translatesAutoresizingMaskIntoConstraints = false
        arrows.isHidden = true
        container.addSubview(arrows)
        NSLayoutConstraint.activate([
            arrows.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.arrowsX),
            arrows.centerYAnchor.constraint(equalTo: container.topAnchor, constant: Self.height / 2),
        ])

        observations = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.back.isEnabled = webView.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.forward.isEnabled = webView.canGoForward }
            },
        ]

        // AppKit lays the title bar out again on resize, key changes, full
        // screen and first display; put the lights back after each.
        let events: [Notification.Name] = [
            NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification, NSWindow.didExitFullScreenNotification,
            NSWindow.didChangeOcclusionStateNotification,
        ]
        windowObservers = events.map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setNeedsTrafficLightLayout() }
            }
        }
    }

    /// Lays the lights out now and again on the next turn of the run loop,
    /// after AppKit has finished its own title bar layout.
    func setNeedsTrafficLightLayout() {
        layoutTrafficLights()
        DispatchQueue.main.async { [weak self] in self?.layoutTrafficLights() }
    }

    func setEnabled(_ enabled: Bool) {
        guard let window, enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = .black
        } else {
            window.styleMask.remove(.fullSizeContentView)
            window.backgroundColor = .ytBackground
        }
        arrows.isHidden = !enabled
        setNeedsTrafficLightLayout()
    }

    /// Centres the close/minimise/zoom buttons in the top bar (or restores
    /// them). The buttons live in the title bar container, which is resized to
    /// the top bar's height so they aren't clipped.
    private func layoutTrafficLights() {
        guard let window,
              let close = window.standardWindowButton(.closeButton),
              let container = close.superview?.superview,
              !window.styleMask.contains(.fullScreen) else { return }

        if standardContainerHeight == nil { standardContainerHeight = container.frame.height }
        let height = isEnabled ? Self.height : (standardContainerHeight ?? container.frame.height)

        var frame = container.frame
        frame.size.height = height
        frame.origin.y = window.frame.height - height
        container.frame = frame

        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for (index, type) in types.enumerated() {
            guard let button = window.standardWindowButton(type) else { continue }
            let x = isEnabled ? Self.trafficLightsX + CGFloat(index) * Self.trafficLightsSpacing : 7 + CGFloat(index) * 20
            button.setFrameOrigin(NSPoint(x: x, y: (height - button.frame.height) / 2))
        }
    }

    // MARK: - Window moves requested by the page

    /// The page saw a mouse-down on an empty part of its top bar.
    func beginDrag() {
        guard isEnabled, let window, let event = webView?.lastMouseDown else { return }
        window.performDrag(with: event)
    }

    /// The page saw a double-click on an empty part of its top bar. Honour the
    /// system "double-click a window's title bar to" setting.
    func titleBarDoubleClicked() {
        guard isEnabled, let window else { return }
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window.performMiniaturize(nil)
        case "None": break
        default: window.performZoom(nil)
        }
    }

    private static func arrowButton(_ symbol: String, label: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)!
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))!
        let button = NSButton(image: image, target: nil, action: nil)
        button.isBordered = false
        button.contentTintColor = NSColor(white: 0.7, alpha: 1) // Spotify's subdued #b3b3b3
        button.toolTip = label
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 32),
            button.heightAnchor.constraint(equalToConstant: 32),
        ])
        return button
    }
}

/// WKWebView that remembers the last mouse-down, so a drag the page asks for
/// (asynchronously, over the bridge) can be started from the original event.
final class HostWebView: WKWebView {
    private(set) var lastMouseDown: NSEvent?

    override func mouseDown(with event: NSEvent) {
        lastMouseDown = event
        super.mouseDown(with: event)
    }
}
