import SwiftUI
import WebKit

// MARK: - AccountView（双端控制面板 + 实时 WebView）

struct AccountView: View {
    @EnvironmentObject private var orchestrator: AIOrchestrator
    @State private var showSystemLog = false

    // 登录 WebView（共享默认 DataStore，与自动化 WebView 同 Cookie）
    @StateObject private var dsHolder = PlatformWebHolder(platform: .deepSeek)
    @StateObject private var gmHolder = PlatformWebHolder(platform: .gemini)

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Gradient.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {

                    // ── 紧凑顶栏 ──────────────────────────────────────────────
                    CompactPanelHeader()

                    VStack(spacing: DS.Space.xs) {
                        // 双端状态卡片（30% 更紧凑）
                        HStack(spacing: DS.Space.sm) {
                            CompactStatusCard(
                                name: "DeepSeek",
                                icon: "sparkles",
                                color: DS.Color.deepSeek,
                                gradient: DS.Gradient.deepSeekAccent,
                                isLoggedIn: dsHolder.isLoggedIn,
                                isLoading: orchestrator.isDeepSeekLoading
                            )

                            CompactStatusCard(
                                name: "Gemini",
                                icon: "cpu",
                                color: DS.Color.gemini,
                                gradient: DS.Gradient.geminiAccent,
                                isLoggedIn: gmHolder.isLoggedIn,
                                isLoading: orchestrator.isGeminiLoading
                            )
                        }
                        .padding(.horizontal, DS.Space.md)

                        // 系统日志（DisclosureGroup，默认折叠）
                        SystemLogDisclosure(
                            log: orchestrator.debugLog,
                            isExpanded: $showSystemLog,
                            onClear: { orchestrator.debugLog = "" }
                        )
                        .padding(.horizontal, DS.Space.md)
                    }
                    .padding(.vertical, DS.Space.xs)

                    // ── WebView 并排（填满剩余空间）──────────────────────────
                    HStack(spacing: 2) {
                        WebPanelColumn(
                            title: "DeepSeek",
                            color: DS.Color.deepSeek,
                            isLoggedIn: dsHolder.isLoggedIn,
                            webView: dsHolder.webView
                        )
                        Rectangle()
                            .fill(DS.Color.border)
                            .frame(width: 1)
                        WebPanelColumn(
                            title: "Gemini",
                            color: DS.Color.gemini,
                            isLoggedIn: gmHolder.isLoggedIn,
                            webView: gmHolder.webView
                        )
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, DS.Space.md)
                    .padding(.bottom, 80) // Tab bar 高度
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                    .padding(.horizontal, DS.Space.md)
                }
            }
        }
    }
}

// MARK: - Compact Panel Header

private struct CompactPanelHeader: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("双端控制面板")
                    .font(DS.Font.titleLarge)
                    .foregroundStyle(
                        LinearGradient(colors: [DS.Color.purpleLight, DS.Color.cyan],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                Text("登录状态 · 实时同步")
                    .font(DS.Font.labelSmall)
                    .foregroundColor(DS.Color.textMuted)
            }
            Spacer()
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 16))
                .foregroundColor(DS.Color.cyan.opacity(0.6))
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .background(DS.Gradient.navBar.ignoresSafeArea(edges: .top))
    }
}

// MARK: - Compact Status Card（原卡片缩小约 30%）

private struct CompactStatusCard: View {
    let name: String
    let icon: String
    let color: Color
    let gradient: LinearGradient
    let isLoggedIn: Bool
    let isLoading: Bool

    private var statusColor: Color {
        if isLoading   { return DS.Color.warning }
        return isLoggedIn ? DS.Color.success : DS.Color.error
    }
    private var statusText: String {
        if isLoading   { return "思考中" }
        return isLoggedIn ? "已登录" : "未登录"
    }
    private var statusIcon: String {
        if isLoading   { return "circle.dashed" }
        return isLoggedIn ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            // 平台名 + 图标
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
            Text(name)
                .font(DS.Font.labelSmall)
                .foregroundColor(color)

            Spacer()

            // 状态
            HStack(spacing: 3) {
                if isLoading {
                    ProgressView().tint(statusColor).scaleEffect(0.6)
                } else {
                    Image(systemName: statusIcon)
                        .font(.system(size: 11))
                        .foregroundColor(statusColor)
                }
                Text(statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(statusColor)
            }
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.sm + DS.Space.xs) // ~12pt，原 16pt
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(DS.Color.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .strokeBorder(color.opacity(isLoggedIn ? 0.4 : 0.15), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
    }
}

// MARK: - System Log Disclosure（DisclosureGroup，默认折叠）

private struct SystemLogDisclosure: View {
    let log: String
    @Binding var isExpanded: Bool
    let onClear: () -> Void

    var body: some View {
        DisclosureGroup(
            isExpanded: $isExpanded,
            content: {
                VStack(alignment: .leading, spacing: 0) {
                    Divider().background(DS.Color.border)
                    if log.isEmpty {
                        Text("暂无日志")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(DS.Color.textMuted)
                            .padding(DS.Space.sm)
                    } else {
                        ScrollView {
                            Text(log)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.green.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(DS.Space.sm)
                        }
                        .frame(maxHeight: 160)

                        Button(action: onClear) {
                            Label("清除", systemImage: "trash")
                                .font(.system(size: 10))
                                .foregroundColor(DS.Color.error.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, DS.Space.sm)
                        .padding(.bottom, DS.Space.xs)
                    }
                }
            },
            label: {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 11))
                        .foregroundColor(DS.Color.cyan.opacity(0.65))
                    Text("系统日志")
                        .font(DS.Font.labelSmall)
                        .foregroundColor(DS.Color.textSecondary)
                    if !log.isEmpty {
                        Text("\(log.components(separatedBy: "\n").count)条")
                            .font(.system(size: 9))
                            .foregroundColor(DS.Color.textMuted)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(DS.Color.cyan.opacity(0.08)))
                    }
                }
                .padding(.vertical, DS.Space.xs)
            }
        )
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.xs)
        .accentColor(DS.Color.textMuted)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(DS.Color.bgCard)
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .strokeBorder(DS.Color.border, lineWidth: 1))
        )
    }
}

// MARK: - WebView Panel Column（带标题栏的 WebView 容器）

private struct WebPanelColumn: View {
    let title: String
    let color: Color
    let isLoggedIn: Bool
    let webView: WKWebView

    var body: some View {
        VStack(spacing: 0) {
            // 迷你标题栏
            HStack(spacing: 4) {
                Circle()
                    .fill(isLoggedIn ? DS.Color.success : DS.Color.error)
                    .frame(width: 5, height: 5)
                    .shadow(color: (isLoggedIn ? DS.Color.success : DS.Color.error).opacity(0.8), radius: 3)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
                Spacer()
                Text(isLoggedIn ? "已登录" : "请登录")
                    .font(.system(size: 9))
                    .foregroundColor(isLoggedIn ? DS.Color.success : DS.Color.textMuted)
            }
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, 5)
            .background(DS.Color.bgCard.opacity(0.9))

            Divider().background(color.opacity(0.3))

            // WebView 占满剩余高度
            ExistingWebViewContainer(webView: webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .strokeBorder(color.opacity(0.2), lineWidth: 0.8)
        )
    }
}

// MARK: - PlatformWebHolder（持有登录 WebView + 登录状态扫描）

@MainActor
final class PlatformWebHolder: NSObject, ObservableObject {
    let platform: AIPlatform
    let webView: WKWebView

    @Published var isLoggedIn: Bool = false

    init(platform: AIPlatform) {
        self.platform = platform
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.allowsInlineMediaPlayback = true
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        wv.allowsBackForwardNavigationGestures = true
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        self.webView = wv
        super.init()
        wv.navigationDelegate = self
        wv.load(URLRequest(url: platform.baseURL))
    }

    // MARK: - 登录扫描

    func scanLoginStatus() {
        let script = JSBridge.loginScanScript(platform: platform)
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self, let str = result as? String else { return }
            let loggedIn = (str == "true")
            if self.isLoggedIn != loggedIn {
                self.isLoggedIn = loggedIn
                print("[WebHolder-\(self.platform)] 登录状态变更: \(loggedIn)")
            }
        }
    }

    // 递归5秒轮询（@MainActor 安全）
    func scheduleNextPoll() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self else { return }
            self.scanLoginStatus()
            self.scheduleNextPoll()
        }
    }
}

extension PlatformWebHolder: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 加载完成 2s 后扫描一次，之后每 5s 轮询
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.scanLoginStatus()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.scheduleNextPoll()
        }
    }

    nonisolated func webView(_ webView: WKWebView,
                             decidePolicyFor action: WKNavigationAction,
                             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }

    nonisolated func webView(_ webView: WKWebView,
                             didFail navigation: WKNavigation!,
                             withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        print("[WebHolder] 导航失败: \(error.localizedDescription)")
    }
}
