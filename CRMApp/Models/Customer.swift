// MARK: - Customer.swift
// 核心数据模型

import Foundation

// MARK: 客户记录类型
enum CustomerDataType: String, Codable {
    case fullCustomer  // 完整客户：含姓名+电话+地址，计入客户总数
    case ledgerEntry   // 流水/跟进记录：仅含姓名+转化类型+金额，不新增客户
}

// MARK: 转化状态
enum ConversionType: String, Codable, CaseIterable {
    case newOrder = "新单"
    case second   = "二次"
    case third    = "三次"
    case fourth   = "四次"
    case fifth    = "五次"
    case sixth    = "六次"
    case seventh  = "七次"
    case eighth   = "八次"
    case unknown  = "未知"
}

// MARK: 去重处理策略
enum DuplicateResolution {
    case overwrite
    case skip
    case merge
}

// MARK: 转化/消费记录（生命周期时间轴）
struct ConversionRecord: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var type: ConversionType
    var amount: Double       // 手动录入的成交金额（计入营业额）
    var date: Date
    var productNote: String?
    var note: String?

    init(type: ConversionType, amount: Double,
         date: Date = Date(), productNote: String? = nil, note: String? = nil) {
        self.type        = type
        self.amount      = amount
        self.date        = date
        self.productNote = productNote
        self.note        = note
    }
}

// MARK: 主客户模型
struct Customer: Identifiable, Codable, Equatable {

    var id: UUID = UUID()
    var dataType: CustomerDataType = .fullCustomer

    // 基础资料
    var name: String
    var phone: String
    var address: String?
    var age: Int?
    var height: Double?
    var weight: Double?
    var gender: String = "未知"
    var customerNumber: String?   // 手动录入的客户编号，系统不自动生成

    // 线索金额（智能导入时提取，仅用于画像统计，不计入营业额）
    var leadAmount: Double?

    // 历史单价留存（需求2）
    // 入库时自动固化当时的 AppSettings.leadUnitPrice，之后改价不影响此值
    var lineCost: Double

    // 来源
    var importBatchID: UUID?
    var importDate: Date

    // 标签
    var tags: [String] = []

    // 转化/消费记录（手动录入，金额计入营业额）
    var conversions: [ConversionRecord] = []

    // MARK: 计算属性

    /// 营业额 = 手动录入转化记录之和（不含 leadAmount）
    var totalRevenue: Double {
        conversions.reduce(0) { $0 + $1.amount }
    }

    var importDayKey: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: importDate)
    }

    var importDayDisplay: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "M月d日"
        return fmt.string(from: importDate)
    }

    init(name: String, phone: String,
         address: String?        = nil,
         age: Int?               = nil,
         height: Double?         = nil,
         weight: Double?         = nil,
         gender: String          = "未知",
         customerNumber: String? = nil,
         leadAmount: Double?     = nil,
         lineCost: Double        = 1200,
         dataType: CustomerDataType = .fullCustomer,
         importBatchID: UUID?    = nil,
         importDate: Date        = Date(),
         conversions: [ConversionRecord] = []) {
        self.name           = name
        self.phone          = phone
        self.address        = address
        self.age            = age
        self.height         = height
        self.weight         = weight
        self.gender         = gender
        self.customerNumber = customerNumber
        self.leadAmount     = leadAmount
        self.lineCost       = lineCost
        self.dataType       = dataType
        self.importBatchID  = importBatchID
        self.importDate     = importDate
        self.conversions    = conversions
    }
}

// MARK: 导入批次
struct ImportBatch: Identifiable, Codable {
    var id: UUID = UUID()
    var source: String
    var importDate: Date
    var recordCount: Int
    var fullCustomerCount: Int

    var displayHeader: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "M月d日 HH:mm"
        return "\(fmt.string(from: importDate))  |  \(recordCount) 条"
    }

    var yearKey:  String { "\(Calendar.current.component(.year, from: importDate))年" }
    var monthKey: String {
        let c = Calendar.current.dateComponents([.year, .month], from: importDate)
        return "\(c.year!)年\(c.month!)月"
    }
}
