import SwiftUI
import PhotosUI
import SwiftData

// MARK: - MainDiaryView

struct MainDiaryView: View {

    @EnvironmentObject private var keyStore: KeyStore
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \DiaryEntry.timestamp, order: .reverse)
    private var entries: [DiaryEntry]

    // Composer state
    @State private var diaryText = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var selectedVideoURL: URL?

    // UI feedback
    @State private var showCopiedBanner = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    timestampHeader
                    textEditor
                    mediaRow
                    encryptCopyButton
                    Divider().padding(.top, 8)
                    entryList
                }
                .padding()
            }
            .navigationTitle("私密日记")
            .navigationBarTitleDisplayMode(.large)
            .alert("错误", isPresented: $showError) {
                Button("好的", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .overlay(alignment: .top) {
                if showCopiedBanner {
                    copiedBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: Subviews

    private var timestampHeader: some View {
        HStack {
            Image(systemName: "calendar.badge.clock")
                .foregroundStyle(.secondary)
            Text(Date(), style: .date)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Date(), style: .time)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var textEditor: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
            TextEditor(text: $diaryText)
                .frame(minHeight: 180)
                .padding(10)
                .scrollContentBackground(.hidden)
            if diaryText.isEmpty {
                Text("写下今天的故事…")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 18)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 180)
    }

    private var mediaRow: some View {
        HStack(spacing: 16) {
            // Photo picker
            PhotosPicker(selection: $selectedPhotoItem,
                         matching: .images,
                         photoLibrary: .shared()) {
                mediaButton(icon: "photo.on.rectangle.angled",
                            label: "添加照片",
                            active: selectedPhotoData != nil)
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    selectedPhotoData = try? await newItem?.loadTransferable(type: Data.self)
                }
            }

            // Video placeholder (file importer)
            Button {
                // Video picking handled via UIDocumentPickerViewController in production;
                // placeholder tap clears selection for prototype.
                selectedVideoURL = nil
            } label: {
                mediaButton(icon: "video.badge.plus",
                            label: selectedVideoURL != nil ? "已选视频" : "添加视频",
                            active: selectedVideoURL != nil)
            }

            Spacer()

            // Clear media
            if selectedPhotoData != nil || selectedVideoURL != nil {
                Button(role: .destructive) {
                    selectedPhotoData = nil
                    selectedVideoURL = nil
                    selectedPhotoItem = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red.opacity(0.8))
                }
            }
        }
    }

    private func mediaButton(icon: String, label: String, active: Bool) -> some View {
        Label(label, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(active ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemBackground))
            .foregroundStyle(active ? .accent : .secondary)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(active ? Color.accentColor.opacity(0.4) : .clear,
                                            lineWidth: 1))
    }

    private var encryptCopyButton: some View {
        Button(action: encryptAndCopy) {
            HStack(spacing: 10) {
                Image(systemName: "lock.doc.fill")
                Text("一键伪装并复制")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [.indigo, .purple],
                               startPoint: .leading,
                               endPoint: .trailing)
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .purple.opacity(0.35), radius: 8, y: 4)
        }
        .disabled(diaryText.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var copiedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
            Text("密文已复制到剪贴板")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 8)
    }

    private var entryList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !entries.isEmpty {
                Text("历史记录")
                    .font(.headline)
                    .padding(.bottom, 2)
            }
            ForEach(entries) { entry in
                DiaryRowView(entry: entry, key: keyStore.globalKey)
            }
        }
    }

    // MARK: Actions

    private func encryptAndCopy() {
        let photoB64 = selectedPhotoData.map { $0.base64EncodedString() } ?? ""
        let key = keyStore.globalKey
        guard !key.isEmpty else {
            errorMessage = "请先在设置中配置全局密钥。"
            showError = true
            return
        }
        do {
            let cipher = try EncryptionEngine.encryptDiary(
                text: diaryText,
                photoB64: photoB64,
                videoB64: "",
                key: key
            )
            // Persist to SwiftData
            let entry = DiaryEntry(encryptedData: cipher)
            modelContext.insert(entry)
            try? modelContext.save()

            // Copy to clipboard
            UIPasteboard.general.string = cipher

            // Clear composer
            diaryText = ""
            selectedPhotoData = nil
            selectedPhotoItem = nil

            withAnimation(.spring(response: 0.4)) { showCopiedBanner = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation { showCopiedBanner = false }
            }
        } catch {
            errorMessage = "加密失败：\(error.localizedDescription)"
            showError = true
        }
    }
}

// MARK: - DiaryRowView

private struct DiaryRowView: View {

    let entry: DiaryEntry
    let key: String

    @State private var preview: String = "（点击解密预览）"
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.timestamp, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if isExpanded {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .padding(.top, 2)
            } else {
                Text(entry.encryptedData.prefix(60) + "…")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            if !isExpanded {
                decryptPreview()
            }
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
        }
    }

    private func decryptPreview() {
        guard !key.isEmpty else { preview = "未设置密钥"; return }
        do {
            let payload = try entry.decrypt(key: key)
            preview = payload.text
        } catch {
            preview = "解密失败，请检查密钥。"
        }
    }
}
