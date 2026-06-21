import Foundation
import Combine

/// 协调 DeepSeek + Gemini 双引擎并发查询与整合
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

    init() { bindWebVM() }

    // MARK: - Public

    /// 并发向双端发送查询
    func send(query: String) async {
        deepSeekResponse = ""
        geminiResponse   = ""
        mergedResponse   = ""
        isDeepSeekLoading = true
        isGeminiLoading   = true

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.webVM.sendToDeepSeek(query: query) }
            group.addTask { await self.webVM.sendToGemini(query: query) }
        }
    }

    /// 调用 Gemini 对两端回复进行二次整合
    func merge() async {
        guard !deepSeekResponse.isEmpty, !geminiResponse.isEmpty else { return }
        isMerging = true
        mergedResponse = ""

        let script = JSBridge.buildMergeScript(
            deepSeekAnswer: deepSeekResponse,
            geminiAnswer: geminiResponse
        )
        _ = try? await webVM.geminiWebView.evaluateJavaScript(script)
        // 整合结果通过 WKScriptMessageHandler 回调写入 webVM.geminiReply
    }

    // MARK: - Private

    private func bindWebVM() {
        webVM.$deepSeekReply
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reply in
                guard let self, !reply.isEmpty else { return }
                self.deepSeekResponse  = reply
                self.isDeepSeekLoading = false
            }
            .store(in: &cancellables)

        webVM.$geminiReply
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reply in
                guard let self, !reply.isEmpty else { return }
                if self.isMerging {
                    self.mergedResponse = reply
                    self.isMerging = false
                } else {
                    self.geminiResponse  = reply
                    self.isGeminiLoading = false
                }
            }
            .store(in: &cancellables)
    }
}
