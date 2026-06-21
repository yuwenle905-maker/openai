import SwiftUI

@main
struct AIAggregatorApp: App {
    @StateObject private var orchestrator = AIOrchestrator()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(orchestrator)
                .preferredColorScheme(.dark)
        }
    }
}
