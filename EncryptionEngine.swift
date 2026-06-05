import Foundation
import CryptoKit

// MARK: - EncryptionEngine
// Algorithm: SHA-256 key-stream XOR  +  Fisher-Yates shuffled Base64 alphabet
// Compatible with diary_core.py Phase-1 prototype.

enum EncryptionError: Error {
    case base64DecodingFailed
    case utf8DecodingFailed
    case jsonSerializationFailed
    case jsonDeserializationFailed
}

struct DiaryPayload: Codable {
    let timestamp: String
    let text: String
    let photo_base64: String
    let video_base64: String
}

struct EncryptionEngine {

    // MARK: Public API

    /// Encrypt a diary entry into an obfuscated ciphertext string.
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
        let xored = xorWithKeyStream(data: jsonData, key: key)
        let stdB64 = xored.base64EncodedData()
        let shuffled = translateAlphabet(data: stdB64,
                                         from: stdAlpha,
                                         to: buildCustomAlphabet(key: key))
        return String(bytes: shuffled, encoding: .ascii) ?? ""
    }

    /// Decrypt a ciphertext string back to a DiaryPayload.
    static func decryptDiary(cipherText: String, key: String) throws -> DiaryPayload {
        guard let cipherData = cipherText.data(using: .ascii) else {
            throw EncryptionError.base64DecodingFailed
        }
        let stdB64 = translateAlphabet(data: cipherData,
                                       from: buildCustomAlphabet(key: key),
                                       to: stdAlpha)
        guard let xored = Data(base64Encoded: stdB64) else {
            throw EncryptionError.base64DecodingFailed
        }
        let plainData = xorWithKeyStream(data: xored, key: key)
        return try JSONDecoder().decode(DiaryPayload.self, from: plainData)
    }

    /// Re-encrypt a list of ciphertexts from oldKey to newKey.
    static func rekeyAll(
        ciphertexts: [String],
        oldKey: String,
        newKey: String
    ) throws -> [String] {
        try ciphertexts.map { ct in
            let payload = try decryptDiary(cipherText: ct, key: oldKey)
            return try encryptDiary(
                text: payload.text,
                photoB64: payload.photo_base64,
                videoB64: payload.video_base64,
                key: newKey
            )
        }
    }

    // MARK: - Key Stream (SHA-256 chaining)

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
        let bytes = data.enumerated().map { (i, byte) in byte ^ keyStream[i] }
        return Data(bytes)
    }

    // MARK: - Custom Base64 Alphabet (Fisher-Yates + LCG seeded by MD5)

    // Standard Base64 alphabet as ASCII bytes
    private static let stdAlpha: [UInt8] = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8
    )

    private static func buildCustomAlphabet(key: String) -> [UInt8] {
        // Seed from first 8 bytes of MD5(key) interpreted as UInt64
        let md5 = Insecure.MD5.hash(data: Data(key.utf8))
        let seedBytes = Array(md5.prefix(8))
        var seedInt: UInt64 = 0
        for b in seedBytes {
            seedInt = seedInt &* 256 &+ UInt64(b)
        }

        var alpha = stdAlpha
        // LCG params matching Python prototype
        let a: UInt64 = (seedInt | 1)
        let c: UInt64 = 0x3039
        let m: UInt64 = 0x1_0000_0000   // 2^32
        var state = seedInt

        for i in stride(from: alpha.count - 1, through: 1, by: -1) {
            state = (a &* state &+ c) % m
            let j = Int(state) % (i + 1)
            alpha.swapAt(i, j)
        }
        return alpha
    }

    // MARK: - Alphabet Translation

    private static func translateAlphabet(
        data: Data,
        from src: [UInt8],
        to dst: [UInt8]
    ) -> Data {
        // Build lookup table
        var table = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 { table[i] = UInt8(i) }   // identity
        for (s, d) in zip(src, dst) { table[Int(s)] = d }

        return Data(data.map { table[Int($0)] })
    }
}
