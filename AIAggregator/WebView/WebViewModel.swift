import WebKit
import Combine

/// 管理后台 DeepSeek / Gemini WKWebView 实例
/// 支持：JS 注入、React InputEvent 回调、页面就绪检测、回复监听
@MainActor
final class WebViewModel: NSObject, ObservableObject {

    // MARK: - 公开状态

    @Published var deepSeekReply: String = ""
    @Published var geminiReply:   String = ""
    @Published var isDeepSeekBusy = false
    @Published var isGeminiBusy   = false

    /// 页面 DOM 就绪状态（输入框 + 发送按钮均已存在）
    @Published var deepSeekIsReady = false
    @Published var geminiIsReady   = false

    // MARK: - 后台 WebView 实例（lazy，首次访问时初始化）

    private(set) lazy var deepSeekWebView: WKWebView = makeWebView(platform: .deepSeek)
    private(set) lazy var geminiWebView:   WKWebView = makeWebView(platform: .gemini)

    // MARK: - Init

    override init() {
        super.init()
        warmUp()
    }

    // MARK: - 公开 API

    func sendToDeepSeek(query: String) async {
        isDeepSeekBusy = true
        deepSeekReply  = ""
        await inject(query: query, into: deepSeekWebView, platform: .deepSeek)
    }

    func sendToGemini(query: String) async {
        isGeminiBusy = true
        geminiReply  = ""
        await inject(query: query, into: geminiWebView, platform: .gemini)
    }

    // MARK: - 私有：预热

    private func warmUp() {
        deepSeekWebView.load(URLRequest(url: AIPlatform.deepSeek.baseURL))
        geminiWebView.load(URLRequest(url: AIPlatform.gemini.baseURL))
    }

    // MARK: - 私有：WebView 工厂

    private func makeWebView(platform: AIPlatform) -> WKWebView {
        let config = WKWebViewConfiguration()
        // 使用默认 DataStore：与 AccountView 中展示的 WebView 共享 Cookie / Session
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.allowsInlineMediaPlayback = true

        let controller = WKUserContentController()

        // ── 注册所有消息通道 ────────────────────────────────────────
        // 回复通道
        controller.add(LeakAvoider(delegate: self), name: platform.messageHandler)
        // 错误通道
        controller.add(LeakAvoider(delegate: self), name: "\(platform.messageHandler)_error")
        // 就绪检测通道
        controller.add(LeakAvoider(delegate: self), name: "\(platform.messageHandler)_ready")

        // ── 预注入全局监听脚本（每次页面导航后自动重注入）────────────
        let listenerScript = WKUserScript(
            source: JSBridge.globalListenerScript(platform: platform),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        controller.addUserScript(listenerScript)
        config.userContentController = controller

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        // 使用桌面 UA，防止网站限制功能
        wv.customUserAgent = """
        Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) \
        AppleWebKit/605.1.15 (KHTML, like Gecko) \
        Version/17.0 Safari/605.1.15
        """
        return wv
    }

    // MARK: - 私有：JS 注入

    private func inject(query: String, into webView: WKWebView, platform: AIPlatform) async {
        let script = JSBridge.buildInputScript(query: query, platform: platform)
        _ = try? await webView.evaluateJavaScript(script)
    }
}

// MARK: - WKScriptMessageHandler

extension WebViewModel: WKScriptMessageHandler {

    nonisolated func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? String else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }

            switch message.name {

            // ── 正常回复 ──────────────────────────────────────────
            case AIPlatform.deepSeek.messageHandler:
                self.deepSeekReply  = body
                self.isDeepSeekBusy = false

            case AIPlatform.gemini.messageHandler:
                self.geminiReply  = body
                self.isGeminiBusy = false

            // ── 就绪检测结果 ──────────────────────────────────────
            case "\(AIPlatform.deepSeek.messageHandler)_ready":
                self.deepSeekIsReady = (body == "true")
                if !self.deepSeekIsReady {
                    print("[WebViewModel] DeepSeek isReady=false — 详情见浏览器控制台 console.warn")
                }

            case "\(AIPlatform.gemini.messageHandler)_ready":
                self.geminiIsReady = (body == "true")
                if !self.geminiIsReady {
                    print("[WebViewModel] Gemini isReady=false — 详情见浏览器控制台 console.warn")
                }

            // ── 错误回调 ──────────────────────────────────────────
            case "\(AIPlatform.deepSeek.messageHandler)_error":
                print("[WebViewModel] DeepSeek JS 错误: \(body)")
                self.isDeepSeekBusy = false

            case "\(AIPlatform.gemini.messageHandler)_error":
                print("[WebViewModel] Gemini JS 错误: \(body)")
                self.isGeminiBusy = false

            default:
                break
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension WebViewModel: WKNavigationDelegate {

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let platform: AIPlatform = (webView === self.deepSeekWebView) ? .deepSeek : .gemini

            // React SPA 通常在 DOMContentLoaded 后继续渲染，等待 2 秒再检测
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            let readyScript = JSBridge.pageReadyCheckScript(platform: platform)
            _ = try? await webView.evaluateJavaScript(readyScript)
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        print("[WebViewModel] 导航失败: \(error.localizedDescription)")
    }

    nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(.allow)
    }
}

// MARK: - WKUIDelegate（处理登录页弹窗、OAuth 新窗口）

extension WebViewModel: WKUIDelegate {
    nonisolated func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // 把 window.open() 跳转在当前 WebView 内打开，避免白屏
        if let url = navigationAction.request.url {
            Task { @MainActor in webView.load(URLRequest(url: url)) }
        }
        return nil
    }

    nonisolated func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    nonisolated func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

// MARK: - LeakAvoider（打破 WKUserContentController 强引用循环）

private final class LeakAvoider: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(delegate: WKScriptMessageHandler) { self.delegate = delegate }

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(controller, didReceive: message)
    }
}
