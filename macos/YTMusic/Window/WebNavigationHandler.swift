import AppKit
import WebKit

/// Keeps YouTube Music and Google sign-in inside the app; sends everything
/// else (artist websites, help pages, …) to the default browser.
@MainActor
final class WebNavigationHandler: NSObject, WKNavigationDelegate, WKUIDelegate {
    private static let inAppDomains = [
        "youtube.com", "youtu.be", "ytimg.com", "googlevideo.com",
        "google.com", "gstatic.com", "googleusercontent.com", "googleapis.com",
        "accounts.youtube.com", "consent.youtube.com",
    ]

    static func belongsInApp(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "about" || scheme == "blob" || scheme == "data" { return true }
        guard scheme == "https" || scheme == "http", let host = url.host?.lowercased() else { return false }
        if inAppDomains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return true }
        // Regional Google sign-in hosts, e.g. accounts.google.com.sa / google.co.uk.
        return host.range(of: #"(^|\.)google\.(co\.)?[a-z]{2,3}(\.[a-z]{2})?$"#, options: .regularExpression) != nil
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = action.request.url,
              action.targetFrame?.isMainFrame ?? true,
              !Self.belongsInApp(url) else {
            decisionHandler(.allow)
            return
        }
        NSWorkspace.shared.open(url)
        decisionHandler(.cancel)
    }

    /// `target=_blank` links and `window.open`.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = action.request.url {
            if Self.belongsInApp(url) {
                webView.load(action.request)
            } else {
                NSWorkspace.shared.open(url)
            }
        }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}
