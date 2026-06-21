import SwiftUI
import WebKit

struct WebViewContainer: UIViewRepresentable {
    let url: URL

    // 共享默认 DataStore 保证登录态持久化
    private static let sharedStore = WKWebsiteDataStore.default()

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = Self.sharedStore
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.backgroundColor = UIColor(DS.Color.bgBase)
        webView.scrollView.backgroundColor = UIColor(DS.Color.bgBase)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // 仅当 URL 发生变化时重新加载（避免切换 Tab 时不必要刷新）
        if webView.url?.host != url.host {
            webView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}

// MARK: - ExistingWebViewContainer
// 包装一个已存在的 WKWebView 实例（不新建），供 AccountView 展示 WebViewModel 里的 WebView。
// 这样全 App 只有 2 个 WKWebView，避免内存溢出崩溃。
struct ExistingWebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
