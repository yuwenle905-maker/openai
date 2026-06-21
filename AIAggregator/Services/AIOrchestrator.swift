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

    // AccountView 通过这两个属性复用同一对 WebView，避免创建第 3 个
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

        // sendToDeepSeek/Gemini 现在是同步方法（内部用 completion handler）
        // 直接调用，零 async/await，彻底消除并发崩溃风险
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
        webVM.geminiWebView.evaluateJavaScript(script) { [weak self] _, error in
            if let error { print("[Orchestrator] merge error: \(error)") }
            self?.isMerging = false
        }
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
