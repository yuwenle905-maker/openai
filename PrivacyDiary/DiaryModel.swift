import Foundation
import SwiftData

// DiaryEntry stores ONLY the ciphertext and its creation timestamp.
// No decryption logic exists in this model — the app is a one-way encryption tool.

@Model
final class DiaryEntry {

    @Attribute(.unique) var id: UUID
    var timestamp: Date       // plaintext timestamp for display/sorting only
    var encryptedData: String // opaque Base64 ciphertext — never decoded in-app

    init(id: UUID = UUID(), timestamp: Date = Date(), encryptedData: String) {
        self.id = id
        self.timestamp = timestamp
        self.encryptedData = encryptedData
    }
}
