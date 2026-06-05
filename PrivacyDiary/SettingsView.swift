import SwiftUI
import SwiftData

// MARK: - KeyStore

final class KeyStore: ObservableObject {
    @Published var globalKey: String {
        didSet { UserDefaults.standard.set(globalKey, forKey: "diary_global_key") }
    }

    init() {
        self.globalKey = UserDefaults.standard.string(forKey: "diary_global_key") ?? ""
    }
}

// MARK: - SettingsView

struct SettingsView: View {

    @EnvironmentObject private var keyStore: KeyStore
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [DiaryEntry]

    @State private var pendingNewKey = ""
    @State private var isRekeying = false
    @State private var showConfirmRekey = false
    @State private var rekeyResult: RekeyResult?
    @State private var showCurrentKey = false
    @State private var showNewKey = false

    enum RekeyResult: Equatable {
        case success(count: Int)
        case failure(message: String)
    }

    // "一键更新"可用条件：新密钥非空、与当前密钥不同
    // 注意：不再要求 entries 非空，让用户随时可以更换密钥
    private var canRekey: Bool {
        let trimmed = pendingNewKey.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed != keyStore.globalKey
    }

    var body: some View {
        NavigationStack {
            Form {
                currentKeySection
                rekeySection
                infoSection
            }
            .navigationTitle("安全设置")
            .navigationBarTitleDisplayMode(.large)
            .alert("确认更换密钥", isPresented: $showConfirmRekey) {
                Button("取消", role: .cancel) {}
                Button("确认更新", role: .destructive) { performRekey() }
            } message: {
                Text("将用新密钥重新加密本地 \(entries.count) 条日记，操作不可撤销。")
            }
            .overlay {
                if isRekeying { rekeyProgressOverlay }
            }
        }
        .onAppear {
            // 首次进入时用当前全局密钥预填新密钥框，方便用户对比修改
            if pendingNewKey.isEmpty {
                pendingNewKey = keyStore.globalKey
            }
        }
    }

    // MARK: - 当前密钥 Section

    private var currentKeySection: some View {
        Section {
            HStack {
                Group {
                    if showCurrentKey {
                        TextField("尚未设置密钥", text: $keyStore.globalKey)
                    } else {
                        SecureField("尚未设置密钥", text: $keyStore.globalKey)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)

                Button {
                    showCurrentKey.toggle()
                } label: {
                    Image(systemName: showCurrentKey ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            strengthBar(key: keyStore.globalKey)

        } header: {
            Label("全局加密密钥", systemImage: "key.fill")
        } footer: {
            Text("所有日记均用此密钥加密，请妥善保管。遗失后数据无法恢复。")
                .font(.caption)
        }
    }

    // MARK: - 更换密钥 Section

    private var rekeySection: some View {
        Section {
            HStack {
                Group {
                    if showNewKey {
                        TextField("输入新密钥", text: $pendingNewKey)
                    } else {
                        SecureField("输入新密钥", text: $pendingNewKey)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)

                Button {
                    showNewKey.toggle()
                } label: {
                    Image(systemName: showNewKey ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            strengthBar(key: pendingNewKey)

            Button {
                showConfirmRekey = true
            } label: {
                HStack {
                    Spacer()
                    Label("一键更新所有密文", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.body.weight(.semibold))
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .tint(.orange)
            .disabled(!canRekey || isRekeying)

            if let result = rekeyResult {
                rekeyResultRow(result)
            }

        } header: {
            Label("更换密钥", systemImage: "arrow.triangle.2.circlepath")
        } footer: {
            Text("输入新密钥后点击【一键更新】，App 将用新密钥重新加密本地所有历史日记。")
                .font(.caption)
        }
    }

    // MARK: - 数据库信息 Section

    private var infoSection: some View {
        Section {
            LabeledContent("本地条目数", value: "\(entries.count) 条")
            LabeledContent("加密算法", value: "SHA-256 密钥流 XOR + 自定义 Base64")
            LabeledContent("存储方式", value: "SwiftData（沙盒本地）")
        } header: {
            Label("数据库信息", systemImage: "externaldrive.fill")
        }
    }

    // MARK: - 密钥强度条

    @ViewBuilder
    private func strengthBar(key: String) -> some View {
        let s = strength(key)
        HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i < s.level ? s.color : Color(.systemFill))
                    .frame(height: 4)
            }
            Text(s.label)
                .font(.caption2)
                .foregroundStyle(s.color)
        }
    }

    private struct Strength { let level: Int; let label: String; let color: Color }

    private func strength(_ key: String) -> Strength {
        var score = 0
        if key.count >= 8  { score += 1 }
        if key.count >= 14 { score += 1 }
        if key.rangeOfCharacter(from: .decimalDigits) != nil { score += 1 }
        if key.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil { score += 1 }
        switch score {
        case 0:  return Strength(level: 0, label: "未设置", color: .gray)
        case 1:  return Strength(level: 1, label: "弱",     color: .red)
        case 2:  return Strength(level: 2, label: "一般",   color: .orange)
        case 3:  return Strength(level: 3, label: "较强",   color: .yellow)
        default: return Strength(level: 4, label: "强",     color: .green)
        }
    }

    // MARK: - 结果行

    @ViewBuilder
    private func rekeyResultRow(_ result: RekeyResult) -> some View {
        switch result {
        case .success(let count):
            Label("成功更新 \(count) 条密文", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.subheadline)
        case .failure(let msg):
            Label("更新失败：\(msg)", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red).font(.subheadline)
        }
    }

    // MARK: - 进度遮罩

    private var rekeyProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().scaleEffect(1.4).tint(.white)
                Text("正在重加密所有日记…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    // MARK: - 重加密逻辑

    private func performRekey() {
        let oldKey = keyStore.globalKey
        let newKey = pendingNewKey.trimmingCharacters(in: .whitespaces)
        guard !newKey.isEmpty, newKey != oldKey else { return }

        isRekeying = true
        rekeyResult = nil

        // Snapshot entry IDs on main thread before entering Task
        let entryIDs = entries.map { $0.id }

        Task { @MainActor in
            do {
                var count = 0
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
                    count += 1
                }
                try modelContext.save()
                keyStore.globalKey = newKey
                rekeyResult = .success(count: count)
            } catch {
                rekeyResult = .failure(message: error.localizedDescription)
            }
            isRekeying = false
        }
    }
}
