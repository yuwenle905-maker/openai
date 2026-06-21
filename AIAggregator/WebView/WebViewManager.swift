// WebViewManager.swift — 双引擎 WKWebView 生命周期管理
// 职责：后台预热、登录态持久化、JS 注入、回复监听、错误兜底

import WebKit
import Combine
import SwiftUI

// MARK: - Session State

enum WebSessionState: Equatable {
    case initializing          // 首次加载中
    case needsLogin            // 页面已加载但用户未登录
    case ready                 // 登录完成，可接受查询
    case sending               // 正在注入 JS / 等待回复
    case error(String)         // 加载或注入失败

    var isReady: Bool { self == .ready }

    var displayText: String {
        switch self {
        case .initializing:    return "连接中…"
        case .needsLogin:      return "请前往「账户」页面登录"
        case .ready:           return "就绪"
        case .sending:         return "思考中…"
        case .error(let msg):  return "错误：\(msg)"
        }
    }
}

// MARK: - WebViewManager

/// 单例：统一管理 DeepSeek 与 Gemini 两个后台 WKWebView 实例
@MainActor
final class WebViewManager: NSObject, ObservableObject {

    // ── 单例 ────────────────────────────────────────────────────────────────
    static let shared = WebViewManager()

    // ── 公开状态 ─────────────────────────────────────────────────────────────
    @Published var deepSeekState: WebSessionState = .initializing
    @Published var geminiState:   WebSessionState = .initializing
    @Published var deepSeekReply: String = ""
    @Published var geminiReply:   String = ""

    // ── WebView 实例（外部只读，供 AccountView 嵌入展示） ─────────────────────
    private(set) lazy var deepSeekWebView: WKWebView = makeWebView(platform: .deepSeek)
    private(set) lazy var geminiWebView:   WKWebView = makeWebView(platform: .gemini)

    // ── 内部 ─────────────────────────────────────────────────────────────────
    private var observers: [NSKeyValueObservation] = []

    // MARK: Init

    private override init() {
        super.init()
        warmUp()
    }

    // MARK: - Public API

    /// 向指定平台发送查询（并发安全：MainActor 保证）
    func send(query: String, to platform: AIPlatform) async {
        switch platform {
        case .deepSeek:
            guard deepSeekState.isReady else { return }
            deepSeekState = .sending
            deepSeekReply = ""
            await inject(query: query, into: deepSeekWebView, platform: .deepSeek)
        case .gemini:
            guard geminiState.isReady else { return }
            geminiState = .sending
            geminiReply = ""
            await inject(query: query, into: geminiWebView, platform: .gemini)
        }
    }

    /// 并发向双端发送同一查询
    func sendBoth(query: String) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.send(query: query, to: .deepSeek) }
            group.addTask { await self.send(query: query, to: .gemini) }
        }
    }

    /// 触发整合：以 Gemini 为整合引擎
    func merge(deepSeekAnswer: String, geminiAnswer: String) async {
        let mergeQuery = JSBridge.buildMergeScript(
            deepSeekAnswer: deepSeekAnswer,
            geminiAnswer: geminiAnswer
        )
        geminiState = .sending
        geminiReply = ""
        _ = try? await geminiWebView.evaluateJavaScript(mergeQuery)
    }

    // MARK: - Private: WebView Factory

    private func makeWebView(platform: AIPlatform) -> WKWebView {
        let config = WKWebViewConfiguration()

        // ── 关键：使用 default DataStore 保证 Cookie / Session 持久化 ──────
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // ── 注册 JS → Swift 消息通道 ────────────────────────────────────────
        let controller = WKUserContentController()
        controller.add(LeakAvoider(delegate: self), name: platform.messageHandler)
        controller.add(LeakAvoider(delegate: self), name: "\(platform.messageHandler)_error")
        config.userContentController = controller

        // ── 注入全局监听脚本（页面每次导航后自动重注入） ──────────────────────
        let listenerScript = WKUserScript(
            source: JSBridge.globalListenerScript(platform: platform),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        controller.addUserScript(listenerScript)

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.backgroundColor = UIColor(DS.Color.bgBase)
        wv.scrollView.backgroundColor = UIColor(DS.Color.bgBase)
        wv.allowsBackForwardNavigationGestures = true

        // 桌面 UA 让网页展示完整版（部分网站移动版功能受限）
        wv.customUserAgent = """
        Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) \
        AppleWebKit/605.1.15 (KHTML, like Gecko) \
        Version/17.0 Safari/605.1.15
        """

        // ── KVO 监听 URL 变化以更新登录状态 ─────────────────────────────────
        let obs = wv.observe(\.url, options: .new) { [weak self] webView, _ in
            Task { @MainActor [weak self] in
                self?.detectLoginState(webView: webView, platform: platform)
            }
        }
        observers.append(obs)

        return wv
    }

    // MARK: - Private: Warm Up

    private func warmUp() {
        deepSeekWebView.load(URLRequest(url: AIPlatform.deepSeek.baseURL))
        geminiWebView.load(URLRequest(url: AIPlatform.gemini.baseURL))
    }

    // MARK: - Private: JS Injection

    private func inject(query: String, into webView: WKWebView, platform: AIPlatform) async {
        let script = JSBridge.buildInputScript(query: query, platform: platform)
        do {
            _ = try await webView.evaluateJavaScript(script)
        } catch {
            handleError(error.localizedDescription, platform: platform)
        }
    }

    // MARK: - Private: Login Detection

    private func detectLoginState(webView: WKWebView, platform: AIPlatform) {
        guard let url = webView.url?.absoluteString else { return }
        let isOnLoginPage: Bool
        switch platform {
        case .deepSeek:
            isOnLoginPage = url.contains("login") || url.contains("sign")
        case .gemini:
            isOnLoginPage = url.contains("accounts.google") || url.contains("signin")
        }

        let newState: WebSessionState = isOnLoginPage ? .needsLogin : .ready
        switch platform {
        case .deepSeek: if deepSeekState != newState { deepSeekState = newState }
        case .gemini:   if geminiState   != newState { geminiState   = newState }
        }
    }

    // MARK: - Private: Error Handling

    private func handleError(_ message: String, platform: AIPlatform) {
        switch platform {
        case .deepSeek:
            deepSeekState = .error(message)
        case .gemini:
            geminiState   = .error(message)
        }
    }
}

// MARK: - WKScriptMessageHandler

extension WebViewManager: WKScriptMessageHandler {
    nonisolated func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? String else { return }

        Task { @MainActor in
            switch message.name {
            case AIPlatform.deepSeek.messageHandler:
                self.deepSeekReply = body
                self.deepSeekState = .ready
            case AIPlatform.gemini.messageHandler:
                self.geminiReply = body
                self.geminiState = .ready
            case "\(AIPlatform.deepSeek.messageHandler)_error":
                self.handleError(body, platform: .deepSeek)
            case "\(AIPlatform.gemini.messageHandler)_error":
                self.handleError(body, platform: .gemini)
            default:
                break
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension WebViewManager: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView,
                             didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            let platform: AIPlatform = (webView === self.deepSeekWebView) ? .deepSeek : .gemini
            self.detectLoginState(webView: webView, platform: platform)
        }
    }

    nonisolated func webView(_ webView: WKWebView,
                             didFail navigation: WKNavigation!,
                             withError error: Error) {
        Task { @MainActor in
            let platform: AIPlatform = (webView === self.deepSeekWebView) ? .deepSeek : .gemini
            // 忽略取消导航的伪错误（URLError -999）
            if (error as NSError).code != NSURLErrorCancelled {
                self.handleError(error.localizedDescription, platform: platform)
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView,
                             didFailProvisionalNavigation navigation: WKNavigation!,
                             withError error: Error) {
        Task { @MainActor in
            let platform: AIPlatform = (webView === self.deepSeekWebView) ? .deepSeek : .gemini
            if (error as NSError).code != NSURLErrorCancelled {
                self.handleError(error.localizedDescription, platform: platform)
            }
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(.allow)
    }
}

// MARK: - WKUIDelegate（处理弹窗、新窗口）

extension WebViewManager: WKUIDelegate {
    nonisolated func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // 将新窗口链接在当前 WebView 内打开（避免白屏）
        if let url = navigationAction.request.url {
            Task { @MainActor in webView.load(URLRequest(url: url)) }
        }
        return nil
    }
}

// MARK: - AIPlatform

enum AIPlatform {
    case deepSeek
    case gemini

    var baseURL: URL {
        switch self {
        case .deepSeek: return URL(string: "https://chat.deepseek.com")!
        case .gemini:   return URL(string: "https://gemini.google.com")!
        }
    }

    var messageHandler: String {
        switch self {
        case .deepSeek: return "deepSeekReply"
        case .gemini:   return "geminiReply"
        }
    }

    var displayName: String {
        switch self {
        case .deepSeek: return "DeepSeek"
        case .gemini:   return "Gemini"
        }
    }

    var accentColor: Color {
        switch self {
        case .deepSeek: return DS.Color.deepSeek
        case .gemini:   return DS.Color.gemini
        }
    }

    var accentGradient: LinearGradient {
        switch self {
        case .deepSeek: return DS.Gradient.deepSeekAccent
        case .gemini:   return DS.Gradient.geminiAccent
        }
    }
}

// MARK: - Leak Avoider（防止 WKUserContentController 强引用循环）

/// WKUserContentController 强持有 messageHandler，
/// 用此 Wrapper 打破循环引用
private class LeakAvoider: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(delegate: WKScriptMessageHandler) { self.delegate = delegate }

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        delegate?.userContentController(controller, didReceive: message)
    }
}
