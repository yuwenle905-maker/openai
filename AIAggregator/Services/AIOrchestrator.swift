import Foundation
import Combine

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

    func send(query: String) async {
        deepSeekResponse = ""
        geminiResponse   = ""
        mergedResponse   = ""
        isDeepSeekLoading = true
        isGeminiLoading   = true

        // async let 在同一 actor 上并发执行两个异步任务，
        // 避免 withTaskGroup + @MainActor 捕获导致的 Sendability 崩溃
        async let ds: Void = webVM.sendToDeepSeek(query: query)
        async let gm: Void = webVM.sendToGemini(query: query)
        _ = await (ds, gm)
    }

    func merge() async {
        guard !deepSeekResponse.isEmpty, !geminiResponse.isEmpty else { return }
        isMerging = true
        mergedResponse = ""

        let script = JSBridge.buildMergeScript(
            deepSeekAnswer: deepSeekResponse,
            geminiAnswer: geminiResponse
        )
        _ = try? await webVM.geminiWebView.evaluateJavaScript(script)
    }

    // MARK: - Private

    private func bindWebVM() {
        // 用 Task { @MainActor in } 而非 .receive(on: DispatchQueue.main)
        // 确保修改 @Published 属性时始终在 MainActor 上，不触发 actor 隔离崩溃
        webVM.$deepSeekReply
            .filter { !$0.isEmpty }
            .sink { [weak self] reply in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.deepSeekResponse  = reply
                    self.isDeepSeekLoading = false
                }
            }
            .store(in: &cancellables)

        webVM.$geminiReply
            .filter { !$0.isEmpty }
            .sink { [weak self] reply in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.isMerging {
                        self.mergedResponse = reply
                        self.isMerging      = false
                    } else {
                        self.geminiResponse  = reply
                        self.isGeminiLoading = false
                    }
                }
            }
            .store(in: &cancellables)
    }
}
