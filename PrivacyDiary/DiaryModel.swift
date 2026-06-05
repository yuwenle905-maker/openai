import Foundation
import SwiftData

// MARK: - DiaryEntry  (SwiftData model)
// Stores only the timestamp in plaintext; all diary content lives in
// encryptedData as a single opaque Base64 ciphertext blob.

@Model
final class DiaryEntry {

    @Attribute(.unique) var id: UUID
    var timestamp: Date          // plaintext — used for sorting/display
    var encryptedData: String    // full ciphertext from EncryptionEngine

    init(id: UUID = UUID(), timestamp: Date = Date(), encryptedData: String) {
        self.id = id
        self.timestamp = timestamp
        self.encryptedData = encryptedData
    }

    /// Convenience: decrypt and return the payload using the supplied key.
    func decrypt(key: String) throws -> DiaryPayload {
        try EncryptionEngine.decryptDiary(cipherText: encryptedData, key: key)
    }
}

// MARK: - DiaryStore  (SwiftData container helper)

@MainActor
final class DiaryStore: ObservableObject {

    let container: ModelContainer

    init() {
        let schema = Schema([DiaryEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    // MARK: CRUD

    func insert(entry: DiaryEntry) {
        container.mainContext.insert(entry)
        try? container.mainContext.save()
    }

    func delete(entry: DiaryEntry) {
        container.mainContext.delete(entry)
        try? container.mainContext.save()
    }

    func fetchAll() throws -> [DiaryEntry] {
        let descriptor = FetchDescriptor<DiaryEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try container.mainContext.fetch(descriptor)
    }

    // MARK: Re-key

    /// Decrypt every entry with oldKey, re-encrypt with newKey, save in place.
    func rekeyAll(oldKey: String, newKey: String) throws {
        let entries = try fetchAll()
        for entry in entries {
            let newCipher = try EncryptionEngine.rekeyAll(
                ciphertexts: [entry.encryptedData],
                oldKey: oldKey,
                newKey: newKey
            ).first ?? entry.encryptedData
            entry.encryptedData = newCipher
        }
        try container.mainContext.save()
    }
}
