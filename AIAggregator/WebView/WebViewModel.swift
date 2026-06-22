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

    /// JS 层最新上报的单条调试事件（AIOrchestrator 订阅后聚合到 debugLog）
    @Published var debugEntry: String = ""

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
    // 使用 completion handler 版 evaluateJavaScript，避免 async 版本在
    // 某些 WebView 状态下抛出 ObjC NSException（Swift try? 无法捕获）

    func sendToDeepSeek(query: String) {
        isDeepSeekBusy = true
        deepSeekReply  = ""
        let script = JSBridge.buildInputScript(query: query, platform: .deepSeek)
        deepSeekWebView.evaluateJavaScript(script) { [weak self] _, error in
            if let error { print("[WVM] DeepSeek JS error: \(error)") }
            self?.isDeepSeekBusy = false
        }
    }

    func sendToGemini(query: String) {
        isGeminiBusy = true
        geminiReply  = ""
        let script = JSBridge.buildInputScript(query: query, platform: .gemini)
        geminiWebView.evaluateJavaScript(script) { [weak self] _, error in
            if let error { print("[WVM] Gemini JS error: \(error)") }
            self?.isGeminiBusy = false
        }
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
        // UI 可见诊断通道（JS 主动上报，显示在 debugLabel）
        controller.add(LeakAvoider(delegate: self), name: "\(platform.messageHandler)_debug")

        // ── 预注入全局监听脚本（每次页面导航后自动重注入）────────────
        let listenerScript = WKUserScript(
            source: JSBridge.globalListenerScript(platform: platform),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        controller.addUserScript(listenerScript)
        config.userContentController = controller

        // 给后台 WebView 一个非零视口：frame:.zero 会让 window.innerWidth/Height=0，
        // React 的懒渲染可能因此不挂载按钮等组件
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        return wv
    }

    // MARK: - 诊断日志辅助

    func postDebug(_ message: String) {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        debugEntry = "[\(fmt.string(from: Date()))] \(message)"
    }

    // pageReadyCheck 同样用 completion handler
    func checkPageReady(platform: AIPlatform) {
        let wv = platform == .deepSeek ? deepSeekWebView : geminiWebView
        let script = JSBridge.pageReadyCheckScript(platform: platform)
        wv.evaluateJavaScript(script) { _, error in
            if let error { print("[WVM] readyCheck error: \(error)") }
        }
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
            print("[WVM] 收到数据流片段，通道=\(message.name)，内容长度=\(body.count)，当前状态：DS忙=\(self.isDeepSeekBusy) GM忙=\(self.isGeminiBusy)")

            switch message.name {

            // ── 正常回复 ──────────────────────────────────────────
            case AIPlatform.deepSeek.messageHandler:
                print("[WVM] ✅ DeepSeek 回复，长度=\(body.count)")
                self.deepSeekReply  = body
                self.isDeepSeekBusy = false

            case AIPlatform.gemini.messageHandler:
                print("[WVM] ✅ Gemini 回复，长度=\(body.count)")
                self.geminiReply  = body
                self.isGeminiBusy = false

            // ── 就绪检测结果 ──────────────────────────────────────
            case "\(AIPlatform.deepSeek.messageHandler)_ready":
                self.deepSeekIsReady = (body == "true")
                print("[WVM] DeepSeek isReady=\(body)")

            case "\(AIPlatform.gemini.messageHandler)_ready":
                self.geminiIsReady = (body == "true")
                print("[WVM] Gemini isReady=\(body)")

            // ── 错误回调 ──────────────────────────────────────────
            case "\(AIPlatform.deepSeek.messageHandler)_error":
                print("[WVM] ❌ DeepSeek JS 错误: \(body)")
                self.isDeepSeekBusy = false
                self.postDebug("[DS❌] \(body)")

            case "\(AIPlatform.gemini.messageHandler)_error":
                print("[WVM] ❌ Gemini JS 错误: \(body)")
                self.isGeminiBusy = false
                self.postDebug("[GM❌] \(body)")

            // ── UI 诊断日志 ───────────────────────────────────────
            case "\(AIPlatform.deepSeek.messageHandler)_debug":
                print("[WVM] 🔍 DS诊断: \(body)")
                self.postDebug("[DS] \(body)")

            case "\(AIPlatform.gemini.messageHandler)_debug":
                print("[WVM] 🔍 GM诊断: \(body)")
                self.postDebug("[GM] \(body)")

            default:
                print("[WVM] ⚠️ 未知通道: \(message.name)")
                break
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension WebViewModel: WKNavigationDelegate {

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            let platform: AIPlatform = (webView === self.deepSeekWebView) ? .deepSeek : .gemini
            self.checkPageReady(platform: platform)
        }
        // DOM 结构探测：页面加载 4 秒后执行，结果显示在 debugLabel
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self else { return }
            let platform: AIPlatform = (webView === self.deepSeekWebView) ? .deepSeek : .gemini
            let probeScript = JSBridge.domProbeScript(platform: platform)
            webView.evaluateJavaScript(probeScript) { _, error in
                if let error { print("[WVM] domProbe error: \(error)") }
            }
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
