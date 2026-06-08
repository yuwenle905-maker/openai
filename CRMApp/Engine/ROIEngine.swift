// MARK: - ROIEngine.swift
// ROI 与销售漏斗核心计算层

import Foundation

// MARK: 漏斗单级
struct FunnelStage: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
    let totalAmount: Double
    let conversionRate: Double
    let denominator: Int

    var conversionRateText: String {
        guard denominator > 0 else { return "—" }
        return String(format: "%.1f%%", conversionRate * 100)
    }
    var totalAmountText: String { String(format: "%.0f 元", totalAmount) }
}

// MARK: 期间汇总
struct PeriodSummary {
    let importedLeadCount: Int
    let leadUnitPrice: Double
    var totalCost: Double { Double(importedLeadCount) * leadUnitPrice }

    // 营业额 = 手动录入转化记录之和（不含 leadAmount）
    let totalRevenue: Double
    var roi: Double {
        guard totalCost > 0 else { return 0 }
        return totalRevenue / totalCost
    }
    var roiText: String { String(format: "%.2f", roi) }
    let funnelStages: [FunnelStage]
}

// MARK: 通用画像条目（地域/年龄/金额共用）
struct ProfileItem: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
    let percentage: Double
    // 下钻时用于过滤客户
    let filterKey: String

    var percentageText: String { String(format: "%.1f%%", percentage * 100) }
}

// MARK: ROI 引擎
enum ROIEngine {

    // MARK: 期间汇总
    static func summary(customers: [Customer], leadUnitPrice: Double) -> PeriodSummary {
        let leadCount    = customers.count
        // 营业额：只统计手动录入的 ConversionRecord.amount
        let totalRevenue = customers.flatMap { $0.conversions }.reduce(0) { $0 + $1.amount }
        let stages       = buildFunnel(customers: customers, totalLeads: leadCount)
        return PeriodSummary(
            importedLeadCount: leadCount,
            leadUnitPrice:     leadUnitPrice,
            totalRevenue:      totalRevenue,
            funnelStages:      stages
        )
    }

    // MARK: 漏斗
    private static func buildFunnel(customers: [Customer], totalLeads: Int) -> [FunnelStage] {
        let types: [(ConversionType, String)] = [
            (.newOrder, "新单"), (.second, "二次"), (.third, "三次"), (.fourth, "四次")
        ]
        var result:    [FunnelStage] = []
        var prevCount  = totalLeads
        for (type, label) in types {
            let matched = customers.filter { $0.conversions.contains { $0.type == type } }
            let count   = matched.count
            let amount  = matched.flatMap { $0.conversions.filter { $0.type == type } }
                                  .reduce(0) { $0 + $1.amount }
            let rate: Double = prevCount > 0 ? Double(count) / Double(prevCount) : 0
            result.append(FunnelStage(label: label, count: count,
                                      totalAmount: amount, conversionRate: rate,
                                      denominator: prevCount))
            prevCount = count
        }
        return result
    }

    // MARK: 七大地理区划（需求4）
    // filterKey 与 regionLabel(for:) 保持一致，供下钻使用
    private static let regionGroups: [(label: String, provinces: [String])] = [
        ("华南地区", ["广东","广州","深圳","珠海","佛山","东莞","中山","惠州","江门","肇庆","广西","海南","香港","澳门"]),
        ("华东地区", ["上海","江苏","南京","苏州","无锡","浙江","杭州","宁波","安徽","福建","厦门","江西","山东","台湾"]),
        ("华北地区", ["北京","天津","河北","山西","内蒙古","内蒙"]),
        ("华中地区", ["河南","郑州","湖北","武汉","湖南","长沙"]),
        ("东北地区", ["辽宁","沈阳","吉林","长春","黑龙江","哈尔滨"]),
        ("西南地区", ["重庆","四川","成都","贵州","云南","昆明","西藏"]),
        ("西北地区", ["陕西","西安","甘肃","青海","宁夏","新疆"]),
    ]

    /// 根据地址字符串返回所属大区 label
    static func regionLabel(for address: String?) -> String {
        guard let addr = address, !addr.isEmpty else { return "未知/其他" }
        for group in regionGroups {
            if group.provinces.contains(where: { addr.contains($0) }) {
                return group.label
            }
        }
        return "未知/其他"
    }

    static func regionProfiles(customers: [Customer]) -> [ProfileItem] {
        let total = customers.count
        guard total > 0 else { return [] }

        var counts: [String: Int] = [:]
        for c in customers {
            let label = regionLabel(for: c.address)
            counts[label, default: 0] += 1
        }

        // 按七大区顺序 + 未知
        var ordered: [String] = regionGroups.map { $0.label } + ["未知/其他"]
        return ordered.compactMap { label -> ProfileItem? in
            guard let count = counts[label], count > 0 else { return nil }
            return ProfileItem(label: label, count: count,
                               percentage: Double(count) / Double(total),
                               filterKey: label)
        }
    }

    // MARK: 年龄段（需求5）
    static func ageProfiles(customers: [Customer]) -> [ProfileItem] {
        let withAge = customers.compactMap { $0.age }
        let total   = withAge.count
        guard total > 0 else { return [] }

        let bands: [(String, ClosedRange<Int>)] = [
            ("20-30岁", 20...29),
            ("30-40岁", 30...39),
            ("40岁以上", 40...120),
            ("20岁以下", 1...19),
        ]
        return bands.compactMap { (label, range) in
            let count = withAge.filter { range.contains($0) }.count
            guard count > 0 else { return nil }
            return ProfileItem(label: label, count: count,
                               percentage: Double(count) / Double(total),
                               filterKey: label)
        }
    }

    // MARK: 线索金额分布（需求2：用 leadAmount，不用 conversions.amount）
    static func amountProfiles(customers: [Customer]) -> [ProfileItem] {
        // 只取有 leadAmount 的客户
        let amounts = customers.compactMap { $0.leadAmount }
        let total   = amounts.count
        guard total > 0 else { return [] }

        let bands: [(String, (Double) -> Bool)] = [
            ("300元以内",  { $0 <= 300 }),
            ("301-500元", { $0 > 300 && $0 <= 500 }),
            ("500元以上",  { $0 > 500 }),
        ]
        return bands.compactMap { (label, pred) in
            let count = amounts.filter(pred).count
            guard count > 0 else { return nil }
            return ProfileItem(label: label, count: count,
                               percentage: Double(count) / Double(total),
                               filterKey: label)
        }
    }
}
