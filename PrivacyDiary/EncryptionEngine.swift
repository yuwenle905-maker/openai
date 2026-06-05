import Foundation
import CryptoKit

// MARK: - EncryptionEngine
// Algorithm: AES-256-GCM (CryptoKit)
// Key derivation: SHA-256(keyString) → 256-bit SymmetricKey
// Wire format: Base64(nonce[12] || ciphertext || tag[16])

enum EncryptionError: Error {
    case base64DecodingFailed
    case utf8DecodingFailed
    case jsonSerializationFailed
    case jsonDeserializationFailed
    case invalidCiphertextLength
}

// Text-only payload — for clipboard (short, WeChat-safe)
struct TextPayload: Codable {
    let timestamp: String
    let text: String
}

// Full payload — stored locally, includes media
struct DiaryPayload: Codable {
    let timestamp: String
    let text: String
    let photo_base64: String
    let video_base64: String
}

struct EncryptionEngine {

    // MARK: - Public API

    /// Encrypt text only (for clipboard — no media).
    static func encryptText(text: String, key: String) throws -> String {
        let payload = TextPayload(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            text: text
        )
        return try encryptData(JSONEncoder().encode(payload), key: key)
    }

    /// Encrypt full diary entry including media (for local storage).
    static func encryptDiary(
        text: String,
        photoB64: String = "",
        videoB64: String = "",
        key: String
    ) throws -> String {
        let payload = DiaryPayload(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            text: text,
            photo_base64: photoB64,
            video_base64: videoB64
        )
        return try encryptData(JSONEncoder().encode(payload), key: key)
    }

    /// Decrypt any ciphertext back to DiaryPayload.
    static func decryptDiary(cipherText: String, key: String) throws -> DiaryPayload {
        let data = try decryptData(cipherText, key: key)
        // Try full payload first, fall back to text-only
        if let full = try? JSONDecoder().decode(DiaryPayload.self, from: data) {
            return full
        }
        let text = try JSONDecoder().decode(TextPayload.self, from: data)
        return DiaryPayload(timestamp: text.timestamp, text: text.text,
                            photo_base64: "", video_base64: "")
    }

    /// Re-encrypt a list of ciphertexts from oldKey to newKey.
    static func rekeyAll(
        ciphertexts: [String],
        oldKey: String,
        newKey: String
    ) throws -> [String] {
        try ciphertexts.map { ct in
            let data = try decryptData(ct, key: oldKey)
            return try encryptData(data, key: newKey)
        }
    }

    // MARK: - Core AES-256-GCM

    static func encryptData(_ plainData: Data, key: String) throws -> String {
        let symKey = symmetricKey(from: key)
        let sealed = try AES.GCM.seal(plainData, using: symKey)
        // Pack: nonce(12) + ciphertext + tag(16)
        var combined = Data()
        combined.append(contentsOf: sealed.nonce)
        combined.append(sealed.ciphertext)
        combined.append(sealed.tag)
        return combined.base64EncodedString()
    }

    static func decryptData(_ cipherText: String, key: String) throws -> Data {
        let cleaned = cipherText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines).joined()
        guard let combined = Data(base64Encoded: cleaned) else {
            throw EncryptionError.base64DecodingFailed
        }
        // Minimum: 12 (nonce) + 0 (ciphertext) + 16 (tag) = 28 bytes
        guard combined.count >= 28 else {
            throw EncryptionError.invalidCiphertextLength
        }
        let nonce      = try AES.GCM.Nonce(data: combined.prefix(12))
        let ciphertext = combined.dropFirst(12).dropLast(16)
        let tag        = combined.suffix(16)
        let box        = try AES.GCM.SealedBox(nonce: nonce,
                                               ciphertext: ciphertext,
                                               tag: tag)
        return try AES.GCM.open(box, using: symmetricKey(from: key))
    }

    // MARK: - Key Derivation

    private static func symmetricKey(from keyString: String) -> SymmetricKey {
        let hash = SHA256.hash(data: Data(keyString.utf8))
        return SymmetricKey(data: hash)
    }
}
