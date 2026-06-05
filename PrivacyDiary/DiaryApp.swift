import SwiftUI
import SwiftData

@main
struct DiaryApp: App {

    @StateObject private var keyStore = KeyStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(keyStore)
        }
        .modelContainer(for: DiaryEntry.self)
    }
}

// MARK: - ContentView

struct ContentView: View {
    var body: some View {
        TabView {
            MainDiaryView()
                .tabItem {
                    Label("杂鱼", systemImage: "fish.fill")
                }

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
        }
    }
}
