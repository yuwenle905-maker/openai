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

    // 转发 WebViewModel 的就绪状态，供 ControlPanelView 显示
    @Published var deepSeekIsReady: Bool = false
    @Published var geminiIsReady: Bool   = false

    // 转发登录检测结果（自动化 WebView 侧）
    @Published var deepSeekIsLoggedIn: Bool = false
    @Published var geminiIsLoggedIn: Bool   = false

    var canMerge: Bool { !deepSeekResponse.isEmpty && !geminiResponse.isEmpty }

    private let webVM = WebViewModel()
    private var cancellables = Set<AnyCancellable>()
    private var mergeTimeoutWork: DispatchWorkItem?
    private var sendTimeoutWork: DispatchWorkItem?

    // 3s 监听窗口（1s 初始缓冲 + 2s 稳定检测）
    private var dsWindowWork: DispatchWorkItem?
    private var dsStabilizeWork: DispatchWorkItem?
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

        // 强制要求详细、深度回答
        let enriched = "请提供详细、深度的分析，尽可能全面地回答以下问题，内容不少于300字。\n\n\(query)"
        appendDebug("📤 发送: \(query.prefix(30))...")

        sendTimeoutWork?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            var stuck: [String] = []
            if self.isDeepSeekLoading { stuck.append("DeepSeek") }
            if self.isGeminiLoading   { stuck.append("Gemini") }
            if !stuck.isEmpty { self.appendDebug("⚠️ 15s超时无回复: \(stuck.joined(separator: "/"))") }
        }
        sendTimeoutWork = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)

        webVM.sendToDeepSeek(query: enriched)
        webVM.sendToGemini(query: enriched)
    }

    func merge() {
        guard canMerge else { return }
        isMerging      = true
        mergedResponse = ""
        objectWillChange.send()
        appendDebug("🔀 触发整合，注入 Gemini...")
        let script = JSBridge.buildMergeScript(deepSeekAnswer: deepSeekResponse, geminiAnswer: geminiResponse)
        webVM.geminiWebView.evaluateJavaScript(script) { [weak self] _, error in
            if let error { self?.appendDebug("⚠️ merge 注入错误: \(error.localizedDescription)") }
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

    // MARK: - 强制渲染（3s监听窗口）

    func renderDeepSeekReply(_ reply: String) {
        guard !reply.isEmpty else { return }
        sendTimeoutWork?.cancel()
        deepSeekResponse = reply
        objectWillChange.send()
        appendDebug("📥 DS到达，长度=\(reply.count)，开启3s窗口...")
        scheduleWindow(for: .deepSeek, currentLength: reply.count)
    }

    func renderGeminiReply(_ reply: String) {
        guard !reply.isEmpty else { return }
        if isMerging {
            mergedResponse = reply
            isMerging      = false
            mergeTimeoutWork?.cancel()
            objectWillChange.send()
            appendDebug("✅ 整合结论写入，长度=\(reply.count)")
        } else {
            sendTimeoutWork?.cancel()
            geminiResponse = reply
            objectWillChange.send()
            appendDebug("📥 GM到达，长度=\(reply.count)，开启3s窗口...")
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
        if lines.count > 30 { debugLog = lines.suffix(30).joined(separator: "\n") }
    }

    // MARK: - 3s 监听窗口（1s初始缓冲 + 2s稳定）

    private enum ReplySource { case deepSeek, gemini }

    private func scheduleWindow(for source: ReplySource, currentLength: Int) {
        switch source {
        case .deepSeek:
            dsWindowWork?.cancel(); dsStabilizeWork?.cancel()
            lastDSLength = currentLength
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.lastDSLength = self.deepSeekResponse.count
                self.appendDebug("⏱ DS 1s缓冲完毕，长度=\(self.lastDSLength)，等待2s稳定...")
                self.scheduleStabilize(for: .deepSeek)
            }
            dsWindowWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        case .gemini:
            gmWindowWork?.cancel(); gmStabilizeWork?.cancel()
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
                appendDebug("✅ DS稳定，长度=\(current)")
                tryAutoMerge()
            } else {
                lastDSLength = current
                appendDebug("🔄 DS仍在更新，长度=\(current)，重置稳定计时...")
                scheduleStabilize(for: .deepSeek)
            }
        case .gemini:
            let current = geminiResponse.count
            if current == lastGMLength {
                isGeminiLoading = false
                objectWillChange.send()
                appendDebug("✅ GM稳定，长度=\(current)")
                tryAutoMerge()
            } else {
                lastGMLength = current
                appendDebug("🔄 GM仍在更新，长度=\(current)，重置稳定计时...")
                scheduleStabilize(for: .gemini)
            }
        }
    }

    private func tryAutoMerge() {
        guard !isDeepSeekLoading, !isGeminiLoading,
              canMerge, !isMerging, mergedResponse.isEmpty else { return }
        appendDebug("🔀 双端稳定，自动整合")
        merge()
    }

    private func cancelAllStabilize() {
        dsWindowWork?.cancel(); dsStabilizeWork?.cancel()
        gmWindowWork?.cancel(); gmStabilizeWork?.cancel()
    }

    // MARK: - Bindings

    private func bindWebVM() {
        webVM.$deepSeekReply
            .filter { !$0.isEmpty }
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.renderDeepSeekReply($0) }
            .store(in: &cancellables)

        webVM.$geminiReply
            .filter { !$0.isEmpty }
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.renderGeminiReply($0) }
            .store(in: &cancellables)

        webVM.$debugEntry
            .filter { !$0.isEmpty }
            .receive(on: RunLoop.main)
            .sink { [weak self] entry in
                guard let self else { return }
                debugLog = debugLog.isEmpty ? entry : debugLog + "\n" + entry
                let lines = debugLog.components(separatedBy: "\n")
                if lines.count > 30 { debugLog = lines.suffix(30).joined(separator: "\n") }
            }
            .store(in: &cancellables)

        // 转发 ready 状态供 UI 显示
        webVM.$deepSeekIsReady
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.deepSeekIsReady = $0 }
            .store(in: &cancellables)

        webVM.$geminiIsReady
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.geminiIsReady = $0 }
            .store(in: &cancellables)

        // 转发登录状态
        webVM.$deepSeekIsLoggedIn
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.deepSeekIsLoggedIn = $0 }
            .store(in: &cancellables)

        webVM.$geminiIsLoggedIn
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.geminiIsLoggedIn = $0 }
            .store(in: &cancellables)
    }
}
