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

    /// UI 可见诊断日志（最多保留 20 条，显示在 WorkbenchView debugLabel）
    @Published var debugLog: String = ""

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

        // 15s 超时：如果没有任何回复到达，在 debugLog 显示错误
        sendTimeoutWork?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            var stuck: [String] = []
            if self.isDeepSeekLoading { stuck.append("DeepSeek") }
            if self.isGeminiLoading   { stuck.append("Gemini") }
            if !stuck.isEmpty {
                self.appendDebug("⚠️ 15s超时无回复: \(stuck.joined(separator: "/"))。检查JS注入是否成功、按钮是否可点")
            }
        }
        sendTimeoutWork = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)

        webVM.sendToDeepSeek(query: query)
        webVM.sendToGemini(query: query)
    }

    func merge() {
        guard !deepSeekResponse.isEmpty, !geminiResponse.isEmpty else { return }
        isMerging = true
        mergedResponse = ""

        let script = JSBridge.buildMergeScript(
            deepSeekAnswer: deepSeekResponse,
            geminiAnswer: geminiResponse
        )

        webVM.geminiWebView.evaluateJavaScript(script) { _, error in
            if let error { print("[Orchestrator] merge 注入错误: \(error)") }
        }

        mergeTimeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isMerging else { return }
            print("[Orchestrator] merge 120s 超时，强制重置")
            self.appendDebug("⚠️ 整合120s超时，强制重置")
            self.isMerging = false
        }
        mergeTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: work)
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
        // deepSeekReply 到达 → 更新 deepSeekResponse，清除加载态
        webVM.$deepSeekReply
            .filter { !$0.isEmpty }
            .receive(on: RunLoop.main)
            .sink { [weak self] reply in
                guard let self else { return }
                print("[Orchestrator] ✅ DeepSeek 回复到达，长度=\(reply.count)")
                self.sendTimeoutWork?.cancel()
                self.deepSeekResponse  = reply
                self.isDeepSeekLoading = false
                self.appendDebug("✅ DS回复到达，长度=\(reply.count)")
            }
            .store(in: &cancellables)

        // geminiReply 到达 → 普通回复 or 整合回复，取决于 isMerging
        webVM.$geminiReply
            .filter { !$0.isEmpty }
            .receive(on: RunLoop.main)
            .sink { [weak self] reply in
                guard let self else { return }
                if self.isMerging {
                    print("[Orchestrator] ✅ 整合回复到达，长度=\(reply.count)")
                    self.mergedResponse = reply
                    self.isMerging      = false
                    self.mergeTimeoutWork?.cancel()
                    self.appendDebug("✅ 整合回复到达，长度=\(reply.count)")
                } else {
                    print("[Orchestrator] ✅ Gemini 回复到达，长度=\(reply.count)")
                    self.sendTimeoutWork?.cancel()
                    self.geminiResponse  = reply
                    self.isGeminiLoading = false
                    self.appendDebug("✅ GM回复到达，长度=\(reply.count)")
                }
            }
            .store(in: &cancellables)

        // JS 层诊断事件 → 聚合到 debugLog
        webVM.$debugEntry
            .filter { !$0.isEmpty }
            .receive(on: RunLoop.main)
            .sink { [weak self] entry in
                guard let self else { return }
                self.debugLog = self.debugLog.isEmpty ? entry : self.debugLog + "\n" + entry
                let lines = self.debugLog.components(separatedBy: "\n")
                if lines.count > 20 { self.debugLog = lines.suffix(20).joined(separator: "\n") }
            }
            .store(in: &cancellables)
    }
}
