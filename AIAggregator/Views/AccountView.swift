import SwiftUI
import WebKit

struct AccountView: View {
    @State private var selectedPlatform: ViewPlatform = .deepSeek

    // 两个独立 WKWebView，用 @StateObject 保证只创建一次
    @StateObject private var dsHolder = PlatformWebHolder(urlString: "https://chat.deepseek.com")
    @StateObject private var gmHolder = PlatformWebHolder(urlString: "https://gemini.google.com")

    enum ViewPlatform: String, CaseIterable {
        case deepSeek = "DeepSeek"
        case gemini   = "Gemini"

        var color: Color {
            switch self {
            case .deepSeek: return DS.Color.deepSeek
            case .gemini:   return DS.Color.gemini
            }
        }
        var gradient: LinearGradient {
            switch self {
            case .deepSeek: return DS.Gradient.deepSeekAccent
            case .gemini:   return DS.Gradient.geminiAccent
            }
        }
        var icon: String {
            switch self {
            case .deepSeek: return "sparkles"
            case .gemini:   return "cpu"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Gradient.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    AccountNavBar()

                    PlatformSegmentPicker(selected: $selectedPlatform)
                        .padding(DS.Space.md)

                    // ZStack + opacity：两个 WebView 永远都在视图层级里，
                    // 切换时只改透明度，完全不做 add/remove/swap，杜绝 UIKit 崩溃
                    ZStack {
                        PlatformWebViewPanel(holder: dsHolder)
                            .opacity(selectedPlatform == .deepSeek ? 1 : 0)
                            .allowsHitTesting(selectedPlatform == .deepSeek)

                        PlatformWebViewPanel(holder: gmHolder)
                            .opacity(selectedPlatform == .gemini ? 1 : 0)
                            .allowsHitTesting(selectedPlatform == .gemini)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                    .padding(.horizontal, DS.Space.md)
                    .padding(.bottom, 80 + DS.Space.md)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .fill(selectedPlatform.gradient)
                            .frame(height: 2)
                            .padding(.horizontal, DS.Space.md)
                    }
                    .shadow(color: selectedPlatform.color.opacity(0.2), radius: 16, x: 0, y: 6)
                }
            }
        }
    }
}

// MARK: - PlatformWebHolder
// 持有单个平台的 WKWebView，@MainActor 保证主线程初始化

@MainActor
final class PlatformWebHolder: NSObject, ObservableObject {
    let webView: WKWebView

    init(urlString: String) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.allowsInlineMediaPlayback = true
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.allowsBackForwardNavigationGestures = true
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        self.webView = wv
        super.init()
        wv.navigationDelegate = self
        if let url = URL(string: urlString) {
            wv.load(URLRequest(url: url))
        }
    }
}

extension PlatformWebHolder: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView,
                             decidePolicyFor action: WKNavigationAction,
                             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }
}

// MARK: - PlatformWebViewPanel
// 把 WKWebView 固定放入 UIKit 层；只做 makeUIView，永不 swap

private struct PlatformWebViewPanel: UIViewRepresentable {
    let holder: PlatformWebHolder

    func makeUIView(context: Context) -> WKWebView { holder.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - Nav Bar

private struct AccountNavBar: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("账户管理")
                    .font(DS.Font.displayMedium)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [DS.Color.purpleLight, DS.Color.cyan],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                Text("登录后聊天记录将自动同步")
                    .font(DS.Font.labelSmall)
                    .foregroundColor(DS.Color.textSecondary)
            }
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 20))
                .foregroundColor(DS.Color.success)
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.md)
        .background(DS.Gradient.navBar.ignoresSafeArea(edges: .top))
    }
}

// MARK: - Platform Segment Picker

private struct PlatformSegmentPicker: View {
    @Binding var selected: AccountView.ViewPlatform

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            ForEach(AccountView.ViewPlatform.allCases, id: \.self) { platform in
                Button {
                    selected = platform          // 无动画，避免 WKWebView 快照崩溃
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: platform.icon)
                            .font(.system(size: 13, weight: .semibold))
                        Text(platform.rawValue)
                            .font(DS.Font.titleMedium)
                    }
                    .foregroundColor(selected == platform ? .white : DS.Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        Group {
                            if selected == platform {
                                RoundedRectangle(cornerRadius: DS.Radius.sm)
                                    .fill(platform.gradient)
                                    .shadow(color: platform.color.opacity(0.4), radius: 8, x: 0, y: 3)
                            } else {
                                RoundedRectangle(cornerRadius: DS.Radius.sm)
                                    .fill(DS.Color.bgInput)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DS.Space.xs)
        .glassCard(cornerRadius: DS.Radius.sm + DS.Space.xs)
    }
}
