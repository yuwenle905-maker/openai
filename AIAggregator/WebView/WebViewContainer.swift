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
// 用一个普通 UIView 作壳，WKWebView 作子视图挂进去。
// 切换平台时 updateUIView 负责换子视图，不会触发 UIKit
// "A view can only be inserted in one place at a time" 崩溃。
struct ExistingWebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        let shell = UIView()
        shell.backgroundColor = .clear
        attach(webView, to: shell)
        return shell
    }

    func updateUIView(_ shell: UIView, context: Context) {
        guard shell.subviews.first !== webView else { return }
        shell.subviews.forEach { $0.removeFromSuperview() }
        attach(webView, to: shell)
    }

    private func attach(_ wv: WKWebView, to shell: UIView) {
        wv.removeFromSuperview()          // 先从原有父视图脱离
        shell.addSubview(wv)
        wv.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: shell.topAnchor),
            wv.leadingAnchor.constraint(equalTo: shell.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: shell.trailingAnchor),
            wv.bottomAnchor.constraint(equalTo: shell.bottomAnchor),
        ])
    }
}
