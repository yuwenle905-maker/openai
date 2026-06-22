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

    private let webVM = WebViewModel()
    private var cancellables = Set<AnyCancellable>()
    private var mergeTimeoutWork: DispatchWorkItem?

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

        // evaluateJavaScript 的 completion 是 JS「注入完成」回调，
        // 不是 Gemini「回答完成」回调，绝对不能在这里 isMerging = false。
        // isMerging 的重置由 Combine 绑定在 geminiReply 到达时处理。
        webVM.geminiWebView.evaluateJavaScript(script) { _, error in
            if let error { print("[Orchestrator] merge 注入错误: \(error)") }
        }

        // 120 秒硬超时：防止整合永久卡住
        mergeTimeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isMerging else { return }
            print("[Orchestrator] merge 120s 超时，强制重置")
            self.isMerging = false
        }
        mergeTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: work)
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
                self.deepSeekResponse  = reply
                self.isDeepSeekLoading = false
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
                } else {
                    print("[Orchestrator] ✅ Gemini 回复到达，长度=\(reply.count)")
                    self.geminiResponse  = reply
                    self.isGeminiLoading = false
                }
            }
            .store(in: &cancellables)
    }
}
