import Foundation
import SwiftData

// DiaryEntry stores the full ciphertext (with media) locally,
// and a separate short text-only ciphertext safe for clipboard/wechat.

@Model
final class DiaryEntry {

    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var encryptedData: String    // full ciphertext (text + media) — local only
    var clipboardData: String    // text-only ciphertext — safe to copy anywhere

    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         encryptedData: String,
         clipboardData: String = "") {
        self.id = id
        self.timestamp = timestamp
        self.encryptedData = encryptedData
        // If no separate clipboard version provided, use full cipher
        self.clipboardData = clipboardData.isEmpty ? encryptedData : clipboardData
    }
}
