import SwiftUI
import WebKit

struct AccountView: View {
    @State private var selectedPlatform: ViewPlatform = .deepSeek

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
        var other: ViewPlatform {
            self == .deepSeek ? .gemini : .deepSeek
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

                    // 主体区：选中的 WebView 全屏展开，未选中的保持最小帧（维持 Session）
                    ZStack(alignment: .bottomTrailing) {
                        // 选中平台 WebView
                        Group {
                            if selectedPlatform == .deepSeek {
                                PlatformWebViewPanel(holder: dsHolder)
                            } else {
                                PlatformWebViewPanel(holder: gmHolder)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                        .overlay(alignment: .top) {
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .fill(selectedPlatform.gradient)
                                .frame(height: 2)
                        }
                        .shadow(color: selectedPlatform.color.opacity(0.2), radius: 16, x: 0, y: 6)

                        // 未选中平台：50x50 状态图标（点击切换）
                        PlatformMiniBadge(platform: selectedPlatform.other) {
                            selectedPlatform = selectedPlatform.other
                        }
                        .padding(.trailing, DS.Space.sm)
                        .padding(.bottom, DS.Space.sm)
                    }
                    .padding(.horizontal, DS.Space.md)
                    .padding(.bottom, 80 + DS.Space.md)

                    // 两个 WebView 均保持在视图层级中（维持登录态），但尺寸设为 0
                    ZStack {
                        PlatformWebViewPanel(holder: dsHolder)
                            .frame(width: selectedPlatform == .deepSeek ? 0 : 0,
                                   height: 0)
                            .opacity(0)
                        PlatformWebViewPanel(holder: gmHolder)
                            .frame(width: selectedPlatform == .gemini ? 0 : 0,
                                   height: 0)
                            .opacity(0)
                    }
                    .frame(width: 0, height: 0)
                }
            }
        }
    }
}

// MARK: - Platform Mini Badge（50x50，点击切换到该平台）

private struct PlatformMiniBadge: View {
    let platform: AccountView.ViewPlatform
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: platform.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(platform.color)
                Text(platform == .deepSeek ? "DS" : "GM")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(platform.color.opacity(0.8))
            }
            .frame(width: 50, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(DS.Color.bgCard.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(platform.color.opacity(0.45), lineWidth: 1.2)
                    )
            )
            .shadow(color: platform.color.opacity(0.25), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PlatformWebHolder

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
                    selected = platform
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
