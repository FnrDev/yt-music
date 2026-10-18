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
        controller.addUserScript(WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: .page
        ))
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
                    if state.trackKey != model.state.trackKey || state.isPlaying != model.state.isPlaying {
                        Self.log.debug("state: \(state.title, privacy: .public) — playing=\(state.isPlaying)")
                    }
                    model.update(state)
                }
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
