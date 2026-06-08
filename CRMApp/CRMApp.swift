// MARK: - CRMApp.swift
// App 入口 — 依赖注入、环境对象装配

import SwiftUI

@main
struct CRMApp: App {

    @StateObject private var store       = DataStore()
    @StateObject private var lockManager: LockManager

    // LockManager 需要读取 settings，故在 init 中初始化
    init() {
        let s = DataStore()
        _store       = StateObject(wrappedValue: s)
        _lockManager = StateObject(wrappedValue: LockManager(settings: s.settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(lockManager)
        }
    }
}
