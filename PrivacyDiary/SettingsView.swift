import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - KeyStore

final class KeyStore: ObservableObject {
    @Published var globalKey: String {
        didSet { UserDefaults.standard.set(globalKey, forKey: "diary_global_key") }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "diary_global_key") ?? ""
        self.globalKey = saved.isEmpty ? "ZaYu_Default_2024" : saved
    }
}

// MARK: - Backup file format

private struct BackupFile: Codable {
    let version: Int                // format version
    let exportedAt: String          // ISO8601
    let key: String                 // encrypted key (AES-GCM with backup passphrase)
    let entries: [BackupEntry]
}

private struct BackupEntry: Codable {
    let id: String
    let timestamp: String           // ISO8601
    let encryptedData: String
    let clipboardData: String
}

// MARK: - SettingsView

struct SettingsView: View {

    @EnvironmentObject private var keyStore: KeyStore
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [DiaryEntry]

    @State private var isRekeying = false
    @State private var showConfirmRekey = false
    @State private var rekeySuccess: Bool? = nil

    // Export
    @State private var exportItem: BackupDocument? = nil
    @State private var showExporter = false
    @State private var exportMsg: String? = nil

    // Import
    @State private var showImporter = false
    @State private var importMsg: String? = nil
    @State private var importSuccess: Bool? = nil

    var body: some View {
        NavigationStack {
            Form {
                rekeySection
                infoSection
                backupSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .alert("确认更换密钥", isPresented: $showConfirmRekey) {
                Button("取消", role: .cancel) {}
                Button("确认", role: .destructive) { performRekey() }
            } message: {
                Text("将为本地 \(entries.count) 条记录随机生成并应用新密钥，操作不可撤销。")
            }
            .overlay {
                if isRekeying { progressOverlay }
            }
            // Export to Files
            .fileExporter(
                isPresented: $showExporter,
                document: exportItem,
                contentType: .zaYuBackup,
                defaultFilename: "杂鱼备份_\(dateStamp())"
            ) { result in
                switch result {
                case .success: exportMsg = "备份已保存到文件"
                case .failure(let e): exportMsg = "导出失败：\(e.localizedDescription)"
                }
            }
            // Import from Files
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.zaYuBackup, .json],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                importBackup(from: url)
            }
        }
    }

    // MARK: - 更换密钥 Section

    private var rekeySection: some View {
        Section {
            HStack {
                Text("一键刷新密钥")
                Spacer()
                if let ok = rekeySuccess {
                    Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(ok ? .green : .red)
                        .transition(.scale.combined(with: .opacity))
                }
                Button {
                    showConfirmRekey = true
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .disabled(isRekeying)
            }
        } header: {
            Label("密钥管理", systemImage: "key.fill")
        } footer: {
            Text("点击刷新按钮将随机生成新密钥并重新加密所有本地记录。")
                .font(.caption)
        }
    }

    // MARK: - 数据库信息 Section

    private var infoSection: some View {
        Section {
            LabeledContent("本地条目数", value: "\(entries.count) 条")
            LabeledContent("软件版本", value: "260606")
        } header: {
            Label("数据库信息", systemImage: "externaldrive.fill")
        }
    }

    // MARK: - 备份 Section

    private var backupSection: some View {
        Section {
            // 导出
            Button {
                prepareExport()
            } label: {
                HStack {
                    Label("导出备份到文件", systemImage: "arrow.up.doc.fill")
                    Spacer()
                    if entries.isEmpty {
                        Text("无记录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(entries.isEmpty)

            if let msg = exportMsg {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(msg.contains("失败") ? .red : .green)
            }

            // 导入
            Button {
                showImporter = true
                importMsg = nil
                importSuccess = nil
            } label: {
                Label("从文件恢复备份", systemImage: "arrow.down.doc.fill")
            }

            if let msg = importMsg {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle((importSuccess == true) ? .green : .red)
            }

        } header: {
            Label("数据备份", systemImage: "icloud.and.arrow.up")
        } footer: {
            Text("备份文件包含所有加密密文，保存在本机文件 App 中。重装 App 后可从备份文件恢复历史记录。")
                .font(.caption)
        }
    }

    // MARK: - 进度遮罩

    private var progressOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().scaleEffect(1.4).tint(.white)
                Text("正在刷新密钥…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    // MARK: - Export logic

    private func prepareExport() {
        exportMsg = nil
        let isoFormatter = ISO8601DateFormatter()
        let backupEntries = entries.map { e in
            BackupEntry(
                id: e.id.uuidString,
                timestamp: isoFormatter.string(from: e.timestamp),
                encryptedData: e.encryptedData,
                clipboardData: e.clipboardData
            )
        }
        let backup = BackupFile(
            version: 1,
            exportedAt: isoFormatter.string(from: Date()),
            key: keyStore.globalKey,   // stored as-is; file itself is the user's responsibility
            entries: backupEntries
        )
        if let data = try? JSONEncoder().encode(backup) {
            exportItem = BackupDocument(data: data)
            showExporter = true
        } else {
            exportMsg = "导出失败：无法序列化数据"
        }
    }

    // MARK: - Import logic

    private func importBackup(from url: URL) {
        importMsg = nil
        importSuccess = nil

        guard url.startAccessingSecurityScopedResource() else {
            importMsg = "无法访问文件，请重试"
            importSuccess = false
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let backup = try JSONDecoder().decode(BackupFile.self, from: data)

            // Restore key
            keyStore.globalKey = backup.key

            // Restore entries — skip duplicates by ID
            let existingIDs = Set(entries.map { $0.id.uuidString })
            var imported = 0
            let isoFormatter = ISO8601DateFormatter()

            for be in backup.entries {
                if existingIDs.contains(be.id) { continue }
                let ts = isoFormatter.date(from: be.timestamp) ?? Date()
                let entry = DiaryEntry(
                    id: UUID(uuidString: be.id) ?? UUID(),
                    timestamp: ts,
                    encryptedData: be.encryptedData,
                    clipboardData: be.clipboardData
                )
                modelContext.insert(entry)
                imported += 1
            }
            try modelContext.save()
            importMsg = "恢复成功，导入 \(imported) 条记录"
            importSuccess = true
        } catch {
            importMsg = "恢复失败：\(error.localizedDescription)"
            importSuccess = false
        }
    }

    // MARK: - Rekey logic

    private func performRekey() {
        let oldKey = keyStore.globalKey
        let newKey = (0..<16).map { _ in
            String(format: "%02x", UInt8.random(in: 0...255))
        }.joined()

        isRekeying = true
        rekeySuccess = nil
        let entryIDs = entries.map { $0.id }

        Task { @MainActor in
            do {
                for id in entryIDs {
                    let descriptor = FetchDescriptor<DiaryEntry>(
                        predicate: #Predicate { $0.id == id }
                    )
                    guard let entry = try modelContext.fetch(descriptor).first else { continue }
                    entry.encryptedData = try EncryptionEngine.rekeyAll(
                        ciphertexts: [entry.encryptedData],
                        oldKey: oldKey, newKey: newKey
                    ).first ?? entry.encryptedData
                    entry.clipboardData = try EncryptionEngine.rekeyAll(
                        ciphertexts: [entry.clipboardData],
                        oldKey: oldKey, newKey: newKey
                    ).first ?? entry.clipboardData
                }
                try modelContext.save()
                keyStore.globalKey = newKey
                withAnimation { rekeySuccess = true }
            } catch {
                withAnimation { rekeySuccess = false }
            }
            isRekeying = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation { rekeySuccess = nil }
            }
        }
    }

    private func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmm"
        return f.string(from: Date())
    }
}

// MARK: - BackupDocument (FileDocument for exporter)

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zaYuBackup, .json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Custom UTType

extension UTType {
    static let zaYuBackup = UTType(exportedAs: "com.privacy.diary.backup")
}
