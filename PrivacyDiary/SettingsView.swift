import SwiftUI
import SwiftData

// MARK: - KeyStore

final class KeyStore: ObservableObject {
    @Published var globalKey: String {
        didSet { UserDefaults.standard.set(globalKey, forKey: "diary_global_key") }
    }

    init() {
        // Use a fixed default key so the app works out of the box without setup
        let saved = UserDefaults.standard.string(forKey: "diary_global_key") ?? ""
        self.globalKey = saved.isEmpty ? "ZaYu_Default_2024" : saved
    }
}

// MARK: - SettingsView

struct SettingsView: View {

    @EnvironmentObject private var keyStore: KeyStore
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [DiaryEntry]

    @State private var isRekeying = false
    @State private var showConfirmRekey = false
    @State private var rekeySuccess: Bool? = nil
    @State private var copiedKey = false

    var body: some View {
        NavigationStack {
            Form {
                rekeySection
                infoSection
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
        }
    }

    // MARK: - 更换密钥 Section

    private var rekeySection: some View {
        Section {
            HStack {
                Text("一键刷新密钥")
                Spacer()
                // Result badge
                if let ok = rekeySuccess {
                    Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(ok ? .green : .red)
                        .transition(.scale.combined(with: .opacity))
                }
                // Refresh button
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
            Text("点击刷新按钮将随机生成新密钥并重新加密所有本地记录。密钥不对外显示。")
                .font(.caption)
        }
    }

    // MARK: - 数据库信息 Section

    private var infoSection: some View {
        Section {
            LabeledContent("本地条目数", value: "\(entries.count) 条")

            // Disguised key display — looks like a technical note, not a key
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("软件编码原理")
                        .font(.body)
                    Text(keyStore.globalKey)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = keyStore.globalKey
                    copiedKey = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedKey = false
                    }
                } label: {
                    Image(systemName: copiedKey ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(copiedKey ? .green : .secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Label("数据库信息", systemImage: "externaldrive.fill")
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

    // MARK: - 刷新密钥逻辑（随机生成新密钥）

    private func performRekey() {
        let oldKey = keyStore.globalKey
        // Generate a random 32-char hex key
        let newKey = (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()

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
                        oldKey: oldKey,
                        newKey: newKey
                    ).first ?? entry.encryptedData
                }
                try modelContext.save()
                keyStore.globalKey = newKey
                withAnimation { rekeySuccess = true }
            } catch {
                withAnimation { rekeySuccess = false }
            }
            isRekeying = false
            // Auto-clear badge after 3s
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation { rekeySuccess = nil }
            }
        }
    }
}
