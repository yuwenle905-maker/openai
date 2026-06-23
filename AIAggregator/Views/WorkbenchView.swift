import SwiftUI
import UIKit

struct WorkbenchView: View {
    @EnvironmentObject private var orchestrator: AIOrchestrator
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var showDebugLog = false
    @State private var isDSExpanded = false
    @State private var isGMExpanded = false

    private var isSending: Bool {
        orchestrator.isDeepSeekLoading || orchestrator.isGeminiLoading
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Gradient.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    WorkbenchNavBar(showDebugLog: $showDebugLog)

                    // ── 回复内容区 ─────────────────────────────────────────────
                    ScrollView {
                        VStack(spacing: DS.Space.md) {
                            if orchestrator.deepSeekResponse.isEmpty && orchestrator.geminiResponse.isEmpty {
                                EmptyStateView()
                                    .transition(.opacity.combined(with: .scale))
                            }

                            if !orchestrator.deepSeekResponse.isEmpty || orchestrator.isDeepSeekLoading {
                                AIResponseCardView(
                                    title: "DeepSeek",
                                    icon: "sparkles",
                                    gradient: DS.Gradient.deepSeekAccent,
                                    accentColor: DS.Color.deepSeek,
                                    content: orchestrator.deepSeekResponse,
                                    isLoading: orchestrator.isDeepSeekLoading,
                                    isExpanded: $isDSExpanded
                                )
                                .transition(.move(edge: .leading).combined(with: .opacity))
                            }

                            if !orchestrator.geminiResponse.isEmpty || orchestrator.isGeminiLoading {
                                AIResponseCardView(
                                    title: "Gemini",
                                    icon: "cpu",
                                    gradient: DS.Gradient.geminiAccent,
                                    accentColor: DS.Color.gemini,
                                    content: orchestrator.geminiResponse,
                                    isLoading: orchestrator.isGeminiLoading,
                                    isExpanded: $isGMExpanded
                                )
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                            }

                            if !orchestrator.mergedResponse.isEmpty {
                                MergedResponseCard(content: orchestrator.mergedResponse)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }

                            Color.clear.frame(height: DS.Space.lg)
                        }
                        .padding(DS.Space.md)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: orchestrator.deepSeekResponse)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: orchestrator.geminiResponse)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: orchestrator.mergedResponse)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        bottomBar
                    }
                }

                // ── 悬浮调试日志层 ────────────────────────────────────────────
                if showDebugLog {
                    DebugFloatingOverlay(
                        log: orchestrator.debugLog,
                        onClear: { orchestrator.debugLog = "" },
                        onClose: { withAnimation { showDebugLog = false } }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showDebugLog)
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 0) {
            if orchestrator.canMerge && !orchestrator.isMerging && orchestrator.mergedResponse.isEmpty {
                MergeButtonRow(isMerging: orchestrator.isMerging) {
                    orchestrator.merge()
                }
                .padding(.horizontal, DS.Space.md)
                .padding(.top, DS.Space.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            InputBar(
                text: $inputText,
                isFocused: $isInputFocused,
                isSending: isSending
            ) {
                sendQuery()
            }
            .padding(.bottom, isInputFocused ? 0 : 80)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: orchestrator.canMerge)
        .animation(.easeOut(duration: 0.25), value: isInputFocused)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                Rectangle().fill(DS.Color.bgCard.opacity(0.85))
                Rectangle()
                    .fill(DS.Color.borderHighlight)
                    .frame(height: 0.5)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Send Action

    private func sendQuery() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isInputFocused = false
        inputText = ""
        isDSExpanded = false
        isGMExpanded = false
        orchestrator.send(query: trimmed)
    }
}

// MARK: - Nav Bar

private struct WorkbenchNavBar: View {
    @Binding var showDebugLog: Bool

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
            HStack(spacing: 10) {
                StatusDot(color: DS.Color.deepSeek, label: "DS")
                StatusDot(color: DS.Color.gemini, label: "GM")

                // 调试日志开关
                Button {
                    withAnimation { showDebugLog.toggle() }
                } label: {
                    Image(systemName: showDebugLog ? "ladybug.fill" : "ladybug")
                        .font(.system(size: 18))
                        .foregroundColor(showDebugLog ? .orange : DS.Color.textMuted)
                        .padding(6)
                        .background(
                            Circle().fill(showDebugLog
                                ? Color.orange.opacity(0.15)
                                : Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
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

// MARK: - Debug Floating Overlay

private struct DebugFloatingOverlay: View {
    let log: String
    let onClear: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                Text("诊断日志")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.orange)
                Spacer()
                Button(action: onClear) {
                    Text("清除")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color.gray.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            if log.isEmpty {
                Text("暂无日志")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray)
            } else {
                ScrollView {
                    Text(log)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.orange.opacity(0.55), lineWidth: 1)
                )
        )
        .shadow(color: Color.orange.opacity(0.2), radius: 16, x: 0, y: 6)
        .padding(.horizontal, DS.Space.md)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(true)
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

// MARK: - AI Response Card（可折叠）

private struct AIResponseCardView: View {
    let title: String
    let icon: String
    let gradient: LinearGradient
    let accentColor: Color
    let content: String
    let isLoading: Bool
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题行（始终可见，点击折叠/展开）
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: icon).foregroundColor(accentColor)
                    Text(title)
                        .font(DS.Font.titleMedium)
                        .foregroundColor(accentColor)
                    if isLoading {
                        ProgressView().tint(accentColor).scaleEffect(0.8)
                    }
                    Spacer()
                    if !content.isEmpty {
                        // 字数统计小标签
                        Text("\(content.count) 字")
                            .font(.system(size: 10))
                            .foregroundColor(accentColor.opacity(0.6))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(accentColor.opacity(0.08)))

                        Button {
                            UIPasteboard.general.string = content
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12))
                                .foregroundColor(DS.Color.textMuted)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture())
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Color.textMuted)
                }
                .padding(DS.Space.md)
            }
            .buttonStyle(.plain)

            // 展开内容
            if isExpanded {
                Divider()
                    .background(accentColor.opacity(0.2))
                    .padding(.horizontal, DS.Space.md)

                if isLoading && content.isEmpty {
                    TypingIndicator(color: accentColor)
                        .padding(DS.Space.md)
                } else {
                    Text(content)
                        .font(DS.Font.bodyMedium)
                        .foregroundColor(DS.Color.textPrimary)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                        .padding(DS.Space.md)
                        .padding(.top, 2)
                }
            }
        }
        .aiResponseCard(accent: gradient)
    }
}

// MARK: - Merged Response Card（始终展开，主要结果）

private struct MergedResponseCard: View {
    let content: String
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "arrow.triangle.merge").foregroundStyle(DS.Gradient.mergeButton)
                Text("整合结论")
                    .font(DS.Font.titleMedium)
                    .foregroundStyle(DS.Gradient.mergeButton)
                Spacer()
                Image(systemName: "checkmark.seal.fill").foregroundColor(DS.Color.success)
                Button {
                    UIPasteboard.general.string = content
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(DS.Color.textMuted)
                }
                .buttonStyle(.plain)
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
    @State private var timer: Timer?

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
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                phase = (phase + 1) % 3
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
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

    @State private var showCompose = false

    var body: some View {
        HStack(alignment: .bottom, spacing: DS.Space.sm) {
            Button {
                showCompose = true
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Group {
                        if text.isEmpty {
                            Text("点此处输入，全屏撰写与审阅...")
                                .foregroundColor(DS.Color.textMuted)
                        } else {
                            Text(text)
                                .foregroundColor(DS.Color.textPrimary)
                                .lineLimit(2)
                        }
                    }
                    .font(DS.Font.bodyLarge)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !text.isEmpty {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(DS.Color.cyan.opacity(0.7))
                    }
                }
                .padding(.horizontal, DS.Space.sm)
                .padding(.vertical, 12)
                .inputFieldStyle()
            }
            .buttonStyle(.plain)

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
                .background(Circle().fill(DS.Gradient.sendButton))
                .shadow(color: DS.Color.cyan.opacity(0.5), radius: 8, x: 0, y: 3)
            }
            .disabled(isSending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .buttonStyle(.plain)
            .scaleEffect(isSending ? 0.92 : 1.0)
            .animation(.spring(response: 0.2), value: isSending)
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .sheet(isPresented: $showCompose) {
            ComposeSheet(text: $text) {
                showCompose = false
                onSend()
            }
        }
    }
}

// MARK: - Compose Sheet

private struct ComposeSheet: View {
    @Binding var text: String
    let onSend: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var editorFocused: Bool

    private var charCount: Int { text.count }
    private var wordCount: Int {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
    }
    private var lineCount: Int {
        max(1, text.components(separatedBy: "\n").count)
    }
    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Gradient.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(spacing: DS.Space.lg) {
                        StatBadge(value: charCount, label: "字")
                        StatBadge(value: wordCount, label: "词")
                        StatBadge(value: lineCount, label: "行")
                        Spacer()
                        if !isEmpty {
                            Button {
                                withAnimation { text = "" }
                            } label: {
                                Label("清空", systemImage: "xmark.circle.fill")
                                    .font(DS.Font.labelSmall)
                                    .foregroundColor(DS.Color.error.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, DS.Space.md)
                    .padding(.vertical, DS.Space.sm)
                    .background(DS.Color.bgCard.opacity(0.6))

                    Divider().background(DS.Color.border)

                    ScrollView {
                        TextEditor(text: $text)
                            .font(DS.Font.bodyLarge)
                            .foregroundColor(DS.Color.textPrimary)
                            .tint(DS.Color.cyan)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .focused($editorFocused)
                            .frame(minHeight: 300)
                            .padding(DS.Space.md)
                    }
                    .scrollDismissesKeyboard(.interactively)

                    HStack {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundColor(DS.Color.textMuted)
                        Text("在此处检查错别字，确认无误后点击「发送」")
                            .font(DS.Font.labelSmall)
                            .foregroundColor(DS.Color.textMuted)
                        Spacer()
                    }
                    .padding(.horizontal, DS.Space.md)
                    .padding(.vertical, DS.Space.sm)
                    .background(DS.Color.bgCard.opacity(0.4))
                }
            }
            .navigationTitle("撰写 & 审阅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DS.Color.bgCard, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundColor(DS.Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard !isEmpty else { return }
                        onSend()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "paperplane.fill")
                            Text("发送")
                        }
                        .font(DS.Font.titleMedium)
                        .foregroundStyle(
                            isEmpty
                                ? AnyShapeStyle(DS.Color.textMuted)
                                : AnyShapeStyle(DS.Gradient.sendButton)
                        )
                    }
                    .disabled(isEmpty)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                editorFocused = true
            }
        }
    }
}

// MARK: - Stat Badge

private struct StatBadge: View {
    let value: Int
    let label: String
    var body: some View {
        HStack(spacing: 2) {
            Text("\(value)")
                .font(DS.Font.titleMedium)
                .foregroundStyle(DS.Gradient.sendButton)
            Text(label)
                .font(DS.Font.labelSmall)
                .foregroundColor(DS.Color.textSecondary)
        }
    }
}
