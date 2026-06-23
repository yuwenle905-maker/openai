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

    // 3s 监听窗口 + 2s 稳定判定
    private var dsWindowWork: DispatchWorkItem?   // 1s 初始缓冲
    private var dsStabilizeWork: DispatchWorkItem? // 2s 稳定检测
    private var gmWindowWork: DispatchWorkItem?
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
        cancelAllStabilize()
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
        isMerging      = true
        mergedResponse = ""
        objectWillChange.send()
        appendDebug("🔀 触发整合，注入 Gemini...")
        let script = JSBridge.buildMergeScript(deepSeekAnswer: deepSeekResponse, geminiAnswer: geminiResponse)
        webVM.geminiWebView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                self?.appendDebug("⚠️ merge 注入错误: \(error.localizedDescription)")
            }
        }
        mergeTimeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isMerging else { return }
            self.appendDebug("⚠️ 整合120s超时，强制重置")
            self.isMerging = false
            self.objectWillChange.send()
        }
        mergeTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: work)
    }

    // MARK: - 强制渲染（带 3s 缓冲窗口）

    func renderDeepSeekReply(_ reply: String) {
        guard !reply.isEmpty else { return }
        sendTimeoutWork?.cancel()
        deepSeekResponse = reply
        objectWillChange.send()
        appendDebug("📥 DS回复到达，长度=\(reply.count)，开启3s监听窗口...")
        scheduleWindow(for: .deepSeek, currentLength: reply.count)
    }

    func renderGeminiReply(_ reply: String) {
        guard !reply.isEmpty else { return }
        if isMerging {
            // 整合结果：直接写入，强制刷新 UI
            mergedResponse = reply
            isMerging      = false
            mergeTimeoutWork?.cancel()
            objectWillChange.send()
            appendDebug("✅ 整合回复写入，长度=\(reply.count)")
        } else {
            sendTimeoutWork?.cancel()
            geminiResponse = reply
            objectWillChange.send()
            appendDebug("📥 GM回复到达，长度=\(reply.count)，开启3s监听窗口...")
            scheduleWindow(for: .gemini, currentLength: reply.count)
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

    // MARK: - 3s 监听窗口（1s初始缓冲 + 2s稳定检测）

    private enum ReplySource { case deepSeek, gemini }

    // 第一阶段：1s 初始缓冲（等内容开始流入后再进入稳定检测）
    private func scheduleWindow(for source: ReplySource, currentLength: Int) {
        switch source {
        case .deepSeek:
            dsWindowWork?.cancel()
            dsStabilizeWork?.cancel()
            lastDSLength = currentLength
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                // 1s 后更新快照，进入第二阶段稳定检测
                self.lastDSLength = self.deepSeekResponse.count
                self.appendDebug("⏱ DS 1s缓冲完毕，长度=\(self.lastDSLength)，等待2s稳定...")
                self.scheduleStabilize(for: .deepSeek)
            }
            dsWindowWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)

        case .gemini:
            gmWindowWork?.cancel()
            gmStabilizeWork?.cancel()
            lastGMLength = currentLength
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.lastGMLength = self.geminiResponse.count
                self.appendDebug("⏱ GM 1s缓冲完毕，长度=\(self.lastGMLength)，等待2s稳定...")
                self.scheduleStabilize(for: .gemini)
            }
            gmWindowWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        }
    }

    // 第二阶段：2s 稳定检测（内容 2s 不再增长则完成）
    private func scheduleStabilize(for source: ReplySource) {
        switch source {
        case .deepSeek:
            dsStabilizeWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.checkStability(source: .deepSeek) }
            dsStabilizeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
        case .gemini:
            gmStabilizeWork?.cancel()
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
                appendDebug("✅ DS回复稳定（3s窗口完成），长度=\(current)")
                tryAutoMerge()
            } else {
                // 内容仍在变化，重启稳定检测
                lastDSLength = current
                appendDebug("🔄 DS内容更新中，长度=\(current)，重置稳定计时...")
                scheduleStabilize(for: .deepSeek)
            }
        case .gemini:
            let current = geminiResponse.count
            if current == lastGMLength {
                isGeminiLoading = false
                objectWillChange.send()
                appendDebug("✅ GM回复稳定（3s窗口完成），长度=\(current)")
                tryAutoMerge()
            } else {
                lastGMLength = current
                appendDebug("🔄 GM内容更新中，长度=\(current)，重置稳定计时...")
                scheduleStabilize(for: .gemini)
            }
        }
    }

    // 双端均稳定后自动整合
    private func tryAutoMerge() {
        guard !isDeepSeekLoading, !isGeminiLoading,
              canMerge, !isMerging, mergedResponse.isEmpty else { return }
        appendDebug("🔀 双端3s窗口内容已稳定，自动触发整合")
        merge()
    }

    private func cancelAllStabilize() {
        dsWindowWork?.cancel()
        dsStabilizeWork?.cancel()
        gmWindowWork?.cancel()
        gmStabilizeWork?.cancel()
    }

    // MARK: - Private Binding

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
