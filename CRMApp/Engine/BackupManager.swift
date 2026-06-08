// MARK: - BackupManager.swift
// 一键加密备份与恢复接口

import Foundation
import CryptoKit   // iOS 13+ 原生，AES-256-GCM

// MARK: 备份载荷（完整快照）
struct BackupPayload: Codable {
    let version: Int            // 备份格式版本号，未来用于迁移
    let exportDate: Date
    let customers: [Customer]
    let batches:   [ImportBatch]
    let settings:  AppSettings

    static let currentVersion = 1
}

// MARK: 备份错误
enum BackupError: LocalizedError {
    case encryptionFailed(String)
    case decryptionFailed(String)
    case invalidData
    case wrongPassword

    var errorDescription: String? {
        switch self {
        case .encryptionFailed(let r): return "加密失败：\(r)"
        case .decryptionFailed(let r): return "解密失败：\(r)"
        case .invalidData:             return "备份文件损坏或格式不匹配"
        case .wrongPassword:           return "密码错误，无法解密"
        }
    }
}

// MARK: BackupManager
enum BackupManager {

    // MARK: 导出 — 生成加密 JSON 数据流
    /// - Parameters:
    ///   - store:    当前 DataStore
    ///   - password: 用户设定的备份密码（UTF-8 → SHA-256 → AES-256-GCM key）
    /// - Returns:    可直接写文件或分享的 Data（格式：nonce[12B] + tag[16B] + ciphertext）
    static func export(store: DataStore, password: String) throws -> Data {
        let payload = BackupPayload(
            version:   BackupPayload.currentVersion,
            exportDate: Date(),
            customers: store.customers,
            batches:   store.batches,
            settings:  store.settings
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting   = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        let plaintext: Data
        do {
            plaintext = try encoder.encode(payload)
        } catch {
            throw BackupError.encryptionFailed("JSON 序列化失败：\(error.localizedDescription)")
        }

        let key = deriveKey(from: password)
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.seal(plaintext, using: key)
        } catch {
            throw BackupError.encryptionFailed(error.localizedDescription)
        }

        guard let combined = sealedBox.combined else {
            throw BackupError.encryptionFailed("无法合并加密数据")
        }
        return combined
    }

    // MARK: 导入 — 解密并还原
    /// - Parameters:
    ///   - data:     从文件或分享中读取的 Data
    ///   - password: 用户输入的备份密码
    ///   - store:    目标 DataStore（恢复后覆盖写入）
    static func `import`(data: Data, password: String, into store: DataStore) throws {
        let key = deriveKey(from: password)

        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(combined: data)
        } catch {
            throw BackupError.invalidData
        }

        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw BackupError.wrongPassword
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let payload: BackupPayload
        do {
            payload = try decoder.decode(BackupPayload.self, from: plaintext)
        } catch {
            throw BackupError.decryptionFailed("JSON 反序列化失败：\(error.localizedDescription)")
        }

        // 还原到 DataStore
        DispatchQueue.main.async {
            store.customers = payload.customers
            store.batches   = payload.batches
            store.settings  = payload.settings
            store.save()
        }
    }

    // MARK: 纯 JSON 导出（不加密，用于调试）
    static func exportPlainJSON(store: DataStore) throws -> String {
        let payload = BackupPayload(
            version:    BackupPayload.currentVersion,
            exportDate: Date(),
            customers:  store.customers,
            batches:    store.batches,
            settings:   store.settings
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting    = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: 私有：密码 → AES-256 密钥（HKDF via SHA-256）
    private static func deriveKey(from password: String) -> SymmetricKey {
        let passwordData = Data(password.utf8)
        // 使用固定 salt（生产环境建议随机 salt 并存入备份头）
        let salt = Data("CRMApp_AES256_Salt_v1".utf8)
        let inputKeyMaterial = SymmetricKey(data: SHA256.hash(data: passwordData))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKeyMaterial,
            salt: salt,
            outputByteCount: 32
        )
    }
}
