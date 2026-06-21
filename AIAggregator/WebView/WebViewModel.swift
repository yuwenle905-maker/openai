import WebKit
import Combine

/// 管理后台 DeepSeek / Gemini WKWebView 实例，支持 JS 注入与消息回调
@MainActor
final class WebViewModel: NSObject, ObservableObject {
    // MARK: - Public State
    @Published var deepSeekReply: String = ""
    @Published var geminiReply: String = ""
    @Published var isDeepSeekBusy = false
    @Published var isGeminiBusy = false

    // MARK: - Private WebViews (后台预热)
    private(set) lazy var deepSeekWebView: WKWebView = makeWebView(handler: "deepSeekReply")
    private(set) lazy var geminiWebView: WKWebView   = makeWebView(handler: "geminiReply")

    // MARK: - Init
    override init() {
        super.init()
        warmUp()
    }

    // MARK: - Public API

    func sendToDeepSeek(query: String) async {
        isDeepSeekBusy = true
        deepSeekReply = ""
        await injectQuery(query, into: deepSeekWebView, platform: .deepSeek)
    }

    func sendToGemini(query: String) async {
        isGeminiBusy = true
        geminiReply = ""
        await injectQuery(query, into: geminiWebView, platform: .gemini)
    }

    // MARK: - Private

    private func warmUp() {
        let dsReq = URLRequest(url: URL(string: "https://chat.deepseek.com")!)
        let gmReq = URLRequest(url: URL(string: "https://gemini.google.com")!)
        deepSeekWebView.load(dsReq)
        geminiWebView.load(gmReq)
    }

    private func makeWebView(handler: String) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()

        let controller = WKUserContentController()
        controller.add(self, name: handler)
        config.userContentController = controller

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        return wv
    }

    private func injectQuery(_ query: String, into webView: WKWebView, platform: JSBridge.Platform) async {
        let script = JSBridge.buildInputScript(query: query, platform: platform)
        _ = try? await webView.evaluateJavaScript(script)
    }
}

// MARK: - WKScriptMessageHandler

extension WebViewModel: WKScriptMessageHandler {
    nonisolated func userContentController(_ controller: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        guard let body = message.body as? String else { return }
        Task { @MainActor in
            if message.name == "deepSeekReply" {
                self.deepSeekReply = body
                self.isDeepSeekBusy = false
            } else if message.name == "geminiReply" {
                self.geminiReply = body
                self.isGeminiBusy = false
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension WebViewModel: WKNavigationDelegate {}
