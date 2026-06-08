// MARK: - DataStore.swift
// 本地数据仓库 — 内存 + JSON 持久化

import Foundation
import Combine

// MARK: - AppSettings
class AppSettings: ObservableObject, Codable {

    @Published var leadUnitPrice:        Double = 1200
    @Published var biometricLockEnabled: Bool   = false
    @Published var appPINEnabled:        Bool   = false
    @Published var appPIN:               String = ""

    enum CodingKeys: String, CodingKey {
        case leadUnitPrice, biometricLockEnabled, appPINEnabled, appPIN
    }
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        leadUnitPrice        = try c.decodeIfPresent(Double.self, forKey: .leadUnitPrice)        ?? 1200
        biometricLockEnabled = try c.decodeIfPresent(Bool.self,   forKey: .biometricLockEnabled) ?? false
        appPINEnabled        = try c.decodeIfPresent(Bool.self,   forKey: .appPINEnabled)        ?? false
        appPIN               = try c.decodeIfPresent(String.self, forKey: .appPIN)               ?? ""
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(leadUnitPrice,        forKey: .leadUnitPrice)
        try c.encode(biometricLockEnabled, forKey: .biometricLockEnabled)
        try c.encode(appPINEnabled,        forKey: .appPINEnabled)
        try c.encode(appPIN,               forKey: .appPIN)
    }
    init() {}
}

// MARK: - DataStore
class DataStore: ObservableObject {

    private static let customersURL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("customers_v2.json")
    private static let batchesURL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("batches_v2.json")
    private static let settingsURL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("settings.json")

    @Published var customers: [Customer]    = []
    @Published var batches:   [ImportBatch] = []
    @Published var settings:  AppSettings   = AppSettings()

    init() { load() }

    // MARK: 持久化
    func load() {
        customers = decode([Customer].self, from: DataStore.customersURL)    ?? []
        batches   = decode([ImportBatch].self, from: DataStore.batchesURL)   ?? []
        settings  = decode(AppSettings.self, from: DataStore.settingsURL)    ?? AppSettings()
    }

    func save() {
        encode(customers, to: DataStore.customersURL)
        encode(batches,   to: DataStore.batchesURL)
        encode(settings,  to: DataStore.settingsURL)
    }

    // MARK: 客户统计（仅计完整客户）
    var fullCustomerCount: Int {
        customers.filter { $0.dataType == .fullCustomer }.count
    }

    // MARK: 去重检测
    func findExisting(phone: String) -> Customer? {
        customers.first { $0.phone == phone }
    }

    // MARK: 去重处理
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

    // MARK: 增删改
    func addCustomer(_ customer: Customer) {
        customers.append(customer)
        save()
    }

    func addBatch(_ batch: ImportBatch) {
        batches.append(batch)
        save()
    }

    func updateCustomer(_ customer: Customer) {
        if let idx = customers.firstIndex(where: { $0.id == customer.id }) {
            customers[idx] = customer
            save()
        }
    }

    // MARK: 月度/年度过滤（仅完整客户）
    func customers(inYear year: Int, month: Int) -> [Customer] {
        let cal = Calendar.current
        return customers.filter {
            guard $0.dataType == .fullCustomer else { return false }
            let comps = cal.dateComponents([.year, .month], from: $0.importDate)
            return comps.year == year && comps.month == month
        }
    }

    func customers(inYear year: Int) -> [Customer] {
        let cal = Calendar.current
        return customers.filter {
            guard $0.dataType == .fullCustomer else { return false }
            return cal.component(.year, from: $0.importDate) == year
        }
    }

    // MARK: Codable 辅助
    private func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomicWrite)
    }
}
