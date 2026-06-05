import Foundation
import CryptoKit

// MARK: - EncryptionEngine
// Two-layer encryption: SHA-256 key-stream XOR + Fisher-Yates shuffled Base64 alphabet.
// Media (photo/video) is encrypted separately and never included in the clipboard ciphertext.

enum EncryptionError: Error {
    case base64DecodingFailed
    case utf8DecodingFailed
    case jsonSerializationFailed
    case jsonDeserializationFailed
}

// Text-only payload — safe to copy to clipboard (short)
struct TextPayload: Codable {
    let timestamp: String
    let text: String
}

// Full payload including media — stored locally only, never copied to clipboard
struct DiaryPayload: Codable {
    let timestamp: String
    let text: String
    let photo_base64: String
    let video_base64: String
}

struct EncryptionEngine {

    // MARK: - Encrypt text only (for clipboard)

    static func encryptText(
        text: String,
        key: String
    ) throws -> String {
        let payload = TextPayload(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            text: text
        )
        let jsonData = try JSONEncoder().encode(payload)
        return try encryptData(jsonData, key: key)
    }

    // MARK: - Encrypt full payload (for local storage)

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
        let jsonData = try JSONEncoder().encode(payload)
        return try encryptData(jsonData, key: key)
    }

    // MARK: - Decrypt

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

    // MARK: - Re-key

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

    // MARK: - Core encrypt/decrypt (operate on raw Data)

    static func encryptData(_ plainData: Data, key: String) throws -> String {
        let xored = xorWithKeyStream(data: plainData, key: key)
        let stdB64 = xored.base64EncodedData(options: [])
        let shuffled = translateAlphabet(data: stdB64,
                                         from: stdAlpha,
                                         to: buildCustomAlphabet(key: key))
        return String(bytes: shuffled, encoding: .ascii) ?? ""
    }

    static func decryptData(_ cipherText: String, key: String) throws -> Data {
        let cleaned = cipherText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines).joined()
        guard let cipherData = cleaned.data(using: .ascii) else {
            throw EncryptionError.base64DecodingFailed
        }
        let stdB64 = translateAlphabet(data: cipherData,
                                       from: buildCustomAlphabet(key: key),
                                       to: stdAlpha)
        guard let xored = Data(base64Encoded: stdB64, options: .ignoreUnknownCharacters) else {
            throw EncryptionError.base64DecodingFailed
        }
        return xorWithKeyStream(data: xored, key: key)
    }

    // MARK: - Key Stream

    private static func deriveKeyStream(key: String, length: Int) -> [UInt8] {
        var stream = [UInt8]()
        stream.reserveCapacity(length)
        let keyBytes = Array(key.utf8)
        var block = Array(SHA256.hash(data: Data(keyBytes)))
        while stream.count < length {
            stream.append(contentsOf: block)
            var combined = block
            combined.append(contentsOf: keyBytes)
            block = Array(SHA256.hash(data: Data(combined)))
        }
        return Array(stream.prefix(length))
    }

    private static func xorWithKeyStream(data: Data, key: String) -> Data {
        let keyStream = deriveKeyStream(key: key, length: data.count)
        return Data(data.enumerated().map { (i, byte) in byte ^ keyStream[i] })
    }

    // MARK: - Custom Base64 Alphabet

    private static let stdAlpha: [UInt8] = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8
    )

    private static func buildCustomAlphabet(key: String) -> [UInt8] {
        let md5 = Insecure.MD5.hash(data: Data(key.utf8))
        let seedBytes = Array(md5.prefix(8))
        var seedInt: UInt64 = 0
        for b in seedBytes { seedInt = seedInt &* 256 &+ UInt64(b) }

        var alpha = stdAlpha
        let a: UInt64 = (seedInt | 1)
        let c: UInt64 = 0x3039
        let m: UInt64 = 0x1_0000_0000
        var state = seedInt
        for i in stride(from: alpha.count - 1, through: 1, by: -1) {
            state = (a &* state &+ c) % m
            let j = Int(state) % (i + 1)
            alpha.swapAt(i, j)
        }
        return alpha
    }

    private static func translateAlphabet(data: Data, from src: [UInt8], to dst: [UInt8]) -> Data {
        var table = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 { table[i] = UInt8(i) }
        for (s, d) in zip(src, dst) { table[Int(s)] = d }
        return Data(data.map { table[Int($0)] })
    }
}
