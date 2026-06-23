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
    private var hasAnyContent: Bool {
        !orchestrator.deepSeekResponse.isEmpty || !orchestrator.geminiResponse.isEmpty ||
        orchestrator.isDeepSeekLoading || orchestrator.isGeminiLoading
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Gradient.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    WorkbenchNavBar(showDebugLog: $showDebugLog,
                                    isReady: orchestrator.deepSeekIsReady || orchestrator.geminiIsReady)

                    ScrollView {
                        VStack(spacing: DS.Space.md) {

                            if !hasAnyContent {
                                EmptyStateView()
                                    .transition(.opacity.combined(with: .scale))
                            }

                            // ── 分屏区域：DS + GM 左右并排 ──────────────────────
                            if hasAnyContent {
                                SplitResponseArea(
                                    orchestrator: orchestrator,
                                    isDSExpanded: $isDSExpanded,
                                    isGMExpanded: $isGMExpanded
                                )
                                .transition(.opacity)
                            }

                            // ── 整合结论（全宽）──────────────────────────────────
                            if !orchestrator.mergedResponse.isEmpty {
                                MergedResponseCard(content: orchestrator.mergedResponse)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }

                            // ── 整合进行中指示 ──────────────────────────────────
                            if orchestrator.isMerging {
                                MergingIndicatorView()
                                    .transition(.opacity)
                            }

                            Color.clear.frame(height: DS.Space.lg)
                        }
                        .padding(DS.Space.md)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8),
                                   value: orchestrator.deepSeekResponse.count)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8),
                                   value: orchestrator.geminiResponse.count)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8),
                                   value: orchestrator.mergedResponse.isEmpty)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8),
                                   value: orchestrator.isMerging)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
                }

                // ── 悬浮调试日志层 ──────────────────────────────────────────────
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

    // MARK: - Bottom Bar（仅输入栏，无手动整合按钮）

    @ViewBuilder
    private var bottomBar: some View {
        InputBar(
            text: $inputText,
            isFocused: $isInputFocused,
            isSending: isSending
        ) {
            sendQuery()
        }
        .padding(.bottom, isInputFocused ? 0 : 80)
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

// MARK: - Split Response Area（分屏：左右并排）

private struct SplitResponseArea: View {
    @ObservedObject var orchestrator: AIOrchestrator
    @Binding var isDSExpanded: Bool
    @Binding var isGMExpanded: Bool

    private var showDS: Bool {
        !orchestrator.deepSeekResponse.isEmpty || orchestrator.isDeepSeekLoading
    }
    private var showGM: Bool {
        !orchestrator.geminiResponse.isEmpty || orchestrator.isGeminiLoading
    }

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .top, spacing: DS.Space.sm) {
                if showDS {
                    AIResponseCardView(
                        title: "DeepSeek",
                        icon: "sparkles",
                        gradient: DS.Gradient.deepSeekAccent,
                        accentColor: DS.Color.deepSeek,
                        content: orchestrator.deepSeekResponse,
                        isLoading: orchestrator.isDeepSeekLoading,
                        isExpanded: $isDSExpanded
                    )
                    .frame(maxWidth: showGM ? (geo.size.width - DS.Space.sm) / 2 : .infinity)
                }
                if showGM {
                    AIResponseCardView(
                        title: "Gemini",
                        icon: "cpu",
                        gradient: DS.Gradient.geminiAccent,
                        accentColor: DS.Color.gemini,
                        content: orchestrator.geminiResponse,
                        isLoading: orchestrator.isGeminiLoading,
                        isExpanded: $isGMExpanded
                    )
                    .frame(maxWidth: showDS ? (geo.size.width - DS.Space.sm) / 2 : .infinity)
                }
            }
        }
        .frame(height: cardHeight)
    }

    private var cardHeight: CGFloat {
        let dsExpanded = isDSExpanded && !orchestrator.deepSeekResponse.isEmpty
        let gmExpanded = isGMExpanded && !orchestrator.geminiResponse.isEmpty
        if dsExpanded || gmExpanded { return 320 }
        return 100
    }
}

// MARK: - Nav Bar

private struct WorkbenchNavBar: View {
    @Binding var showDebugLog: Bool
    let isReady: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI 工作台")
                    .font(DS.Font.displayMedium)
                    .foregroundStyle(
                        LinearGradient(colors: [DS.Color.cyan, DS.Color.primaryLight],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                HStack(spacing: 4) {
                    Circle()
                        .fill(isReady ? DS.Color.success : DS.Color.warning)
                        .frame(width: 5, height: 5)
                        .shadow(color: (isReady ? DS.Color.success : DS.Color.warning).opacity(0.8), radius: 3)
                    Text(isReady ? "双引擎就绪" : "连接中…")
                        .font(DS.Font.labelSmall)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }
            Spacer()
            Button {
                withAnimation { showDebugLog.toggle() }
            } label: {
                Image(systemName: showDebugLog ? "ladybug.fill" : "ladybug")
                    .font(.system(size: 18))
                    .foregroundColor(showDebugLog ? .orange : DS.Color.textMuted)
                    .padding(6)
                    .background(Circle().fill(showDebugLog
                        ? Color.orange.opacity(0.15)
                        : Color.white.opacity(0.05)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.md)
        .background(DS.Gradient.navBar.ignoresSafeArea(edges: .top))
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
                Image(systemName: "ladybug.fill").font(.system(size: 12)).foregroundColor(.orange)
                Text("诊断日志")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.orange)
                Spacer()
                Button(action: onClear) {
                    Text("清除")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 8).padding(.vertical, 3)
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
                Text("暂无日志").font(.system(size: 10, design: .monospaced)).foregroundColor(.gray)
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
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.orange.opacity(0.55), lineWidth: 1))
        )
        .shadow(color: Color.orange.opacity(0.2), radius: 16, x: 0, y: 6)
        .padding(.horizontal, DS.Space.md)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Empty State

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: DS.Space.md) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(
                    LinearGradient(colors: [DS.Color.cyan, DS.Color.purple],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Text("输入问题，双引擎同步思考")
                .font(DS.Font.titleMedium)
                .foregroundColor(DS.Color.textSecondary)
            Text("DeepSeek 与 Gemini 并行回复\n稳定后自动整合为深度总结")
                .font(DS.Font.bodyMedium)
                .foregroundColor(DS.Color.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(DS.Space.xxl)
        .frame(maxWidth: .infinity)
        .glassCard()
    }
}

// MARK: - AI Response Card（可折叠，分屏内使用）

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
            // 标题行（始终可见）
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accentColor)
                    Text(title)
                        .font(DS.Font.labelSmall)
                        .foregroundColor(accentColor)
                    Spacer()
                    if isLoading {
                        ProgressView().tint(accentColor).scaleEffect(0.7)
                    } else if !content.isEmpty {
                        Text("\(content.count)字")
                            .font(.system(size: 9))
                            .foregroundColor(accentColor.opacity(0.55))
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.Color.textMuted)
                }
                .padding(.horizontal, DS.Space.sm)
                .padding(.vertical, DS.Space.sm)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().background(accentColor.opacity(0.2))

                if isLoading && content.isEmpty {
                    TypingIndicator(color: accentColor)
                        .padding(DS.Space.sm)
                } else {
                    // 内部可滚动，防止分屏时无限高
                    ScrollView {
                        Text(content)
                            .font(DS.Font.bodyMedium)
                            .foregroundColor(DS.Color.textPrimary)
                            .textSelection(.enabled)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DS.Space.sm)
                    }

                    // 复制按钮
                    HStack {
                        Spacer()
                        Button {
                            UIPasteboard.general.string = content
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundColor(DS.Color.textMuted)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, DS.Space.sm)
                        .padding(.bottom, DS.Space.xs)
                    }
                }
            }
        }
        .aiResponseCard(accent: gradient)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Merged Response Card

private struct MergedResponseCard: View {
    let content: String
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "arrow.triangle.merge").foregroundStyle(DS.Gradient.mergeButton)
                Text("深度整合结论")
                    .font(DS.Font.titleMedium)
                    .foregroundStyle(DS.Gradient.mergeButton)
                Spacer()
                Image(systemName: "checkmark.seal.fill").foregroundColor(DS.Color.success)
                Button { UIPasteboard.general.string = content } label: {
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

// MARK: - Merging Indicator

private struct MergingIndicatorView: View {
    var body: some View {
        HStack(spacing: DS.Space.sm) {
            ProgressView().tint(DS.Color.orange).scaleEffect(0.85)
            Text("正在生成深度整合总结（≥300字）…")
                .font(DS.Font.bodyMedium)
                .foregroundColor(DS.Color.textSecondary)
            Spacer()
        }
        .padding(DS.Space.md)
        .glassCard()
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
                    .frame(width: 6, height: 6)
                    .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15),
                               value: phase)
            }
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                phase = (phase + 1) % 3
            }
        }
        .onDisappear { timer?.invalidate(); timer = nil }
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
            Button { showCompose = true } label: {
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
    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Gradient.appBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack(spacing: DS.Space.lg) {
                        HStack(spacing: 2) {
                            Text("\(charCount)").font(DS.Font.titleMedium).foregroundStyle(DS.Gradient.sendButton)
                            Text("字").font(DS.Font.labelSmall).foregroundColor(DS.Color.textSecondary)
                        }
                        Spacer()
                        if !isEmpty {
                            Button { withAnimation { text = "" } } label: {
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
                }
            }
            .navigationTitle("撰写 & 审阅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DS.Color.bgCard, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.foregroundColor(DS.Color.textSecondary)
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
                        .foregroundStyle(isEmpty
                            ? AnyShapeStyle(DS.Color.textMuted)
                            : AnyShapeStyle(DS.Gradient.sendButton))
                    }
                    .disabled(isEmpty)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { editorFocused = true }
        }
    }
}
