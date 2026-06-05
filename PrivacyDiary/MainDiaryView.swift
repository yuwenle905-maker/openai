import SwiftUI
import SwiftData
import PhotosUI

// MARK: - MainDiaryView
// Encrypt-only tool: displays ciphertext list, long-press to copy.
// No decryption, no plaintext preview exists anywhere in this view.

struct MainDiaryView: View {

    @EnvironmentObject private var keyStore: KeyStore
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \DiaryEntry.timestamp, order: .reverse)
    private var entries: [DiaryEntry]

    @State private var showComposer = false
    @State private var selectedDate = Date()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                entryList
                addButton
            }
            .navigationTitle(formattedDate(selectedDate))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { datePicker }
        }
        .sheet(isPresented: $showComposer) {
            ComposerSheet(isPresented: $showComposer)
                .environmentObject(keyStore)
        }
    }

    // MARK: Date toolbar

    private var datePicker: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: date)
    }

    // MARK: Entry list

    private var entryList: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "暂无记录",
                    systemImage: "fish",
                    description: Text("点击右下角 + 号添加第一条记录")
                )
            } else {
                List {
                    ForEach(entries) { entry in
                        CiphertextRow(entry: entry)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onDelete(perform: deleteEntries)
                }
                .listStyle(.plain)
            }
        }
    }

    private func deleteEntries(at offsets: IndexSet) {
        for i in offsets { modelContext.delete(entries[i]) }
        try? modelContext.save()
    }

    // MARK: + button

    private var addButton: some View {
        Button {
            showComposer = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        }
        .padding(.trailing, 24)
        .padding(.bottom, 32)
    }
}

// MARK: - CiphertextRow
// Long-press to copy. No tap-to-expand. No decryption.

private struct CiphertextRow: View {

    let entry: DiaryEntry
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if copied {
                    Label("已复制", systemImage: "checkmark")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            }

            Text(entry.encryptedData)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .truncationMode(.tail)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contextMenu {
            Button {
                copyToClipboard()
            } label: {
                Label("复制密文", systemImage: "doc.on.doc")
            }
        }
        .onLongPressGesture {
            copyToClipboard()
        }
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = entry.encryptedData
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { copied = false }
        }
    }
}

// MARK: - ComposerSheet

struct ComposerSheet: View {

    @Binding var isPresented: Bool
    @EnvironmentObject private var keyStore: KeyStore
    @Environment(\.modelContext) private var modelContext

    @State private var text = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("写点什么…")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: { Text("内容") }

                Section {
                    PhotosPicker(
                        selection: $selectedPhotoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label(
                            selectedPhotoData != nil ? "照片已选中" : "添加照片",
                            systemImage: selectedPhotoData != nil
                                ? "photo.fill" : "photo.on.rectangle.angled"
                        )
                    }
                    .onChange(of: selectedPhotoItem) { _, item in
                        Task {
                            selectedPhotoData = try? await item?.loadTransferable(type: Data.self)
                        }
                    }

                    if selectedPhotoData != nil {
                        Button(role: .destructive) {
                            selectedPhotoData = nil
                            selectedPhotoItem = nil
                        } label: {
                            Label("移除照片", systemImage: "trash")
                        }
                    }
                } header: { Text("多媒体") }

                if let msg = errorMessage {
                    Section {
                        Text(msg).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("新建记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发表") { submit() }
                        .fontWeight(.semibold)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty
                                  || keyStore.globalKey.isEmpty
                                  || isSubmitting)
                }
            }
        }
    }

    private func submit() {
        let key = keyStore.globalKey
        guard !key.isEmpty else {
            errorMessage = "请先在设置中配置全局密钥。"
            return
        }
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                let photoB64 = selectedPhotoData?.base64EncodedString() ?? ""
                let cipher = try EncryptionEngine.encryptDiary(
                    text: text,
                    photoB64: photoB64,
                    videoB64: "",
                    key: key
                )
                await MainActor.run {
                    let entry = DiaryEntry(encryptedData: cipher)
                    modelContext.insert(entry)
                    try? modelContext.save()
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "加密失败：\(error.localizedDescription)"
                    isSubmitting = false
                }
            }
        }
    }
}
