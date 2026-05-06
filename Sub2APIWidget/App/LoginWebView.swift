import SwiftUI
import WebKit

struct LoginWebView: NSViewRepresentable {
    var instance: InstanceConfig
    var onTokens: (AuthTokenBundle) -> Void
    var onStatus: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTokens: onTokens, onStatus: onStatus)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: instance.loginURL))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onTokens: (AuthTokenBundle) -> Void
        private let onStatus: (String) -> Void

        init(onTokens: @escaping (AuthTokenBundle) -> Void, onStatus: @escaping (String) -> Void) {
            self.onTokens = onTokens
            self.onStatus = onStatus
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            captureTokens(from: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            onStatus(webView.url?.absoluteString ?? "正在载入")
        }

        private func captureTokens(from webView: WKWebView) {
            let script = """
            (() => JSON.stringify({
              accessToken: localStorage.getItem('auth_token'),
              refreshToken: localStorage.getItem('refresh_token'),
              tokenExpiresAt: localStorage.getItem('token_expires_at'),
              authUser: localStorage.getItem('auth_user')
            }))()
            """

            webView.evaluateJavaScript(script) { [weak self] result, _ in
                guard let self,
                      let raw = result as? String,
                      let data = raw.data(using: .utf8),
                      let parsed = try? JSONDecoder().decode(WebAuthPayload.self, from: data),
                      let accessToken = parsed.accessToken?.nilIfBlank
                else {
                    return
                }

                let expiresAt = parsed.tokenExpiresAt
                    .flatMap(Double.init)
                    .map { Date(timeIntervalSince1970: $0 / 1000) }

                let email = parsed.authUser?
                    .data(using: .utf8)
                    .flatMap { try? JSONDecoder().decode(UserDTO.self, from: $0) }
                    .flatMap(\.email)

                self.onTokens(
                    AuthTokenBundle(
                        accessToken: accessToken,
                        refreshToken: parsed.refreshToken?.nilIfBlank,
                        expiresAt: expiresAt,
                        userEmail: email
                    )
                )
            }
        }
    }
}

private struct WebAuthPayload: Decodable {
    var accessToken: String?
    var refreshToken: String?
    var tokenExpiresAt: String?
    var authUser: String?
}
