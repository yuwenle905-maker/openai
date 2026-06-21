import SwiftUI
import WebKit

struct AccountView: View {
    @State private var selectedPlatform: AIPlatform = .deepSeek

    enum AIPlatform: String, CaseIterable {
        case deepSeek = "DeepSeek"
        case gemini   = "Gemini"

        var url: URL {
            switch self {
            case .deepSeek: return URL(string: "https://chat.deepseek.com")!
            case .gemini:   return URL(string: "https://gemini.google.com")!
            }
        }

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
                    // 导航栏
                    AccountNavBar()

                    // 平台切换 Segment
                    PlatformSegmentPicker(selected: $selectedPlatform)
                        .padding(DS.Space.md)

                    // WebView 容器
                    WebViewContainer(url: selectedPlatform.url)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                        .padding(.horizontal, DS.Space.md)
                        .padding(.bottom, 80 + DS.Space.md)
                        .overlay(alignment: .top) {
                            // 顶部高光条
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .fill(selectedPlatform.gradient)
                                .frame(height: 2)
                                .padding(.horizontal, DS.Space.md)
                        }
                        .shadow(color: selectedPlatform.color.opacity(0.2), radius: 16, x: 0, y: 6)
                        .animation(.easeInOut(duration: 0.3), value: selectedPlatform)
                }
            }
        }
    }
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
    @Binding var selected: AccountView.AIPlatform

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            ForEach(AccountView.AIPlatform.allCases, id: \.self) { platform in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selected = platform
                    }
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
