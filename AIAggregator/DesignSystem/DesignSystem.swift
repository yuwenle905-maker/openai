// DesignSystem.swift — AI Aggregator 设计规范
// 风格：深色 CRM / Glassmorphism / 渐变层次感
// 使用方式：全局 import，所有视图通过 DS.* 引用

import SwiftUI

// MARK: - Namespace

enum DS {}

// MARK: - Color Palette

extension DS {
    enum Color {
        // ── 背景层次 ──────────────────────────────────────────────
        /// 最深背景 #121212
        static let bgBase        = SwiftUI.Color(hex: "#121212")
        /// 卡片底层 #1A1A2E (Deep Ocean 底调)
        static let bgCard        = SwiftUI.Color(hex: "#1A1A2E")
        /// 卡片浮层 #1E1E3A
        static let bgCardElevated = SwiftUI.Color(hex: "#1E1E3A")
        /// 输入框背景
        static let bgInput       = SwiftUI.Color(hex: "#16213E")

        // ── 主色系：Deep Ocean Blue × Royal Purple ─────────────
        static let primary       = SwiftUI.Color(hex: "#1A73E8")   // Ocean Blue
        static let primaryLight  = SwiftUI.Color(hex: "#4A9EFF")
        static let purple        = SwiftUI.Color(hex: "#7C3AED")   // Royal Purple
        static let purpleLight   = SwiftUI.Color(hex: "#A78BFA")

        // ── 强调色：Electric Cyan × Sunset Orange ──────────────
        static let cyan          = SwiftUI.Color(hex: "#00D4FF")   // Electric Cyan
        static let cyanDim       = SwiftUI.Color(hex: "#00D4FF").opacity(0.15)
        static let orange        = SwiftUI.Color(hex: "#FF6B35")   // Sunset Orange
        static let orangeDim     = SwiftUI.Color(hex: "#FF6B35").opacity(0.15)

        // ── 语义色 ────────────────────────────────────────────
        static let success       = SwiftUI.Color(hex: "#00C896")
        static let warning       = SwiftUI.Color(hex: "#FFB800")
        static let error         = SwiftUI.Color(hex: "#FF4757")
        static let textPrimary   = SwiftUI.Color(hex: "#F0F4FF")
        static let textSecondary = SwiftUI.Color(hex: "#8892B0")
        static let textMuted     = SwiftUI.Color(hex: "#4A5568")
        static let border        = SwiftUI.Color.white.opacity(0.08)
        static let borderHighlight = SwiftUI.Color.white.opacity(0.18)

        // ── AI 品牌色 ──────────────────────────────────────────
        static let deepSeek      = SwiftUI.Color(hex: "#4FACFE")   // DeepSeek 蓝
        static let gemini        = SwiftUI.Color(hex: "#8E75E5")   // Gemini 紫
    }
}

// MARK: - Gradients

extension DS {
    enum Gradient {
        /// 导航栏渐变：深邃蓝 → 皇家紫
        static let navBar = LinearGradient(
            colors: [DS.Color.bgBase, DS.Color.bgCard],
            startPoint: .top, endPoint: .bottom
        )

        /// 发送按钮：Electric Cyan → Ocean Blue
        static let sendButton = LinearGradient(
            colors: [DS.Color.cyan, DS.Color.primary],
            startPoint: .leading, endPoint: .trailing
        )

        /// 整合按钮：Sunset Orange → Royal Purple
        static let mergeButton = LinearGradient(
            colors: [DS.Color.orange, DS.Color.purple],
            startPoint: .leading, endPoint: .trailing
        )

        /// DeepSeek 卡片顶边高光
        static let deepSeekAccent = LinearGradient(
            colors: [DS.Color.deepSeek, DS.Color.primary],
            startPoint: .leading, endPoint: .trailing
        )

        /// Gemini 卡片顶边高光
        static let geminiAccent = LinearGradient(
            colors: [DS.Color.gemini, DS.Color.purple],
            startPoint: .leading, endPoint: .trailing
        )

        /// 背景底纹：从 #121212 过渡到 #1E1E3A
        static let appBackground = LinearGradient(
            colors: [DS.Color.bgBase, DS.Color.bgCardElevated],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )

        /// 通用卡片光泽感（左上角高光）
        static let cardSheen = LinearGradient(
            colors: [
                SwiftUI.Color.white.opacity(0.06),
                SwiftUI.Color.white.opacity(0.01)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

// MARK: - Typography

extension DS {
    enum Font {
        static let displayLarge  = SwiftUI.Font.system(size: 28, weight: .bold,   design: .rounded)
        static let displayMedium = SwiftUI.Font.system(size: 22, weight: .bold,   design: .rounded)
        static let titleLarge    = SwiftUI.Font.system(size: 18, weight: .semibold, design: .rounded)
        static let titleMedium   = SwiftUI.Font.system(size: 15, weight: .semibold, design: .rounded)
        static let bodyLarge     = SwiftUI.Font.system(size: 15, weight: .regular, design: .default)
        static let bodyMedium    = SwiftUI.Font.system(size: 13, weight: .regular, design: .default)
        static let labelSmall    = SwiftUI.Font.system(size: 11, weight: .medium,  design: .rounded)
        static let mono          = SwiftUI.Font.system(size: 13, weight: .regular, design: .monospaced)
    }
}

// MARK: - Shadows

extension DS {
    enum Shadow {
        /// 卡片悬浮阴影（AI 回复卡片）
        static func card(color: SwiftUI.Color = .black) -> some ViewModifier {
            CardShadow(shadowColor: color.opacity(0.35), radius: 16, y: 8)
        }

        /// 按钮点击光晕
        static func button(color: SwiftUI.Color) -> some ViewModifier {
            CardShadow(shadowColor: color.opacity(0.4), radius: 12, y: 4)
        }

        /// 轻量内容阴影
        static func subtle() -> some ViewModifier {
            CardShadow(shadowColor: .black.opacity(0.2), radius: 6, y: 3)
        }
    }
}

private struct CardShadow: ViewModifier {
    let shadowColor: SwiftUI.Color
    let radius: CGFloat
    let y: CGFloat
    func body(content: Content) -> some View {
        content.shadow(color: shadowColor, radius: radius, x: 0, y: y)
    }
}

// MARK: - Corner Radius

extension DS {
    enum Radius {
        static let xs: CGFloat  = 6
        static let sm: CGFloat  = 10
        static let md: CGFloat  = 14
        static let lg: CGFloat  = 20
        static let xl: CGFloat  = 28
        static let pill: CGFloat = 999
    }
}

// MARK: - Spacing

extension DS {
    enum Space {
        static let xs: CGFloat  = 4
        static let sm: CGFloat  = 8
        static let md: CGFloat  = 16
        static let lg: CGFloat  = 24
        static let xl: CGFloat  = 32
        static let xxl: CGFloat = 48
    }
}

// MARK: - Reusable ViewModifiers

extension DS {
    /// 玻璃磨砂卡片修饰符（主卡片容器）
    struct GlassCard: ViewModifier {
        var cornerRadius: CGFloat = DS.Radius.md
        var borderColor: SwiftUI.Color = DS.Color.borderHighlight

        func body(content: Content) -> some View {
            content
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(DS.Color.bgCard)
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(DS.Gradient.cardSheen)
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 8)
        }
    }

    /// AI 回复悬浮卡片（带顶边彩色高光条）
    struct AIResponseCard: ViewModifier {
        var accentGradient: LinearGradient = DS.Gradient.deepSeekAccent
        var cornerRadius: CGFloat = DS.Radius.md

        func body(content: Content) -> some View {
            content
                .background(
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(DS.Color.bgCardElevated)
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(DS.Gradient.cardSheen)
                        // 顶边彩色高光条
                        VStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(accentGradient)
                                .frame(height: 3)
                                .padding(.horizontal, DS.Radius.sm)
                                .padding(.top, 1)
                            Spacer()
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(DS.Color.borderHighlight, lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        }
    }

    /// 主品牌渐变按钮
    struct GradientButton: ViewModifier {
        var gradient: LinearGradient = DS.Gradient.sendButton
        var shadowColor: SwiftUI.Color = DS.Color.cyan

        func body(content: Content) -> some View {
            content
                .background(
                    Capsule().fill(gradient)
                )
                .shadow(color: shadowColor.opacity(0.45), radius: 10, x: 0, y: 4)
        }
    }

    /// 输入框背景样式
    struct InputField: ViewModifier {
        func body(content: Content) -> some View {
            content
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .fill(DS.Color.bgInput)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.sm)
                                .strokeBorder(DS.Color.border, lineWidth: 1)
                        )
                )
        }
    }

    /// Tab Bar 图标徽章
    struct BadgeDot: ViewModifier {
        var color: SwiftUI.Color = DS.Color.cyan
        func body(content: Content) -> some View {
            content.overlay(alignment: .topTrailing) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .offset(x: 2, y: -2)
            }
        }
    }
}

// MARK: - View Extensions (Syntactic Sugar)

extension View {
    func glassCard(cornerRadius: CGFloat = DS.Radius.md,
                   border: Color = DS.Color.borderHighlight) -> some View {
        modifier(DS.GlassCard(cornerRadius: cornerRadius, borderColor: border))
    }

    func aiResponseCard(accent: LinearGradient = DS.Gradient.deepSeekAccent,
                        cornerRadius: CGFloat = DS.Radius.md) -> some View {
        modifier(DS.AIResponseCard(accentGradient: accent, cornerRadius: cornerRadius))
    }

    func gradientButton(gradient: LinearGradient = DS.Gradient.sendButton,
                        glow: Color = DS.Color.cyan) -> some View {
        modifier(DS.GradientButton(gradient: gradient, shadowColor: glow))
    }

    func inputFieldStyle() -> some View {
        modifier(DS.InputField())
    }

    func badgeDot(color: Color = DS.Color.cyan) -> some View {
        modifier(DS.BadgeDot(color: color))
    }
}

// MARK: - Hex Color Init

extension SwiftUI.Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red:   Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview Helper

#if DEBUG
struct DesignSystem_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            DS.Gradient.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: DS.Space.lg) {

                    // 玻璃卡片示例
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        Text("玻璃卡片")
                            .font(DS.Font.titleMedium)
                            .foregroundColor(DS.Color.textPrimary)
                        Text("GlassCard modifier — 用于主要内容容器")
                            .font(DS.Font.bodyMedium)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    .padding(DS.Space.md)
                    .glassCard()

                    // AI 回复卡片示例
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(DS.Color.deepSeek)
                            Text("DeepSeek 回复")
                                .font(DS.Font.titleMedium)
                                .foregroundColor(DS.Color.deepSeek)
                        }
                        Text("这是一段 AI 生成的回复内容，悬浮在背景之上呈现精致感。")
                            .font(DS.Font.bodyMedium)
                            .foregroundColor(DS.Color.textPrimary)
                    }
                    .padding(DS.Space.md)
                    .aiResponseCard(accent: DS.Gradient.deepSeekAccent)

                    // Gemini 卡片
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        HStack {
                            Image(systemName: "cpu")
                                .foregroundColor(DS.Color.gemini)
                            Text("Gemini 回复")
                                .font(DS.Font.titleMedium)
                                .foregroundColor(DS.Color.gemini)
                        }
                        Text("Gemini 对以上内容的整合与归纳分析。")
                            .font(DS.Font.bodyMedium)
                            .foregroundColor(DS.Color.textPrimary)
                    }
                    .padding(DS.Space.md)
                    .aiResponseCard(accent: DS.Gradient.geminiAccent)

                    // 按钮示例
                    HStack(spacing: DS.Space.md) {
                        Text("发送")
                            .font(DS.Font.titleMedium)
                            .foregroundColor(.white)
                            .padding(.horizontal, DS.Space.lg)
                            .padding(.vertical, DS.Space.sm)
                            .gradientButton(gradient: DS.Gradient.sendButton, glow: DS.Color.cyan)

                        Text("整合")
                            .font(DS.Font.titleMedium)
                            .foregroundColor(.white)
                            .padding(.horizontal, DS.Space.lg)
                            .padding(.vertical, DS.Space.sm)
                            .gradientButton(gradient: DS.Gradient.mergeButton, glow: DS.Color.orange)
                    }

                    // 颜色色板
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                        ForEach([
                            ("主蓝", DS.Color.primary),
                            ("皇紫", DS.Color.purple),
                            ("电青", DS.Color.cyan),
                            ("橙", DS.Color.orange),
                            ("成功", DS.Color.success),
                            ("警告", DS.Color.warning),
                            ("DeepSeek", DS.Color.deepSeek),
                            ("Gemini", DS.Color.gemini)
                        ], id: \.0) { name, color in
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(color)
                                    .frame(height: 36)
                                Text(name)
                                    .font(DS.Font.labelSmall)
                                    .foregroundColor(DS.Color.textSecondary)
                            }
                        }
                    }
                    .padding(DS.Space.md)
                    .glassCard()
                }
                .padding(DS.Space.md)
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
