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

    @Published var debugLog: String = ""

    var canMerge: Bool { !deepSeekResponse.isEmpty && !geminiResponse.isEmpty }

    private let webVM = WebViewModel()
    private var cancellables = Set<AnyCancellable>()
    private var mergeTimeoutWork: DispatchWorkItem?
    private var sendTimeoutWork: DispatchWorkItem?

    // 回复稳定性缓冲（内容 2s 不再增长则视为完成）
    private var dsStabilizeWork: DispatchWorkItem?
    private var gmStabilizeWork: DispatchWorkItem?
    private var lastDSLength = 0
    private var lastGMLength = 0

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
        lastDSLength      = 0
        lastGMLength      = 0
        dsStabilizeWork?.cancel()
        gmStabilizeWork?.cancel()
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

    // MARK: - 强制渲染（带 2s 稳定缓冲）

    func renderDeepSeekReply(_ reply: String) {
        guard !reply.isEmpty else { return }
        sendTimeoutWork?.cancel()
        deepSeekResponse = reply
        objectWillChange.send()
        appendDebug("📥 DS回复到达，长度=\(reply.count)，等待稳定...")
        scheduleStabilize(for: .deepSeek, length: reply.count)
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
            geminiResponse = reply
            objectWillChange.send()
            appendDebug("📥 GM回复到达，长度=\(reply.count)，等待稳定...")
            scheduleStabilize(for: .gemini, length: reply.count)
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

    // MARK: - 稳定缓冲（2s内容不再增长则标记完成）

    private enum ReplySource { case deepSeek, gemini }

    private func scheduleStabilize(for source: ReplySource, length: Int) {
        switch source {
        case .deepSeek:
            dsStabilizeWork?.cancel()
            lastDSLength = length
            let work = DispatchWorkItem { [weak self] in self?.checkStability(source: .deepSeek) }
            dsStabilizeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
        case .gemini:
            gmStabilizeWork?.cancel()
            lastGMLength = length
            let work = DispatchWorkItem { [weak self] in self?.checkStability(source: .gemini) }
            gmStabilizeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
        }
    }

    private func checkStability(source: ReplySource) {
        switch source {
        case .deepSeek:
            let current = deepSeekResponse.count
            if current == lastDSLength {
                isDeepSeekLoading = false
                objectWillChange.send()
                appendDebug("✅ DS回复稳定，长度=\(current)")
                tryAutoMerge()
            } else {
                scheduleStabilize(for: .deepSeek, length: current)
            }
        case .gemini:
            let current = geminiResponse.count
            if current == lastGMLength {
                isGeminiLoading = false
                objectWillChange.send()
                appendDebug("✅ GM回复稳定，长度=\(current)")
                tryAutoMerge()
            } else {
                scheduleStabilize(for: .gemini, length: current)
            }
        }
    }

    // 双端均稳定后自动整合
    private func tryAutoMerge() {
        guard !isDeepSeekLoading, !isGeminiLoading,
              canMerge, !isMerging, mergedResponse.isEmpty else { return }
        appendDebug("🔀 双端稳定，自动触发整合")
        merge()
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
