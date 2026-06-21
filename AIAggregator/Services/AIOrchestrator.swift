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

        // 各自独立的 MainActor Task，完全避免 async let / withTaskGroup
        // 的 Sendability 问题；状态由 Combine 绑定在回复到达时更新
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.webVM.sendToDeepSeek(query: query)
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.webVM.sendToGemini(query: query)
        }
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
