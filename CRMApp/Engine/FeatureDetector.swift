// MARK: - FeatureDetector.swift
// 特征值盲切算法 — 自动识别单元格语义

import Foundation

// MARK: 识别结果枚举
enum CellFeature {
    case phone(String)          // 11位 1开头纯数字
    case address(String)        // 含地域关键词
    case age(Int)               // 整数 1-120
    case height(Double)         // 100-220（cm）
    case weight(Double)         // 30-150（kg）
    case name(String)           // 兜底：视为姓名
    case unknown(String)        // 无法判定
}

// MARK: 一行解析结果（供弹窗使用）
struct RowParseResult {
    var name: String?
    var phone: String?
    var address: String?
    var age: Int?
    var height: Double?
    var weight: Double?

    // 缺失关键字段时为 true，触发 showingEditSheet
    var needsManualReview: Bool {
        return age == nil || height == nil || weight == nil
    }

    // 最低可入库要求：姓名 + 电话均不能为空
    var isMinimallyValid: Bool {
        return name != nil && phone != nil
    }
}

// MARK: 主解析器
enum FeatureDetector {

    // ── 地域关键词白名单 ───────────────────────────────────
    private static let addressKeywords: [String] = [
        "省", "市", "区", "县", "路", "街", "镇", "乡", "村",
        "广东", "北京", "上海", "浙江", "江苏", "福建", "湖南",
        "湖北", "四川", "重庆", "山东", "河南", "河北", "陕西",
        "辽宁", "吉林", "黑龙江", "广州", "深圳", "珠海", "佛山",
        "东莞", "中山", "惠州", "杭州", "南京", "苏州", "成都",
        "武汉", "长沙", "西安", "沈阳", "哈尔滨", "长春"
    ]

    // ── 身高/体重单位剥离正则 ─────────────────────────────
    private static let numericPattern = try! NSRegularExpression(
        pattern: #"^\s*(\d+(?:\.\d+)?)\s*(?:cm|厘米|kg|公斤|斤|岁)?\s*$"#,
        options: .caseInsensitive
    )

    /// 对单个单元格字符串进行语义推断
    static func detect(_ raw: String) -> CellFeature {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return .unknown(s) }

        // 1. 电话：11位数字 + 以1开头
        if isPhone(s) { return .phone(s) }

        // 2. 地址：含地域关键词
        if isAddress(s) { return .address(s) }

        // 3. 尝试提取数值
        if let value = extractNumericValue(from: s) {
            let hasHeightUnit = s.contains("cm") || s.contains("厘米")
            let hasWeightUnit = s.contains("kg") || s.contains("公斤") || s.contains("斤")
            let hasAgeUnit    = s.contains("岁")
            let isInteger     = value == Double(Int(value))

            // 有明确单位时直接判定，不走区间歧义
            if hasHeightUnit, value >= 100, value <= 220 { return .height(value) }
            if hasWeightUnit, value >= 30,  value <= 150 { return .weight(value) }
            if hasAgeUnit,    value >= 1,   value <= 120, isInteger { return .age(Int(value)) }

            // 无单位时按区间互斥优先级判定：
            //   1-29  → 仅年龄范围
            //  30-99  → 年龄与体重重叠，优先年龄（整数）；非整数优先体重
            // 100-120 → 年龄/身高/体重三重叠，优先身高（最常见量纲）
            // 121-150 → 身高与体重重叠，优先身高
            // 151-220 → 仅身高范围
            if value >= 1   && value <= 29  && isInteger { return .age(Int(value)) }
            if value >= 30  && value <= 99  && isInteger { return .age(Int(value)) }
            if value >= 30  && value <= 99              { return .weight(value) }
            if value >= 100 && value <= 220             { return .height(value) }
            if value >= 30  && value <= 150             { return .weight(value) }
        }

        // 4. 兜底：视为姓名/文本
        return .name(s)
    }

    // MARK: 整行解析（无表头模式）
    /// 将一行的所有 cell 映射到 RowParseResult
    static func parseRow(_ cells: [String]) -> RowParseResult {
        var result = RowParseResult()
        for cell in cells {
            switch detect(cell) {
            case .phone(let v)   where result.phone == nil:   result.phone   = v
            case .address(let v) where result.address == nil: result.address = v
            case .age(let v)     where result.age == nil:     result.age     = v
            case .height(let v)  where result.height == nil:  result.height  = v
            case .weight(let v)  where result.weight == nil:  result.weight  = v
            case .name(let v)    where result.name == nil:    result.name    = v
            default: break
            }
        }
        return result
    }

    // MARK: 有表头模式 — 模糊映射列名
    /// 返回列索引 → 语义键的字典，供逐行解析
    static func mapHeaders(_ headers: [String]) -> [Int: String] {
        var mapping: [Int: String] = [:]
        let nameKeywords    = ["姓名", "名字", "联系人", "用户名"]
        let phoneKeywords   = ["电话", "手机", "联系方式", "手机号", "号码"]
        let addressKeywords = ["地址", "住址", "所在地", "城市", "省份"]
        let ageKeywords     = ["年龄", "岁"]
        let heightKeywords  = ["身高", "cm", "厘米"]
        let weightKeywords  = ["体重", "kg", "公斤", "斤"]

        for (i, header) in headers.enumerated() {
            let h = header.trimmingCharacters(in: .whitespaces)
            if nameKeywords.contains(where: { h.contains($0) })    { mapping[i] = "name"    }
            else if phoneKeywords.contains(where: { h.contains($0) }) { mapping[i] = "phone"   }
            else if addressKeywords.contains(where: { h.contains($0) }) { mapping[i] = "address" }
            else if ageKeywords.contains(where: { h.contains($0) })    { mapping[i] = "age"     }
            else if heightKeywords.contains(where: { h.contains($0) }) { mapping[i] = "height"  }
            else if weightKeywords.contains(where: { h.contains($0) }) { mapping[i] = "weight"  }
        }
        return mapping
    }

    // MARK: 私有辅助
    private static func isPhone(_ s: String) -> Bool {
        let digits = s.filter { $0.isNumber }
        return digits.count == 11 && digits.hasPrefix("1") && digits == s
    }

    private static func isAddress(_ s: String) -> Bool {
        return addressKeywords.contains(where: { s.contains($0) })
    }

    private static func extractNumericValue(from s: String) -> Double? {
        let range = NSRange(s.startIndex..., in: s)
        guard let match = numericPattern.firstMatch(in: s, range: range),
              let r = Range(match.range(at: 1), in: s)
        else { return nil }
        return Double(s[r])
    }
}
