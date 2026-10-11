import AppKit
import SwiftUI
import WebKit

struct LoginWebView: NSViewRepresentable {
    private static let messageHandlerName = "sub2apiAuth"

    var instance: InstanceConfig
    var onTokens: (AuthTokenBundle) -> Void
    var onStatus: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(instance: instance, onTokens: onTokens, onStatus: onStatus)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.addUserScript(Self.authObserverScript)
        configuration.userContentController.add(context.coordinator, name: Self.messageHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: instance.loginURL))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.update(instance: instance)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.stopLoading()
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: messageHandlerName)
        nsView.navigationDelegate = nil
        nsView.uiDelegate = nil
    }

    private static let authObserverScript = WKUserScript(
        source: """
        (() => {
          if (window.__sub2apiAuthObserverInstalled) return;
          window.__sub2apiAuthObserverInstalled = true;

          const emitAuth = () => {
            window.webkit.messageHandlers.sub2apiAuth.postMessage({
              accessToken: localStorage.getItem('auth_token'),
              refreshToken: localStorage.getItem('refresh_token'),
              tokenExpiresAt: localStorage.getItem('token_expires_at'),
              authUser: localStorage.getItem('auth_user')
            });
          };

          const originalSetItem = Storage.prototype.setItem;
          Storage.prototype.setItem = function(key, value) {
            originalSetItem.call(this, key, value);
            if (this === window.localStorage) setTimeout(emitAuth, 0);
          };

          window.addEventListener('storage', emitAuth);
          emitAuth();

          // Poll as a fallback for sessions restored without a setItem write,
          // but back off and stop entirely once the token is captured.
          let ticks = 0;
          const timer = window.setInterval(() => {
            ticks += 1;
            if (localStorage.getItem('auth_token')) {
              emitAuth();
              window.clearInterval(timer);
              return;
            }
            if (ticks >= 20) window.clearInterval(timer);
          }, 500);
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
    )

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private var instance: InstanceConfig
        private let onTokens: (AuthTokenBundle) -> Void
        private let onStatus: (String) -> Void
        private var didCaptureTokens = false

        init(
            instance: InstanceConfig,
            onTokens: @escaping (AuthTokenBundle) -> Void,
            onStatus: @escaping (String) -> Void
        ) {
            self.instance = instance
            self.onTokens = onTokens
            self.onStatus = onStatus
        }

        func update(instance: InstanceConfig) {
            if self.instance.baseURL.normalizedOrigin != instance.baseURL.normalizedOrigin {
                didCaptureTokens = false
            }
            self.instance = instance
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            captureTokens(from: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            onStatus(webView.url?.absoluteString ?? "正在载入")
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.targetFrame?.isMainFrame != false,
                  let url = navigationAction.request.url
            else {
                decisionHandler(.allow)
                return
            }

            guard url.hasSameOrigin(as: instance.baseURL) else {
                if navigationAction.targetFrame == nil || navigationAction.navigationType == .linkActivated {
                    openExternally(url)
                }
                onStatus("已阻止离开登录实例：\(url.host ?? url.absoluteString)")
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                if url.hasSameOrigin(as: instance.baseURL) {
                    webView.load(URLRequest(url: url))
                } else {
                    openExternally(url)
                }
            }
            return nil
        }

        /// Only web URLs may be handed to the system handler; anything else
        /// (file://, smb://, custom app schemes) is dropped.
        private func openExternally(_ url: URL) {
            guard let scheme = url.scheme?.lowercased(),
                  ["http", "https", "mailto"].contains(scheme)
            else {
                onStatus("已阻止打开非网页链接：\(url.scheme ?? "未知协议")")
                return
            }
            NSWorkspace.shared.open(url)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == LoginWebView.messageHandlerName,
                  message.frameInfo.isMainFrame,
                  securityOriginMatches(message.frameInfo.securityOrigin),
                  let payload = WebAuthPayload(messageBody: message.body)
            else {
                return
            }
            accept(payload: payload)
        }

        private func captureTokens(from webView: WKWebView) {
            guard webView.url?.hasSameOrigin(as: instance.baseURL) == true else { return }
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
                      let payload = try? JSONDecoder().decode(WebAuthPayload.self, from: data)
                else {
                    return
                }
                self.accept(payload: payload)
            }
        }

        private func accept(payload: WebAuthPayload) {
            guard !didCaptureTokens, let accessToken = payload.accessToken?.nilIfBlank else { return }
            didCaptureTokens = true

            let expiresAt = payload.tokenExpiresAt
                .flatMap(Double.init)
                .map { Date(timeIntervalSince1970: $0 / 1000) }
            let email = payload.authUser?
                .data(using: .utf8)
                .flatMap { try? JSONDecoder().decode(UserDTO.self, from: $0) }
                .flatMap(\.email)

            onTokens(
                AuthTokenBundle(
                    accessToken: accessToken,
                    refreshToken: payload.refreshToken?.nilIfBlank,
                    expiresAt: expiresAt,
                    userEmail: email,
                    origin: instance.baseURL.normalizedOrigin
                )
            )
        }

        private func securityOriginMatches(_ origin: WKSecurityOrigin) -> Bool {
            let scheme = origin.protocol.lowercased()
            let defaultPort = scheme == "https" ? 443 : (scheme == "http" ? 80 : 0)
            let port = origin.port == 0 ? defaultPort : origin.port
            return "\(scheme)://\(origin.host.lowercased()):\(port)" == instance.baseURL.normalizedOrigin
        }
    }
}

@MainActor
enum WebSessionStore {
    static func clearAllData() async {
        let store = WKWebsiteDataStore.default()
        await withCheckedContinuation { continuation in
            store.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast
            ) {
                continuation.resume()
            }
        }
    }
}

private struct WebAuthPayload: Decodable {
    var accessToken: String?
    var refreshToken: String?
    var tokenExpiresAt: String?
    var authUser: String?

    init?(messageBody: Any) {
        guard let body = messageBody as? [String: Any] else { return nil }
        accessToken = body["accessToken"] as? String
        refreshToken = body["refreshToken"] as? String
        tokenExpiresAt = body["tokenExpiresAt"] as? String
        authUser = body["authUser"] as? String
    }
}
