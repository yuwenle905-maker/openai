import SwiftUI

struct WorkbenchView: View {
    @EnvironmentObject private var orchestrator: AIOrchestrator
    @State private var inputText = ""
    @State private var isSending = false
    @State private var showMergeButton = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Gradient.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── 导航栏 ──────────────────────────────
                    WorkbenchNavBar()

                    // ── 回复卡片区域 ──────────────────────────
                    ScrollView {
                        VStack(spacing: DS.Space.md) {
                            // 状态提示
                            if orchestrator.deepSeekResponse.isEmpty && orchestrator.geminiResponse.isEmpty {
                                EmptyStateView()
                                    .transition(.opacity.combined(with: .scale))
                            }

                            // DeepSeek 回复
                            if !orchestrator.deepSeekResponse.isEmpty || orchestrator.isDeepSeekLoading {
                                AIResponseCardView(
                                    title: "DeepSeek",
                                    icon: "sparkles",
                                    gradient: DS.Gradient.deepSeekAccent,
                                    accentColor: DS.Color.deepSeek,
                                    content: orchestrator.deepSeekResponse,
                                    isLoading: orchestrator.isDeepSeekLoading
                                )
                                .transition(.move(edge: .leading).combined(with: .opacity))
                            }

                            // Gemini 回复
                            if !orchestrator.geminiResponse.isEmpty || orchestrator.isGeminiLoading {
                                AIResponseCardView(
                                    title: "Gemini",
                                    icon: "cpu",
                                    gradient: DS.Gradient.geminiAccent,
                                    accentColor: DS.Color.gemini,
                                    content: orchestrator.geminiResponse,
                                    isLoading: orchestrator.isGeminiLoading
                                )
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                            }

                            // 整合结果
                            if !orchestrator.mergedResponse.isEmpty {
                                MergedResponseCard(content: orchestrator.mergedResponse)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }

                            // 底部留白（避免被 Tab Bar 遮挡）
                            Spacer().frame(height: 100)
                        }
                        .padding(DS.Space.md)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: orchestrator.deepSeekResponse)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: orchestrator.geminiResponse)
                    }

                    // ── 整合按钮 ──────────────────────────────
                    if showMergeButton {
                        MergeButtonRow(isMerging: orchestrator.isMerging) {
                            Task { await orchestrator.merge() }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.horizontal, DS.Space.md)
                        .padding(.bottom, DS.Space.sm)
                    }

                    // ── 输入区域 ──────────────────────────────
                    InputBar(
                        text: $inputText,
                        isFocused: $isInputFocused,
                        isSending: isSending
                    ) {
                        Task { await sendQuery() }
                    }
                    .padding(.bottom, 80) // Tab Bar 高度
                }
            }
        }
        .onChange(of: orchestrator.deepSeekResponse) { _, new in
            showMergeButton = !new.isEmpty && !orchestrator.geminiResponse.isEmpty
        }
        .onChange(of: orchestrator.geminiResponse) { _, new in
            showMergeButton = !orchestrator.deepSeekResponse.isEmpty && !new.isEmpty
        }
    }

    private func sendQuery() async {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isInputFocused = false
        isSending = true
        await orchestrator.send(query: inputText)
        isSending = false
        inputText = ""
    }
}

// MARK: - Nav Bar

private struct WorkbenchNavBar: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI 工作台")
                    .font(DS.Font.displayMedium)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [DS.Color.cyan, DS.Color.primaryLight],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                Text("DeepSeek · Gemini 双引擎")
                    .font(DS.Font.labelSmall)
                    .foregroundColor(DS.Color.textSecondary)
            }
            Spacer()
            // 状态指示灯
            HStack(spacing: 6) {
                StatusDot(color: DS.Color.deepSeek, label: "DS")
                StatusDot(color: DS.Color.gemini, label: "GM")
            }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.md)
        .background(DS.Gradient.navBar.ignoresSafeArea(edges: .top))
    }
}

private struct StatusDot: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.8), radius: 3)
            Text(label)
                .font(DS.Font.labelSmall)
                .foregroundColor(DS.Color.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(color.opacity(0.12))
                .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.8))
        )
    }
}

// MARK: - Empty State

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: DS.Space.md) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [DS.Color.cyan, DS.Color.purple],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            Text("输入问题，双引擎同步思考")
                .font(DS.Font.titleMedium)
                .foregroundColor(DS.Color.textSecondary)
            Text("DeepSeek 与 Gemini 将并行回复\n再由 Gemini 整合精华")
                .font(DS.Font.bodyMedium)
                .foregroundColor(DS.Color.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(DS.Space.xxl)
        .frame(maxWidth: .infinity)
        .glassCard()
    }
}

// MARK: - AI Response Card

private struct AIResponseCardView: View {
    let title: String
    let icon: String
    let gradient: LinearGradient
    let accentColor: Color
    let content: String
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            // 标题行
            HStack(spacing: DS.Space.sm) {
                Image(systemName: icon)
                    .foregroundColor(accentColor)
                Text(title)
                    .font(DS.Font.titleMedium)
                    .foregroundColor(accentColor)
                Spacer()
                if isLoading {
                    ProgressView()
                        .tint(accentColor)
                        .scaleEffect(0.8)
                }
                // 复制按钮
                if !content.isEmpty {
                    Button {
                        UIPasteboard.general.string = content
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundColor(DS.Color.textMuted)
                    }
                }
            }

            Divider().background(accentColor.opacity(0.2))

            // 内容
            if isLoading && content.isEmpty {
                TypingIndicator(color: accentColor)
            } else {
                Text(content)
                    .font(DS.Font.bodyMedium)
                    .foregroundColor(DS.Color.textPrimary)
                    .textSelection(.enabled)
                    .lineSpacing(4)
            }
        }
        .padding(DS.Space.md)
        .aiResponseCard(accent: gradient)
    }
}

// MARK: - Merged Response Card

private struct MergedResponseCard: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "arrow.triangle.merge")
                    .foregroundStyle(DS.Gradient.mergeButton)
                Text("整合结论")
                    .font(DS.Font.titleMedium)
                    .foregroundStyle(DS.Gradient.mergeButton)
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(DS.Color.success)
            }
            Divider().background(DS.Color.orange.opacity(0.3))
            Text(content)
                .font(DS.Font.bodyMedium)
                .foregroundColor(DS.Color.textPrimary)
                .textSelection(.enabled)
                .lineSpacing(4)
        }
        .padding(DS.Space.md)
        .aiResponseCard(accent: DS.Gradient.mergeButton)
    }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
    let color: Color
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color.opacity(phase == i ? 1 : 0.3))
                    .frame(width: 7, height: 7)
                    .animation(
                        .easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15),
                        value: phase
                    )
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                phase = (phase + 1) % 3
            }
        }
    }
}

// MARK: - Merge Button

private struct MergeButtonRow: View {
    let isMerging: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.sm) {
                if isMerging {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.triangle.merge")
                }
                Text(isMerging ? "整合中..." : "整合双端回复")
                    .font(DS.Font.titleMedium)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .gradientButton(gradient: DS.Gradient.mergeButton, glow: DS.Color.orange)
        }
        .disabled(isMerging)
        .buttonStyle(.plain)
    }
}

// MARK: - Input Bar

private struct InputBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let isSending: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            TextField("向双引擎提问...", text: $text, axis: .vertical)
                .font(DS.Font.bodyLarge)
                .foregroundColor(DS.Color.textPrimary)
                .tint(DS.Color.cyan)
                .lineLimit(1...5)
                .focused(isFocused)
                .padding(DS.Space.sm)
                .inputFieldStyle()

            // 发送按钮
            Button(action: onSend) {
                ZStack {
                    if isSending {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(DS.Gradient.sendButton)
                )
                .shadow(color: DS.Color.cyan.opacity(0.5), radius: 8, x: 0, y: 3)
            }
            .disabled(isSending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .buttonStyle(.plain)
            .scaleEffect(isSending ? 0.92 : 1.0)
            .animation(.spring(response: 0.2), value: isSending)
        }
        .padding(DS.Space.md)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                Rectangle().fill(DS.Color.bgCard.opacity(0.85))
                Rectangle().fill(DS.Color.borderHighlight).frame(height: 0.5).frame(maxHeight: .infinity, alignment: .top)
            }
        )
    }
}
