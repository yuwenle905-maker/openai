// MARK: - SettingsView.swift
// 全局设置 — 数据单价、安全锁（可自由开关）、备份/恢复

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject var store:       DataStore
    @EnvironmentObject var lockManager: LockManager

    // 数据单价编辑
    @State private var priceText: String = ""
    @FocusState private var priceFocused: Bool

    // PIN 设置
    @State private var newPIN:     String = ""
    @State private var confirmPIN: String = ""
    @State private var showPINSetup = false

    // 备份/恢复
    @State private var backupPassword:  String = ""
    @State private var restorePassword: String = ""
    @State private var showBackupSheet  = false
    @State private var showRestoreSheet = false
    @State private var backupData: Data?
    @State private var showShareSheet = false
    @State private var alertMessage:   String = ""
    @State private var showAlert       = false

    var body: some View {
        NavigationView {
            Form {

                // ── 数据单价 ───────────────────────────────────
                Section {
                    HStack {
                        Text("数据单价")
                        Spacer()
                        TextField("元/条", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($priceFocused)
                            .frame(width: 100)
                            .onAppear { priceText = "\(Int(store.settings.leadUnitPrice))" }
                            .onChange(of: priceFocused) { focused in
                                if !focused, let value = Double(priceText), value > 0 {
                                    store.settings.leadUnitPrice = value
                                    store.save()
                                }
                            }
                        Text("元/条")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("ROI 计算参数")
                } footer: {
                    Text("本月成本 = 导入总条数 × 数据单价")
                        .font(.caption)
                }

                // ── 安全锁（自由开关）─────────────────────────
                Section {
                    // Face ID / Touch ID 开关
                    let bioType = lockManager.biometricType
                    if bioType != "不支持" {
                        Toggle(isOn: $store.settings.biometricLockEnabled) {
                            Label(bioType + " 解锁", systemImage: "faceid")
                        }
                        .onChange(of: store.settings.biometricLockEnabled) { _ in
                            lockManager.refresh(settings: store.settings)
                            store.save()
                        }
                    }

                    // 密码锁开关
                    Toggle(isOn: $store.settings.appPINEnabled) {
                        Label("密码锁（PIN）", systemImage: "lock.fill")
                    }
                    .onChange(of: store.settings.appPINEnabled) { enabled in
                        if enabled && store.settings.appPIN.isEmpty {
                            showPINSetup = true
                        }
                        if !enabled {
                            store.settings.appPIN = ""
                        }
                        lockManager.refresh(settings: store.settings)
                        store.save()
                    }

                    // PIN 修改入口
                    if store.settings.appPINEnabled {
                        Button("修改密码") { showPINSetup = true }
                    }

                } header: {
                    Text("隐私与安全")
                } footer: {
                    Text("关闭所有开关后 App 无锁保护。Face ID 失败时可降级使用 PIN 密码。")
                        .font(.caption)
                }

                // ── 备份与恢复 ─────────────────────────────────
                Section {
                    Button {
                        showBackupSheet = true
                    } label: {
                        Label("加密备份数据", systemImage: "lock.doc.fill")
                    }

                    Button {
                        showRestoreSheet = true
                    } label: {
                        Label("从备份恢复", systemImage: "arrow.counterclockwise.circle.fill")
                    }
                    .foregroundStyle(.orange)

                } header: {
                    Text("数据管理")
                } footer: {
                    Text("备份文件使用 AES-256-GCM 加密，需凭密码才能解密恢复。")
                        .font(.caption)
                }

                // ── 数据统计 ───────────────────────────────────
                Section("概览") {
                    LabeledContent("客户总数",    value: "\(store.customers.count) 人")
                    LabeledContent("导入批次数",  value: "\(store.batches.count) 次")
                    LabeledContent("数据单价",    value: "¥\(Int(store.settings.leadUnitPrice))/条")
                }
            }
            .navigationTitle("设置")
            // ── PIN 设置 Sheet ─────────────────────────────────
            .sheet(isPresented: $showPINSetup) {
                PINSetupSheet(
                    currentPIN: store.settings.appPIN
                ) { pin in
                    store.settings.appPIN       = pin
                    store.settings.appPINEnabled = true
                    store.save()
                    lockManager.refresh(settings: store.settings)
                }
            }
            // ── 备份 Sheet ─────────────────────────────────────
            .sheet(isPresented: $showBackupSheet) {
                BackupSheet { password in
                    guard !password.isEmpty else {
                        alertMessage = "请输入备份密码"
                        showAlert = true
                        return
                    }
                    do {
                        let data = try BackupManager.export(store: store, password: password)
                        backupData = data
                        showBackupSheet = false
                        showShareSheet  = true
                    } catch {
                        alertMessage = error.localizedDescription
                        showAlert    = true
                    }
                }
            }
            // ── 恢复 Sheet ─────────────────────────────────────
            .sheet(isPresented: $showRestoreSheet) {
                RestoreSheet { url, password in
                    guard let data = try? Data(contentsOf: url) else {
                        alertMessage = "无法读取备份文件"
                        showAlert = true
                        return
                    }
                    do {
                        try BackupManager.import(data: data, password: password, into: store)
                        alertMessage = "✅ 数据恢复成功"
                        showAlert    = true
                        showRestoreSheet = false
                    } catch {
                        alertMessage = error.localizedDescription
                        showAlert    = true
                    }
                }
            }
            // ── 分享加密备份文件 ───────────────────────────────
            .sheet(isPresented: $showShareSheet) {
                if let data = backupData {
                    ShareSheet(items: [data])
                }
            }
            .alert("提示", isPresented: $showAlert) {
                Button("确认", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }
}

// MARK: - PIN 设置弹窗
struct PINSetupSheet: View {
    let currentPIN: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var pin1 = ""
    @State private var pin2 = ""
    @State private var errorMsg = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    SecureField("输入新密码（4-6位数字）", text: $pin1)
                        .keyboardType(.numberPad)
                    SecureField("再次确认密码", text: $pin2)
                        .keyboardType(.numberPad)
                } footer: {
                    if !errorMsg.isEmpty {
                        Text(errorMsg).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("设置密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard pin1.count >= 4 && pin1.count <= 6 else {
                            errorMsg = "密码长度需为 4-6 位数字"; return
                        }
                        guard pin1 == pin2 else {
                            errorMsg = "两次输入不一致"; return
                        }
                        onSave(pin1)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 备份密码输入 Sheet
struct BackupSheet: View {
    let onExport: (String) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var password = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    SecureField("设置备份密码", text: $password)
                } footer: {
                    Text("请牢记此密码，恢复数据时需要使用。")
                        .font(.caption)
                }
            }
            .navigationTitle("加密备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("导出") { onExport(password) }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 恢复 Sheet
struct RestoreSheet: View {
    let onRestore: (URL, String) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var password  = ""
    @State private var showPicker = false
    @State private var selectedURL: URL?

    var body: some View {
        NavigationView {
            Form {
                Section("选择备份文件") {
                    Button("选择文件") { showPicker = true }
                    if let url = selectedURL {
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("备份密码") {
                    SecureField("输入备份时设置的密码", text: $password)
                }
            }
            .navigationTitle("从备份恢复")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("恢复") {
                        guard let url = selectedURL else { return }
                        onRestore(url, password)
                    }
                    .disabled(selectedURL == nil || password.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showPicker,
                allowedContentTypes: [.data]
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    selectedURL = url
                }
            }
        }
    }
}

// MARK: - 系统分享 Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
