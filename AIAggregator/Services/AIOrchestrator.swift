import Foundation
import Combine
import WebKit

@MainActor
final class AIOrchestrator: ObservableObject {
    @Published var deepSeekResponse: String = ""
    @Published var geminiResponse: String   = ""
    @Published var mergedResponse: String   = ""

    @Published var isDeepSeekLoading = false
    @Published var isGeminiLoading   = false
    @Published var isMerging         = false

    /// UI 可见诊断日志（最多保留 20 条）
    @Published var debugLog: String = ""

    /// 计算属性：只要两侧都有回复就显示整合按钮
    /// 用计算属性取代 View 里的 @State + onChange，避免时序竞争
    var canMerge: Bool { !deepSeekResponse.isEmpty && !geminiResponse.isEmpty }

    private let webVM = WebViewModel()
    private var cancellables = Set<AnyCancellable>()
    private var mergeTimeoutWork: DispatchWorkItem?
    private var sendTimeoutWork: DispatchWorkItem?

    var deepSeekWebView: WKWebView { webVM.deepSeekWebView }
    var geminiWebView:   WKWebView { webVM.geminiWebView }

    init() { bindWebVM() }

    // MARK: - Public

    func send(query: String) {
        deepSeekResponse  = ""
        geminiResponse    = ""
        mergedResponse    = ""
        isDeepSeekLoading = true
        isGeminiLoading   = true
        appendDebug("📤 发送: \(query.prefix(30))...")

        sendTimeoutWork?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            var stuck: [String] = []
            if self.isDeepSeekLoading { stuck.append("DeepSeek") }
            if self.isGeminiLoading   { stuck.append("Gemini") }
            if !stuck.isEmpty {
                self.appendDebug("⚠️ 15s超时无回复: \(stuck.joined(separator: "/"))")
            }
        }
        sendTimeoutWork = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)

        webVM.sendToDeepSeek(query: query)
        webVM.sendToGemini(query: query)
    }

    func merge() {
        guard canMerge else { return }
        isMerging = true
        mergedResponse = ""
        let script = JSBridge.buildMergeScript(deepSeekAnswer: deepSeekResponse, geminiAnswer: geminiResponse)
        webVM.geminiWebView.evaluateJavaScript(script) { _, error in
            if let error { print("[Orchestrator] merge 注入错误: \(error)") }
        }
        mergeTimeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isMerging else { return }
            self.appendDebug("⚠️ 整合120s超时，强制重置")
            self.isMerging = false
        }
        mergeTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: work)
    }

    // MARK: - 强制渲染
    // 无论之前有任何 send_failed / 错误状态，数据到达后调用此方法
    // 直接写入 @Published 属性并显式广播变更，确保 SwiftUI 更新

    func renderDeepSeekReply(_ reply: String) {
        guard !reply.isEmpty else { return }
        sendTimeoutWork?.cancel()
        deepSeekResponse  = reply
        isDeepSeekLoading = false
        objectWillChange.send()   // 显式通知 SwiftUI
        appendDebug("✅ DS回复渲染，长度=\(reply.count)")
    }

    func renderGeminiReply(_ reply: String) {
        guard !reply.isEmpty else { return }
        if isMerging {
            mergedResponse = reply
            isMerging      = false
            mergeTimeoutWork?.cancel()
            objectWillChange.send()
            appendDebug("✅ 整合回复渲染，长度=\(reply.count)")
        } else {
            sendTimeoutWork?.cancel()
            geminiResponse  = reply
            isGeminiLoading = false
            objectWillChange.send()
            appendDebug("✅ GM回复渲染，长度=\(reply.count)")
        }
    }

    func appendDebug(_ msg: String) {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        let entry = "[\(fmt.string(from: Date()))] \(msg)"
        print("[DiagLog] \(entry)")
        debugLog = debugLog.isEmpty ? entry : debugLog + "\n" + entry
        let lines = debugLog.components(separatedBy: "\n")
        if lines.count > 20 { debugLog = lines.suffix(20).joined(separator: "\n") }
    }

    // MARK: - Private

    private func bindWebVM() {
        webVM.$deepSeekReply
            .filter { !$0.isEmpty }
            .receive(on: RunLoop.main)
            .sink { [weak self] reply in
                self?.renderDeepSeekReply(reply)
            }
            .store(in: &cancellables)

        webVM.$geminiReply
            .filter { !$0.isEmpty }
            .receive(on: RunLoop.main)
            .sink { [weak self] reply in
                self?.renderGeminiReply(reply)
            }
            .store(in: &cancellables)

        webVM.$debugEntry
            .filter { !$0.isEmpty }
            .receive(on: RunLoop.main)
            .sink { [weak self] entry in
                guard let self else { return }
                debugLog = debugLog.isEmpty ? entry : debugLog + "\n" + entry
                let lines = debugLog.components(separatedBy: "\n")
                if lines.count > 20 { debugLog = lines.suffix(20).joined(separator: "\n") }
            }
            .store(in: &cancellables)
    }
}
