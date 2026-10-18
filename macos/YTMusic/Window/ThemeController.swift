import WebKit
import os

/// Injects the selected stylesheet from shared/themes into the page and swaps
/// it live when the setting changes.
@MainActor
final class ThemeController {
    enum Theme: String, CaseIterable, Identifiable {
        case youtubeMusic = "default"
        case spotifyStyle = "spotify-style"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .youtubeMusic: "YouTube Music"
            case .spotifyStyle: "Spotify-style"
            }
        }

        /// Stylesheet in the app bundle (copied from shared/themes), if any.
        var stylesheetName: String? {
            self == .youtubeMusic ? nil : rawValue
        }
    }

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "YTMusic", category: "theme")
    private static let styleElementID = "ytm-host-theme"

    private let bridge: WebBridge
    private weak var controller: WKUserContentController?
    private weak var webView: WKWebView?
    private var applied: Theme?
    /// Called after a theme is applied (including the initial one).
    var onThemeApplied: ((Theme) -> Void)?
    private var defaultsObserver: NSObjectProtocol?

    init(bridge: WebBridge) {
        self.bridge = bridge
    }

    func install(into controller: WKUserContentController) {
        self.controller = controller
        apply(AppSettings.theme)
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply(AppSettings.theme) }
        }
    }

    func attach(to webView: WKWebView) {
        self.webView = webView
    }

    private func apply(_ theme: Theme) {
        guard theme != applied, let controller else { return }
        applied = theme

        let source = Self.script(css: stylesheet(for: theme), behaviour: companionScript(for: theme))
        defer { onThemeApplied?(theme) }
        // User scripts can't be removed one at a time, so rebuild the set.
        controller.removeAllUserScripts()
        if let bridgeScript = bridge.userScript {
            controller.addUserScript(bridgeScript)
        }
        controller.addUserScript(WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .page
        ))
        // Restyle the page that's already loaded.
        webView?.evaluateJavaScript(source, in: nil, in: .page)
    }

    private func stylesheet(for theme: Theme) -> String {
        guard let name = theme.stylesheetName else { return "" }
        guard let url = Bundle.main.url(forResource: name, withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8) else {
            Self.log.fault("Theme \(name, privacy: .public).css missing from bundle")
            return ""
        }
        // Themed windows draw the page under the title bar; tell the page how
        // much room the traffic lights and arrows need.
        let hostVariables = "html { --ytm-host-titlebar-left: \(Int(UnifiedTopBar.leadingInset))px; }\n"
        return hostVariables + css
    }

    /// Optional `<theme>.js` next to the stylesheet, for things CSS can't do.
    private func companionScript(for theme: Theme) -> String {
        guard let name = theme.stylesheetName,
              let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return js
    }

    /// JS that installs (or, for empty CSS, removes) a single <style> element,
    /// and swaps the theme's companion script: the previous one is cleaned up
    /// through `window.__ytmThemeCleanup`, which each companion must register.
    private static func script(css: String, behaviour: String) -> String {
        let literal = (try? String(data: JSONEncoder().encode(css), encoding: .utf8)) ?? "\"\""
        return """
        (() => {
          const css = \(literal);
          const runBehaviour = () => {
            window.__ytmThemeCleanup?.();
            \(behaviour)
          };
          // Once per injection; the companion waits for the elements it needs.
          runBehaviour();
          const apply = () => {
            let style = document.getElementById('\(styleElementID)');
            if (!css) { style?.remove(); return; }
            if (!style) {
              style = document.createElement('style');
              style.id = '\(styleElementID)';
            }
            style.textContent = css;
            // Append last so it wins over the site's own stylesheets.
            (document.head || document.documentElement).appendChild(style);
          };
          if (document.documentElement) apply();
          else document.addEventListener('readystatechange', apply, { once: true });
          document.addEventListener('DOMContentLoaded', apply, { once: true });
        })();
        """
    }
}
