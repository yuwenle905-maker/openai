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

// MARK: - ContentView (tab shell)

struct ContentView: View {
    var body: some View {
        TabView {
            MainDiaryView()
                .tabItem {
                    Label("日记", systemImage: "book.closed.fill")
                }

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
        }
    }
}
