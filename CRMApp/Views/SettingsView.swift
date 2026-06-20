// MARK: - SettingsView.swift
// 全局设置 — 数据单价、安全锁（可自由开关）、备份/恢复（iOS 15 兼容）

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {

    @EnvironmentObject var store:       DataStore
    @EnvironmentObject var lockManager: LockManager

    @State private var priceText:        String = ""
    @State private var showPINSetup      = false
    @State private var showBackupSheet   = false
    @State private var showRestoreSheet  = false
    @State private var backupData:       Data?
    @State private var showShareSheet    = false
    @State private var alertMessage:     String = ""
    @State private var showAlert         = false
    @State private var showClearConfirm  = false

    // 明文 JSON 备份（无密码，最简单可靠）
    @State private var showPlainShareSheet = false
    @State private var plainBackupURL:     URL?
    @State private var showFileImporter    = false

    var body: some View {
        NavigationView {
            Form {

                // ── 数据单价 ───────────────────────────────────
                Section {
                    HStack {
                        Text("当前单价")
                        Spacer()
                        Text("¥\(Int(store.settings.leadUnitPrice)) / 条")
                            .foregroundColor(.blue)
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("修改为")
                        TextField("输入新单价", text: $priceText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .onAppear { priceText = "" }
                            .onSubmit { applyNewPrice() }
                    }
                    Button(action: applyNewPrice) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("保存新单价")
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(8)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                } header: {
                    Text("ROI 计算参数")
                } footer: {
                    Text("输入新单价后点「保存新单价」，或键盘点「完成」即可生效。").font(.caption)
                }

                // ── 安全锁 ─────────────────────────────────────
                Section {
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

                    Toggle(isOn: $store.settings.appPINEnabled) {
                        Label("密码锁（PIN）", systemImage: "lock.fill")
                    }
                    .onChange(of: store.settings.appPINEnabled) { enabled in
                        if enabled && store.settings.appPIN.isEmpty { showPINSetup = true }
                        if !enabled { store.settings.appPIN = "" }
                        lockManager.refresh(settings: store.settings)
                        store.save()
                    }

                    if store.settings.appPINEnabled {
                        Button("修改密码") { showPINSetup = true }
                    }
                } header: {
                    Text("隐私与安全")
                } footer: {
                    Text("关闭所有开关后 App 无锁保护。Face ID 失败时可降级使用 PIN 密码。")
                        .font(.caption)
                }

                // ── 数据安全中心（双重保险）────────────────────
                Section {
                    // A：导出备份（明文 JSON，可通过微信/AirDrop/存储到文件保存）
                    Button {
                        exportPlainBackup()
                    } label: {
                        Label("导出备份数据（分享到微信/文件）", systemImage: "square.and.arrow.up")
                            .foregroundColor(.blue)
                    }

                    // B：导入备份（系统文件选择器，选择之前导出的 JSON）
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("导入备份数据（从文件恢复）", systemImage: "square.and.arrow.down")
                            .foregroundColor(.orange)
                    }

                    // 原加密备份（保留，用于高安全场景）
                    Button {
                        showBackupSheet = true
                    } label: {
                        Label("加密备份（高级）", systemImage: "lock.doc.fill")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                    Button {
                        showRestoreSheet = true
                    } label: {
                        Label("从加密备份恢复（高级）", systemImage: "arrow.counterclockwise.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                } header: {
                    Text("数据安全中心")
                } footer: {
                    Text("【导出备份】将全部数据导出为 JSON 文件，可存入微信收藏、文件 App 或发送给自己。覆盖安装前务必先备份！").font(.caption)
                }

                // ── 危险操作 ───────────────────────────────────
                Section {
                    Button {
                        showClearConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("一键清空历史数据", systemImage: "trash.fill")
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                } header: {
                    Text("危险操作")
                } footer: {
                    Text("仅清空 App 内的客户与批次数据，不删除本地备份文件，随时可通过备份恢复。")
                        .font(.caption)
                }

                // ── 概览 ───────────────────────────────────────
                Section(header: Text("概览")) {
                    InfoRow(label: "客户总数",  value: "\(store.customers.count) 人")
                    InfoRow(label: "导入批次数", value: "\(store.batches.count) 次")
                    InfoRow(label: "数据单价",  value: "¥\(Int(store.settings.leadUnitPrice))/条")
                }
            }
            .navigationTitle("设置")
            .confirmationDialog(
                "确认清空所有历史数据？",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("确认清空", role: .destructive) {
                    store.customers = []
                    store.batches   = []
                    store.save()
                    alertMessage = "已清空所有客户和批次数据。备份文件保持完好，可随时恢复。"
                    showAlert    = true
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作将删除 App 内所有客户记录和导入批次，但不会删除备份文件。确认后无法撤销。")
            }
            .sheet(isPresented: $showPINSetup) {
                PINSetupSheet(currentPIN: store.settings.appPIN) { pin in
                    store.settings.appPIN        = pin
                    store.settings.appPINEnabled = true
                    store.save()
                    lockManager.refresh(settings: store.settings)
                }
            }
            // 明文 JSON 分享 Sheet
            .sheet(isPresented: $showPlainShareSheet) {
                if let url = plainBackupURL {
                    ShareSheet(items: [url])
                }
            }
            // 文件导入器（选 JSON 恢复）
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.json, .data],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result: result)
            }
            .sheet(isPresented: $showBackupSheet) {
                BackupSheet { password in
                    guard !password.isEmpty else {
                        alertMessage = "请输入备份密码"; showAlert = true; return
                    }
                    do {
                        let data = try BackupManager.export(store: store, password: password)
                        backupData      = data
                        showBackupSheet = false
                        showShareSheet  = true
                    } catch {
                        alertMessage = error.localizedDescription; showAlert = true
                    }
                }
            }
            .sheet(isPresented: $showRestoreSheet) {
                RestoreSheet { url, password in
                    guard let data = try? Data(contentsOf: url) else {
                        alertMessage = "无法读取备份文件"; showAlert = true; return
                    }
                    do {
                        try BackupManager.import(data: data, password: password, into: store)
                        alertMessage = "数据恢复成功"; showAlert = true; showRestoreSheet = false
                    } catch {
                        alertMessage = error.localizedDescription; showAlert = true
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let data = backupData { ShareSheet(items: [data]) }
            }
            .alert("提示", isPresented: $showAlert) {
                Button("确认", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }

    // MARK: 明文 JSON 导出
    private func exportPlainBackup() {
        let encoder = JSONEncoder()
        encoder.outputFormatting    = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        struct PlainBackup: Encodable {
            let version: Int
            let exportDate: String
            let customers: [Customer]
            let batches:   [ImportBatch]
        }

        let fmt = ISO8601DateFormatter()
        let payload = PlainBackup(
            version:    2,
            exportDate: fmt.string(from: Date()),
            customers:  store.customers,
            batches:    store.batches
        )

        guard let data = try? encoder.encode(payload) else {
            alertMessage = "导出失败：序列化错误"; showAlert = true; return
        }

        // 写入临时文件，方便分享
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CRMBackup_\(fmt.string(from: Date()).prefix(10)).json")
        do {
            try data.write(to: tmpURL, options: .atomicWrite)
            plainBackupURL    = tmpURL
            showPlainShareSheet = true
        } catch {
            alertMessage = "写入临时文件失败：\(error.localizedDescription)"
            showAlert    = true
        }
    }

    // MARK: 文件导入恢复
    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            alertMessage = "选择文件失败：\(err.localizedDescription)"; showAlert = true
        case .success(let urls):
            guard let url = urls.first else { return }
            // 需要安全访问沙盒外文件
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url) else {
                alertMessage = "无法读取文件，请检查权限"; showAlert = true; return
            }

            // 先尝试明文格式
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            struct PlainBackup: Decodable {
                let customers: [Customer]
                let batches:   [ImportBatch]?
            }

            if let payload = try? decoder.decode(PlainBackup.self, from: data) {
                DispatchQueue.main.async {
                    store.customers = payload.customers
                    store.batches   = payload.batches ?? []
                    store.save()
                    alertMessage = "✅ 恢复成功！共导入 \(store.customers.count) 位客户"
                    showAlert    = true
                }
                return
            }

            // 再尝试加密格式（BackupPayload）
            if let payload = try? decoder.decode(BackupPayload.self, from: data) {
                DispatchQueue.main.async {
                    store.customers = payload.customers
                    store.batches   = payload.batches
                    store.save()
                    alertMessage = "✅ 恢复成功！共导入 \(store.customers.count) 位客户"
                    showAlert    = true
                }
                return
            }

            alertMessage = "文件格式不支持，请选择由本 App 导出的 JSON 备份文件"
            showAlert    = true
        }
    }

    // MARK: 保存新单价
    private func applyNewPrice() {
        let cleaned = priceText.trimmingCharacters(in: .whitespaces)
        if let value = Double(cleaned), value > 0 {
            store.settings.leadUnitPrice = value
            store.save()
            priceText = ""
        }
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
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
                    SecureField("输入新密码（4-6位数字）", text: $pin1).keyboardType(.numberPad)
                    SecureField("再次确认密码",          text: $pin2).keyboardType(.numberPad)
                } footer: {
                    if !errorMsg.isEmpty {
                        Text(errorMsg).foregroundColor(.red).font(.caption)
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
                        guard pin1 == pin2 else { errorMsg = "两次输入不一致"; return }
                        onSave(pin1); dismiss()
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
                    Text("请牢记此密码，恢复数据时需要使用。").font(.caption)
                }
            }
            .navigationTitle("加密备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("导出") { onExport(password) } }
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }
}

// MARK: - 恢复 Sheet（iOS 15 fileImporter 回调类型为 Result<[URL], Error>）
struct RestoreSheet: View {
    let onRestore: (URL, String) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var password    = ""
    @State private var showPicker  = false
    @State private var selectedURL: URL?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("选择备份文件")) {
                    Button("选择文件") { showPicker = true }
                    if let url = selectedURL {
                        Text(url.lastPathComponent).font(.caption).foregroundColor(.secondary)
                    }
                }
                Section(header: Text("备份密码")) {
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
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            // iOS 15 单选：fileImporter 回调类型为 Result<URL, Error>，直接赋值
            .fileImporter(isPresented: $showPicker, allowedContentTypes: [.data]) { result in
                if case .success(let url) = result {
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
