import SwiftUI
import SwiftData

// MARK: - KeyStore  (shared observable state)

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

    // Secure field visibility
    @State private var showCurrentKey = false
    @State private var showNewKey = false

    enum RekeyResult: Equatable {
        case success(count: Int)
        case failure(message: String)
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
            .alert("确认更新密钥", isPresented: $showConfirmRekey) {
                confirmRekeyAlert
            } message: {
                Text("这将用新密钥重新加密本地所有 \(entries.count) 条日记。\n操作不可撤销，请确保已记住新密钥。")
            }
            .overlay {
                if isRekeying {
                    rekeyProgressOverlay
                }
            }
        }
        .onAppear { pendingNewKey = keyStore.globalKey }
        .onChange(of: rekeyResult) { _, result in
            guard let result else { return }
            switch result {
            case .success: break
            case .failure: break
            }
        }
    }

    // MARK: Sections

    private var currentKeySection: some View {
        Section {
            HStack {
                Group {
                    if showCurrentKey {
                        TextField("输入当前密钥", text: $keyStore.globalKey)
                    } else {
                        SecureField("输入当前密钥", text: $keyStore.globalKey)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button {
                    showCurrentKey.toggle()
                } label: {
                    Image(systemName: showCurrentKey ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            keyStrengthMeter(key: keyStore.globalKey)

        } header: {
            Label("全局加密密钥", systemImage: "key.fill")
        } footer: {
            Text("此密钥用于加密和解密所有日记条目。请妥善保管，遗失后数据不可恢复。")
                .font(.caption)
        }
    }

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

                Button {
                    showNewKey.toggle()
                } label: {
                    Image(systemName: showNewKey ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            keyStrengthMeter(key: pendingNewKey)

            Button(action: { showConfirmRekey = true }) {
                HStack {
                    Spacer()
                    Label("一键更新所有密文", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.body.weight(.semibold))
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .tint(.orange)
            .disabled(pendingNewKey.trimmingCharacters(in: .whitespaces).isEmpty
                      || pendingNewKey == keyStore.globalKey
                      || entries.isEmpty)

            if let result = rekeyResult {
                rekeyResultRow(result: result)
            }

        } header: {
            Label("更换密钥", systemImage: "arrow.triangle.2.circlepath")
        } footer: {
            Text("输入新密钥后点击【一键更新】，App 将在本地自动完成所有历史密文的解密与重加密，旧密文将被覆盖。")
                .font(.caption)
        }
    }

    private var infoSection: some View {
        Section {
            LabeledContent("本地条目数", value: "\(entries.count) 条")
            LabeledContent("加密算法", value: "SHA-256 密钥流 XOR + 自定义 Base64")
            LabeledContent("存储方式", value: "SwiftData（沙盒本地）")
        } header: {
            Label("数据库信息", systemImage: "externaldrive.fill")
        }
    }

    // MARK: Alert Buttons

    @ViewBuilder
    private var confirmRekeyAlert: some View {
        Button("取消", role: .cancel) {}
        Button("确认更新", role: .destructive) {
            performRekey()
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func keyStrengthMeter(key: String) -> some View {
        let strength = passwordStrength(key)
        HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i < strength.level ? strength.color : Color(.systemFill))
                    .frame(height: 4)
            }
            Text(strength.label)
                .font(.caption2)
                .foregroundStyle(strength.color)
        }
    }

    private struct KeyStrength {
        let level: Int      // 0-4
        let label: String
        let color: Color
    }

    private func passwordStrength(_ key: String) -> KeyStrength {
        var score = 0
        if key.count >= 8 { score += 1 }
        if key.count >= 14 { score += 1 }
        if key.rangeOfCharacter(from: .decimalDigits) != nil { score += 1 }
        if key.rangeOfCharacter(from: CharacterSet.letters.inverted
            .intersection(.decimalDigits.inverted)) != nil { score += 1 }
        switch score {
        case 0: return KeyStrength(level: 0, label: "未设置", color: .gray)
        case 1: return KeyStrength(level: 1, label: "弱", color: .red)
        case 2: return KeyStrength(level: 2, label: "一般", color: .orange)
        case 3: return KeyStrength(level: 3, label: "较强", color: .yellow)
        default: return KeyStrength(level: 4, label: "强", color: .green)
        }
    }

    @ViewBuilder
    private func rekeyResultRow(result: RekeyResult) -> some View {
        switch result {
        case .success(let count):
            Label("成功更新 \(count) 条密文", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.subheadline)
        case .failure(let msg):
            Label("更新失败：\(msg)", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.subheadline)
        }
    }

    private var rekeyProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.4)
                    .tint(.white)
                Text("正在重加密所有日记…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    // MARK: Rekey Logic

    private func performRekey() {
        let oldKey = keyStore.globalKey
        let newKey = pendingNewKey
        isRekeying = true
        rekeyResult = nil

        Task {
            do {
                // Re-encrypt every entry in the SwiftData context
                var count = 0
                for entry in entries {
                    let newCipher = try EncryptionEngine.rekeyAll(
                        ciphertexts: [entry.encryptedData],
                        oldKey: oldKey,
                        newKey: newKey
                    ).first ?? entry.encryptedData
                    entry.encryptedData = newCipher
                    count += 1
                }
                try modelContext.save()

                await MainActor.run {
                    keyStore.globalKey = newKey
                    pendingNewKey = newKey
                    rekeyResult = .success(count: count)
                    isRekeying = false
                }
            } catch {
                await MainActor.run {
                    rekeyResult = .failure(message: error.localizedDescription)
                    isRekeying = false
                }
            }
        }
    }
}
