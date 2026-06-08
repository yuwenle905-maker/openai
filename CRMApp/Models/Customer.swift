// MARK: - Customer.swift
// 客户数据模型 — 核心实体

import Foundation

// MARK: 转化状态枚举
enum ConversionType: String, Codable, CaseIterable {
    case newOrder   = "新单"
    case second     = "二次"
    case third      = "三次"
    case fourth     = "四次"
    case unknown    = "未知"
}

// MARK: 去重冲突处理策略
enum DuplicateResolution {
    case overwrite  // 整行覆盖
    case skip       // 跳过
    case merge      // 保留基础资料，追加转化记录
}

// MARK: 转化记录（一对多：一个客户可有多条）
struct ConversionRecord: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var type: ConversionType
    var amount: Double          // 成交金额（元）
    var date: Date
    var note: String?

    init(type: ConversionType, amount: Double, date: Date = Date(), note: String? = nil) {
        self.type   = type
        self.amount = amount
        self.date   = date
        self.note   = note
    }
}

// MARK: 主客户模型
struct Customer: Identifiable, Codable, Equatable {

    // ── 基础字段 ──────────────────────────────────────────
    var id: UUID = UUID()
    var name: String
    var phone: String           // 11 位，唯一键
    var address: String?
    var age: Int?               // 1-120
    var height: Double?         // 100-220 cm
    var weight: Double?         // 30-150 kg

    // ── 来源信息 ──────────────────────────────────────────
    var importBatchID: UUID?    // 对应 ImportBatch.id
    var importDate: Date

    // ── 标签系统（可扩展） ────────────────────────────────
    var tags: [String]

    // ── 转化记录（生命周期时间轴） ─────────────────────────
    var conversions: [ConversionRecord]

    // MARK: 便捷计算属性
    var totalRevenue: Double {
        conversions.reduce(0) { $0 + $1.amount }
    }

    var latestConversion: ConversionRecord? {
        conversions.sorted { $0.date > $1.date }.first
    }

    // MARK: 初始化
    init(
        name: String,
        phone: String,
        address: String?       = nil,
        age: Int?              = nil,
        height: Double?        = nil,
        weight: Double?        = nil,
        importBatchID: UUID?   = nil,
        importDate: Date       = Date(),
        tags: [String]         = [],
        conversions: [ConversionRecord] = []
    ) {
        self.name          = name
        self.phone         = phone
        self.address       = address
        self.age           = age
        self.height        = height
        self.weight        = weight
        self.importBatchID = importBatchID
        self.importDate    = importDate
        self.tags          = tags
        self.conversions   = conversions
    }
}

// MARK: - ImportBatch（导入批次）
/// 对应树状视图中 年份 → 月份 → 每次导入文件块
struct ImportBatch: Identifiable, Codable {
    var id: UUID = UUID()
    var fileName: String
    var importDate: Date
    var recordCount: Int        // 该批次成功导入条数

    var yearMonth: String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: importDate)
        return "\(comps.year ?? 0)年\(comps.month ?? 0)月"
    }
}
