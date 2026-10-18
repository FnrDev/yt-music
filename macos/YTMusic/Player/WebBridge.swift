import WebKit
import os

/// Connects `ytm-bridge.js` running in the page to `PlayerModel`.
@MainActor
final class WebBridge: NSObject, WKScriptMessageHandler {
    static let handlerName = "ytm"
    private static let supportedVersion = 1
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "YTMusic", category: "bridge")

    private let model: PlayerModel
    private weak var webView: WKWebView?
    private let decoder = JSONDecoder()
    /// The injected bridge script, kept so other scripts can be swapped around it.
    private(set) var userScript: WKUserScript?
    /// The page's top bar asks to move or zoom the window (see UnifiedTopBar).
    var onWindowDrag: (() -> Void)?
    var onTitleBarDoubleClick: (() -> Void)?
    /// Replies to `search` commands.
    var onSearchResults: ((_ requestId: Int, _ results: [SearchResult], _ filters: [SearchFilter], _ error: String?) -> Void)?
    var onLibrary: ((_ requestId: Int, _ recent: [SearchResult], _ playlists: [SearchResult]) -> Void)?
    var onQueue: ((_ requestId: Int, _ items: [QueueItem]) -> Void)?
    var onLyrics: ((_ requestId: Int, _ videoId: String?, _ text: String?, _ source: String?, _ error: String?) -> Void)?

    init(model: PlayerModel) {
        self.model = model
        super.init()
    }

    /// Installs the bridge script and message handler on a configuration.
    func install(into controller: WKUserContentController) {
        guard let url = Bundle.main.url(forResource: "ytm-bridge", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            Self.log.fault("ytm-bridge.js missing from bundle")
            return
        }
        let script = WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: .page
        )
        userScript = script
        controller.addUserScript(script)
        // The controller retains its handlers; go through a weak proxy to avoid a cycle.
        controller.add(WeakScriptMessageHandler(self), contentWorld: .page, name: Self.handlerName)
    }

    func attach(to webView: WKWebView) {
        self.webView = webView
        model.commandSink = { [weak self] command in
            self?.webView?.evaluateJavaScript(command.javaScript, in: nil, in: .page)
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let body = message.body as? String,
              let data = body.data(using: .utf8) else { return }

        do {
            let envelope = try decoder.decode(Envelope.self, from: data)
            switch envelope.type {
            case "ready":
                if envelope.version != Self.supportedVersion {
                    Self.log.warning("Unexpected bridge version \(envelope.version ?? -1)")
                }
                Self.log.info("Bridge ready (v\(envelope.version ?? 0))")
                model.reset()
            case "state":
                if let state = envelope.state {
                    let old = model.state
                    if state.trackKey != old.trackKey || state.isPlaying != old.isPlaying || state.volume != old.volume {
                        Self.log.info("state: \(state.title, privacy: .public) — playing=\(state.isPlaying) volume=\(state.volume)")
                    }
                    model.update(state)
                }
            case "searchResults":
                onSearchResults?(envelope.requestId ?? -1, envelope.results ?? [], envelope.filters ?? [], envelope.error)
            case "library":
                onLibrary?(envelope.requestId ?? -1, envelope.recent ?? [], envelope.playlists ?? [])
            case "queue":
                onQueue?(envelope.requestId ?? -1, envelope.items ?? [])
            case "lyrics":
                onLyrics?(envelope.requestId ?? -1, envelope.videoId, envelope.text, envelope.source, envelope.error)
            case "windowDrag":
                onWindowDrag?()
            case "windowZoom":
                onTitleBarDoubleClick?()
            default:
                break
            }
        } catch {
            Self.log.error("Bad bridge message: \(error.localizedDescription)")
        }
    }

    private struct Envelope: Decodable {
        let type: String
        let version: Int?
        let state: PlayerState?
        let requestId: Int?
        let results: [SearchResult]?
        let filters: [SearchFilter]?
        let recent: [SearchResult]?
        let playlists: [SearchResult]?
        let items: [QueueItem]?
        let videoId: String?
        let text: String?
        let source: String?
        let error: String?
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?

    init(_ target: any WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
