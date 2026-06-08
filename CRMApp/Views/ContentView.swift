// MARK: - ContentView.swift
// 根视图 — 锁屏门卫 + TabBar 主导航

import SwiftUI

struct ContentView: View {

    @EnvironmentObject var store:       DataStore
    @EnvironmentObject var lockManager: LockManager

    var body: some View {
        Group {
            if lockManager.lockState == .unlocked {
                MainTabView()
            } else {
                LockScreenView()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
        ) { _ in
            lockManager.lock()
        }
    }
}

// MARK: - 主 TabBar
struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("看板", systemImage: "chart.bar.fill") }

            CustomerListView()
                .tabItem { Label("客户", systemImage: "person.3.fill") }

            ImportView()
                .tabItem { Label("智能导入", systemImage: "doc.text.magnifyingglass") }

            TextInputView()
                .tabItem { Label("流水录入", systemImage: "pencil.and.list.clipboard") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .accentColor(.blue)
    }
}
