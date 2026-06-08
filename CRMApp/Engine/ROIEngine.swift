// MARK: - ROIEngine.swift
// ROI 与销售漏斗核心计算层

import Foundation

// MARK: 漏斗单级统计
struct FunnelStage: Identifiable {
    let id = UUID()
    let label: String               // "新单"、"二次"...
    let count: Int                  // 该级别转化条数
    let totalAmount: Double         // 该级别总金额
    let conversionRate: Double      // 转化率（0-1）
    let denominator: Int            // 计算率时的分母（用于显示 "x/y"）

    var conversionRateText: String {
        guard denominator > 0 else { return "—" }
        return String(format: "%.1f%%", conversionRate * 100)
    }
    var totalAmountText: String {
        String(format: "%.0f 元", totalAmount)
    }
}

// MARK: 月度/年度汇总
struct PeriodSummary {
    let importedLeadCount: Int      // 导入数据总条数
    let leadUnitPrice: Double       // 数据单价
    var totalCost: Double {         // 总成本
        Double(importedLeadCount) * leadUnitPrice
    }
    let totalRevenue: Double        // 总营业额
    var roi: Double {               // ROI = 营业额 / 成本
        guard totalCost > 0 else { return 0 }
        return totalRevenue / totalCost
    }
    var roiText: String {
        String(format: "%.2f", roi)
    }
    let funnelStages: [FunnelStage]
}

// MARK: 地域画像
struct RegionProfile: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
    let percentage: Double
    var percentageText: String { String(format: "%.1f%%", percentage * 100) }
}

// MARK: 年龄段画像
struct AgeProfile: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
    let percentage: Double
    var percentageText: String { String(format: "%.1f%%", percentage * 100) }
}

// MARK: ROI 引擎
enum ROIEngine {

    // MARK: 计算期间汇总（月/年通用）
    static func summary(
        customers: [Customer],
        leadUnitPrice: Double
    ) -> PeriodSummary {

        let leadCount = customers.count

        // 所有转化记录展平
        let allConversions = customers.flatMap { $0.conversions }
        let totalRevenue   = allConversions.reduce(0) { $0 + $1.amount }

        // 漏斗计算
        let stages = buildFunnel(customers: customers, totalLeads: leadCount)

        return PeriodSummary(
            importedLeadCount: leadCount,
            leadUnitPrice: leadUnitPrice,
            totalRevenue: totalRevenue,
            funnelStages: stages
        )
    }

    // MARK: 漏斗构建
    /// 新单转化率 = 新单数 / 导入总条数
    /// 二次转化率 = 二次数 / 新单数
    /// 三次转化率 = 三次数 / 二次数
    private static func buildFunnel(
        customers: [Customer],
        totalLeads: Int
    ) -> [FunnelStage] {

        // 每个客户"最高转化层级"
        // 也支持单客户多条记录（时间轴），此处按类型分别统计
        let stages: [(ConversionType, String)] = [
            (.newOrder, "新单"),
            (.second,   "二次"),
            (.third,    "三次"),
            (.fourth,   "四次"),
        ]

        var result: [FunnelStage] = []
        var prevCount = totalLeads

        for (type, label) in stages {
            // 持有该类型转化记录的唯一客户数
            let matched = customers.filter { c in
                c.conversions.contains { $0.type == type }
            }
            let count = matched.count
            let amount = matched.flatMap { $0.conversions.filter { $0.type == type } }
                                .reduce(0) { $0 + $1.amount }

            let rate: Double = prevCount > 0 ? Double(count) / Double(prevCount) : 0

            result.append(FunnelStage(
                label: label,
                count: count,
                totalAmount: amount,
                conversionRate: rate,
                denominator: prevCount
            ))

            // 下一级的分母 = 本级命中数（若为0则后续漏斗无意义但仍展示）
            prevCount = count
        }
        return result
    }

    // MARK: 地域画像统计
    static func regionProfiles(customers: [Customer]) -> [RegionProfile] {
        let total = customers.count
        guard total > 0 else { return [] }

        let groups: [(String, [String])] = [
            ("珠三角", ["广州", "深圳", "珠海", "佛山", "东莞", "中山", "惠州", "江门", "肇庆"]),
            ("江浙沪", ["上海", "江苏", "浙江", "苏州", "南京", "杭州", "宁波", "无锡"]),
            ("东北地区", ["辽宁", "吉林", "黑龙江", "沈阳", "长春", "哈尔滨"]),
            ("北方地区", ["北京", "天津", "河北", "山东", "山西", "内蒙", "陕西", "河南"]),
            ("西部地区", ["四川", "重庆", "云南", "贵州", "西藏", "新疆", "甘肃", "青海", "宁夏"]),
        ]

        var profiles: [RegionProfile] = []
        var counted = 0

        for (name, keywords) in groups {
            let count = customers.filter { c in
                guard let addr = c.address else { return false }
                return keywords.contains(where: { addr.contains($0) })
            }.count
            counted += count
            profiles.append(RegionProfile(
                name: name,
                count: count,
                percentage: Double(count) / Double(total)
            ))
        }

        // 其他地区
        let other = total - counted
        profiles.append(RegionProfile(
            name: "其他地区",
            count: other,
            percentage: Double(other) / Double(total)
        ))
        return profiles.filter { $0.count > 0 }
    }

    // MARK: 年龄段画像统计
    static func ageProfiles(customers: [Customer]) -> [AgeProfile] {
        let withAge = customers.compactMap { $0.age }
        let total = withAge.count
        guard total > 0 else { return [] }

        let bands: [(String, ClosedRange<Int>)] = [
            ("20-30岁", 20...29),
            ("30-40岁", 30...39),
            ("40岁以上", 40...120),
            ("20岁以下", 1...19),
        ]
        return bands.map { (label, range) in
            let count = withAge.filter { range.contains($0) }.count
            return AgeProfile(
                label: label,
                count: count,
                percentage: Double(count) / Double(total)
            )
        }.filter { $0.count > 0 }
    }
}
