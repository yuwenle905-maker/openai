// MARK: - DataStore.swift
// 本地数据仓库 — 内存 + JSON 持久化（可替换为 GRDB）

import Foundation
import Combine

// MARK: - AppSettings（全局配置）
class AppSettings: ObservableObject, Codable {

    // ROI 数据单价（默认 1200 元/条）
    @Published var leadUnitPrice: Double = 1200

    // Face ID / 密码锁开关
    @Published var biometricLockEnabled: Bool = false

    // 密码锁（PIN，4-6位）
    @Published var appPINEnabled: Bool = false
    @Published var appPIN: String = ""          // 存储时应 hash，此处简化

    // ── Codable 手动实现（@Published 无法自动合成） ──────────
    enum CodingKeys: String, CodingKey {
        case leadUnitPrice, biometricLockEnabled, appPINEnabled, appPIN
    }
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        leadUnitPrice       = try c.decodeIfPresent(Double.self, forKey: .leadUnitPrice)       ?? 1200
        biometricLockEnabled = try c.decodeIfPresent(Bool.self,  forKey: .biometricLockEnabled) ?? false
        appPINEnabled       = try c.decodeIfPresent(Bool.self,   forKey: .appPINEnabled)       ?? false
        appPIN              = try c.decodeIfPresent(String.self,  forKey: .appPIN)              ?? ""
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(leadUnitPrice,        forKey: .leadUnitPrice)
        try c.encode(biometricLockEnabled, forKey: .biometricLockEnabled)
        try c.encode(appPINEnabled,        forKey: .appPINEnabled)
        try c.encode(appPIN,              forKey: .appPIN)
    }
    init() {}
}

// MARK: - DataStore
class DataStore: ObservableObject {

    // ── 持久化路径 ─────────────────────────────────────────
    private static let customersURL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("customers.json")
    private static let batchesURL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("batches.json")
    private static let settingsURL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("settings.json")

    // ── 内存状态 ───────────────────────────────────────────
    @Published var customers: [Customer]     = []
    @Published var batches:   [ImportBatch]  = []
    @Published var settings:  AppSettings    = AppSettings()

    init() { load() }

    // MARK: 持久化读写
    func load() {
        customers = decode([Customer].self, from: DataStore.customersURL) ?? []
        batches   = decode([ImportBatch].self, from: DataStore.batchesURL) ?? []
        settings  = decode(AppSettings.self, from: DataStore.settingsURL) ?? AppSettings()
    }

    func save() {
        encode(customers, to: DataStore.customersURL)
        encode(batches,   to: DataStore.batchesURL)
        encode(settings,  to: DataStore.settingsURL)
    }

    // MARK: 去重检测 — 返回已存在的客户（按电话匹配）
    func findExisting(phone: String) -> Customer? {
        customers.first { $0.phone == phone }
    }

    // MARK: 应用去重策略
    /// 传入新数据与选定策略，执行写入
    @discardableResult
    func applyDuplicateResolution(
        existing: inout Customer,
        incoming: Customer,
        resolution: DuplicateResolution
    ) -> Bool {
        switch resolution {
        case .overwrite:
            if let idx = customers.firstIndex(where: { $0.phone == existing.phone }) {
                customers[idx] = incoming
                existing = incoming
            }
            save()
            return true

        case .skip:
            return false

        case .merge:
            if let idx = customers.firstIndex(where: { $0.phone == existing.phone }) {
                // 保留基础资料，追加转化记录
                let newConversions = incoming.conversions.filter { newRec in
                    !customers[idx].conversions.contains(where: { $0.id == newRec.id })
                }
                customers[idx].conversions.append(contentsOf: newConversions)
                existing = customers[idx]
            }
            save()
            return true
        }
    }

    // MARK: 添加新客户（无冲突）
    func addCustomer(_ customer: Customer) {
        customers.append(customer)
        save()
    }

    // MARK: 添加导入批次
    func addBatch(_ batch: ImportBatch) {
        batches.append(batch)
        save()
    }

    // MARK: 更新客户（手动补录后调用）
    func updateCustomer(_ customer: Customer) {
        if let idx = customers.firstIndex(where: { $0.id == customer.id }) {
            customers[idx] = customer
            save()
        }
    }

    // MARK: - 月度数据过滤
    func customers(inYear year: Int, month: Int) -> [Customer] {
        let cal = Calendar.current
        return customers.filter {
            let comps = cal.dateComponents([.year, .month], from: $0.importDate)
            return comps.year == year && comps.month == month
        }
    }

    func customers(inYear year: Int) -> [Customer] {
        let cal = Calendar.current
        return customers.filter {
            cal.component(.year, from: $0.importDate) == year
        }
    }

    // MARK: - 私有：Codable 辅助
    private func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomicWrite)
    }
}
