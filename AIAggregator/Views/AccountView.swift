import SwiftUI
import WebKit

// ControlPanelView — 双端控制面板（替代原账户管理页）
// 显示 DeepSeek / Gemini 实时状态，含登录入口与可折叠系统日志

struct AccountView: View {
    @EnvironmentObject private var orchestrator: AIOrchestrator

    @State private var showDSLogin   = false
    @State private var showGMLogin   = false
    @State private var showSystemLog = false

    // 登录 WebView 的 holder（共享默认 DataStore，与自动化 WebView 同 Cookie）
    @StateObject private var dsHolder = PlatformWebHolder(urlString: "https://chat.deepseek.com")
    @StateObject private var gmHolder = PlatformWebHolder(urlString: "https://gemini.google.com")

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Gradient.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DS.Space.md) {

                        // ── 页头 ────────────────────────────────────────────
                        ControlPanelHeader()

                        // ── 双端状态卡片 ─────────────────────────────────────
                        HStack(spacing: DS.Space.sm) {
                            PlatformStatusCard(
                                name: "DeepSeek",
                                icon: "sparkles",
                                color: DS.Color.deepSeek,
                                gradient: DS.Gradient.deepSeekAccent,
                                isReady: orchestrator.deepSeekIsReady,
                                isLoading: orchestrator.isDeepSeekLoading
                            ) {
                                showDSLogin = true
                            }

                            PlatformStatusCard(
                                name: "Gemini",
                                icon: "cpu",
                                color: DS.Color.gemini,
                                gradient: DS.Gradient.geminiAccent,
                                isReady: orchestrator.geminiIsReady,
                                isLoading: orchestrator.isGeminiLoading
                            ) {
                                showGMLogin = true
                            }
                        }
                        .padding(.horizontal, DS.Space.md)

                        // ── 使用提示（未就绪时） ─────────────────────────────
                        if !orchestrator.deepSeekIsReady || !orchestrator.geminiIsReady {
                            LoginHintBanner(
                                dsReady: orchestrator.deepSeekIsReady,
                                gmReady: orchestrator.geminiIsReady
                            )
                            .padding(.horizontal, DS.Space.md)
                        }

                        // ── 系统日志折叠区 ──────────────────────────────────
                        SystemLogPanel(
                            log: orchestrator.debugLog,
                            isExpanded: $showSystemLog,
                            onClear: { orchestrator.debugLog = "" }
                        )
                        .padding(.horizontal, DS.Space.md)

                        // ── 整合状态摘要 ─────────────────────────────────────
                        if !orchestrator.mergedResponse.isEmpty {
                            MergedSummaryBadge(charCount: orchestrator.mergedResponse.count)
                                .padding(.horizontal, DS.Space.md)
                        }

                        Color.clear.frame(height: 80 + DS.Space.lg)
                    }
                    .padding(.vertical, DS.Space.sm)
                }
            }
        }
        // ── 登录 Sheet ────────────────────────────────────────────────────
        .sheet(isPresented: $showDSLogin) {
            LoginSheet(
                title: "DeepSeek 登录",
                color: DS.Color.deepSeek,
                webView: dsHolder.webView
            )
        }
        .sheet(isPresented: $showGMLogin) {
            LoginSheet(
                title: "Gemini 登录",
                color: DS.Color.gemini,
                webView: gmHolder.webView
            )
        }
    }
}

// MARK: - Control Panel Header

private struct ControlPanelHeader: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("双端控制面板")
                    .font(DS.Font.displayMedium)
                    .foregroundStyle(
                        LinearGradient(colors: [DS.Color.purpleLight, DS.Color.cyan],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                Text("管理登录状态 · 监控系统运行")
                    .font(DS.Font.labelSmall)
                    .foregroundColor(DS.Color.textSecondary)
            }
            Spacer()
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 20))
                .foregroundColor(DS.Color.cyan.opacity(0.7))
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.md)
        .background(DS.Gradient.navBar.ignoresSafeArea(edges: .top))
    }
}

// MARK: - Platform Status Card

private struct PlatformStatusCard: View {
    let name: String
    let icon: String
    let color: Color
    let gradient: LinearGradient
    let isReady: Bool
    let isLoading: Bool
    let onLogin: () -> Void

    private var statusText: String {
        if isLoading { return "思考中…" }
        return isReady ? "已就绪" : "未登录"
    }
    private var statusColor: Color {
        if isLoading { return DS.Color.warning }
        return isReady ? DS.Color.success : DS.Color.error
    }
    private var statusIcon: String {
        if isLoading { return "circle.dashed" }
        return isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }

    var body: some View {
        VStack(spacing: DS.Space.sm) {
            // 平台图标行
            HStack(spacing: DS.Space.xs) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(color)
                Text(name)
                    .font(DS.Font.titleMedium)
                    .foregroundColor(color)
                Spacer()
                // 状态指示灯
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: statusColor.opacity(0.9), radius: 4)
            }

            Divider().background(color.opacity(0.2))

            // 状态文本
            HStack(spacing: 4) {
                Image(systemName: statusIcon)
                    .font(.system(size: 11))
                    .foregroundColor(statusColor)
                Text(statusText)
                    .font(DS.Font.labelSmall)
                    .foregroundColor(statusColor)
                Spacer()
            }

            // 登录按钮（未就绪时显示）
            if !isReady && !isLoading {
                Button(action: onLogin) {
                    Label("点击登录", systemImage: "arrow.right.circle.fill")
                        .font(DS.Font.labelSmall)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.sm)
                                .fill(gradient)
                        )
                }
                .buttonStyle(.plain)
            } else if isReady {
                Button(action: onLogin) {
                    Text("切换账号")
                        .font(.system(size: 10))
                        .foregroundColor(color.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DS.Space.md)
        .frame(maxWidth: .infinity)
        .glassCard()
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(color.opacity(isReady ? 0.35 : 0.15), lineWidth: 1)
        )
    }
}

// MARK: - Login Hint Banner

private struct LoginHintBanner: View {
    let dsReady: Bool
    let gmReady: Bool

    private var missingPlatforms: String {
        var missing: [String] = []
        if !dsReady { missing.append("DeepSeek") }
        if !gmReady { missing.append("Gemini") }
        return missing.joined(separator: " 和 ")
    }

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(DS.Color.warning)
                .font(.system(size: 14))
            Text("\(missingPlatforms) 尚未登录，请点击对应卡片进行登录，登录后自动化功能将立即可用。")
                .font(DS.Font.bodyMedium)
                .foregroundColor(DS.Color.textSecondary)
                .lineSpacing(3)
        }
        .padding(DS.Space.md)
        .glassCard()
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(DS.Color.warning.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - System Log Panel（折叠式）

private struct SystemLogPanel: View {
    let log: String
    @Binding var isExpanded: Bool
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 折叠触发行
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 13))
                        .foregroundColor(DS.Color.cyan.opacity(0.7))
                    Text("系统日志")
                        .font(DS.Font.titleMedium)
                        .foregroundColor(DS.Color.textSecondary)
                    if !log.isEmpty {
                        Text("\(log.components(separatedBy: "\n").count) 条")
                            .font(.system(size: 10))
                            .foregroundColor(DS.Color.textMuted)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(DS.Color.cyan.opacity(0.1)))
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Color.textMuted)
                }
                .padding(DS.Space.md)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().background(DS.Color.border)

                if log.isEmpty {
                    Text("暂无日志记录")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(DS.Color.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DS.Space.md)
                } else {
                    ScrollView {
                        Text(log)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.green.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(DS.Space.md)
                    }
                    .frame(maxHeight: 250)

                    HStack {
                        Spacer()
                        Button(action: onClear) {
                            Label("清除日志", systemImage: "trash")
                                .font(DS.Font.labelSmall)
                                .foregroundColor(DS.Color.error.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, DS.Space.md)
                        .padding(.bottom, DS.Space.sm)
                    }
                }
            }
        }
        .glassCard()
    }
}

// MARK: - Merged Summary Badge

private struct MergedSummaryBadge: View {
    let charCount: Int
    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(DS.Color.success)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text("整合总结已生成")
                    .font(DS.Font.titleMedium)
                    .foregroundColor(DS.Color.success)
                Text("共 \(charCount) 字 · 请前往工作台查看")
                    .font(DS.Font.labelSmall)
                    .foregroundColor(DS.Color.textSecondary)
            }
            Spacer()
        }
        .padding(DS.Space.md)
        .glassCard()
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(DS.Color.success.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Login Sheet

private struct LoginSheet: View {
    let title: String
    let color: Color
    let webView: WKWebView
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExistingWebViewContainer(webView: webView)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(DS.Color.bgCard, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                            .foregroundColor(color)
                    }
                }
        }
    }
}

// MARK: - PlatformWebHolder（持有登录 WebView，与自动化 WebView 共享 Cookie）

@MainActor
final class PlatformWebHolder: NSObject, ObservableObject {
    let webView: WKWebView

    init(urlString: String) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.allowsInlineMediaPlayback = true
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        wv.allowsBackForwardNavigationGestures = true
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        self.webView = wv
        super.init()
        wv.navigationDelegate = self
        if let url = URL(string: urlString) { wv.load(URLRequest(url: url)) }
    }
}

extension PlatformWebHolder: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView,
                             decidePolicyFor action: WKNavigationAction,
                             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }
}
