// MARK: - SmartPasteParser.swift
// 智能粘贴解析引擎
// 支持两种输入格式：
//   A. 完整客户行：姓名 电话 地址 [商品] 金额 身高/体重/年龄 [快递单号]
//   B. 流水记录行：姓名 转化类型 金额（仅三字段，不产生新客户）

import Foundation

// MARK: 解析后的单行结果（待用户确认）
struct ParsedRow: Identifiable {
    let id = UUID()
    let rawLine: String
    let rowIndex: Int

    // 解析出的字段
    var name: String
    var phone: String?
    var address: String?
    var amount: Double?
    var conversionType: ConversionType
    var age: Int?
    var height: Double?
    var weight: Double?
    var productNote: String?

    // 记录类型
    var dataType: CustomerDataType

    // 是否解析成功
    var isValid: Bool {
        !name.isEmpty && amount != nil
    }

    // 完整客户判定
    var isFullCustomer: Bool {
        dataType == .fullCustomer && phone != nil && !phone!.isEmpty
    }
}

// MARK: 解析失败行
struct ParseFailedRow: Identifiable {
    let id = UUID()
    let lineNumber: Int
    let rawLine: String
    let reason: String
}

// MARK: 主解析器
enum SmartPasteParser {

    // ── 正则预编译 ────────────────────────────────────────
    // 11位手机号
    private static let phonePattern = try! NSRegularExpression(
        pattern: #"(?<![0-9])1[3-9]\d{9}(?![0-9])"#
    )
    // 金额：数字（含小数），可跟"元/￥"
    private static let amountPattern = try! NSRegularExpression(
        pattern: #"(?<![0-9SF])(\d{2,6}(?:\.\d{1,2})?)\s*[元￥]?(?![0-9])"#
    )
    // 身高：100-220，可带cm/厘米
    private static let heightPattern = try! NSRegularExpression(
        pattern: #"身高\s*(\d{3})|(\d{3})\s*(?:cm|厘米)"#,
        options: .caseInsensitive
    )
    // 体重：30-150，可带kg/斤/公斤
    private static let weightPattern = try! NSRegularExpression(
        pattern: #"体重\s*(\d{2,3})|(\d{2,3})\s*(?:kg|斤|公斤)"#,
        options: .caseInsensitive
    )
    // 年龄：1-99，可带"年龄"前缀或"岁"后缀
    private static let agePattern = try! NSRegularExpression(
        pattern: #"年龄\s*(\d{1,3})|(\d{1,3})\s*岁"#
    )
    // 快递单号（SF/YT/ZT/JD开头+数字，排除）
    private static let trackingPattern = try! NSRegularExpression(
        pattern: #"(?:SF|YT|ZT|JD|EMS|顺丰|圆通)\d{8,20}"#,
        options: .caseInsensitive
    )
    // 纯流水记录识别：姓名+状态关键词+金额（无电话）
    private static let ledgerKeywords = ["新单","首单","二次","三次","四次","复购"]

    // 状态关键词映射
    private static let conversionKeywords: [(keys: [String], type: ConversionType)] = [
        (["四次","4次","第四"],            .fourth),
        (["三次","3次","第三"],            .third),
        (["二次","2次","第二","复购"],      .second),
        (["新单","首单","一次","1次","新"], .newOrder),
    ]

    // 地址特征词
    private static let addressKeywords = [
        "省","市","区","县","路","街","镇","乡","村","号","楼","室","单元",
        "广州","深圳","北京","上海","成都","武汉","南京","杭州","西安",
        "河南","广东","浙江","江苏","湖北","四川","山东","河北","辽宁",
        "吉林","黑龙江","新疆","云南","贵州","福建","陕西","重庆","天津"
    ]

    // MARK: 批量解析入口
    static func parse(_ text: String) -> (rows: [ParsedRow], failed: [ParseFailedRow]) {
        let normalized = normalize(text)
        let lines = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var rows:   [ParsedRow]       = []
        var failed: [ParseFailedRow]  = []

        for (i, line) in lines.enumerated() {
            if let row = parseLine(line, index: i) {
                rows.append(row)
            } else {
                failed.append(ParseFailedRow(
                    lineNumber: i + 1,
                    rawLine:    line,
                    reason:     "无法提取有效字段（需包含姓名和金额）"
                ))
            }
        }
        return (rows, failed)
    }

    // MARK: 单行解析
    private static func parseLine(_ line: String, index: Int) -> ParsedRow? {
        var remaining = line

        // 1. 先提取并移除快递单号（避免干扰数字提取）
        remaining = remove(pattern: trackingPattern, from: remaining)

        // 2. 提取手机号
        let phone = extractFirst(pattern: phonePattern, from: remaining)
        if phone != nil { remaining = remove(pattern: phonePattern, from: remaining) }

        // 3. 提取身高/体重/年龄（优先级高于普通数字）
        let height = extractBiometric(heightPattern, from: remaining, range: 100...220)
        let weight = extractBiometric(weightPattern, from: remaining, range: 30...150)
        let age    = extractBiometricInt(agePattern, from: remaining, range: 1...99)
        // 移除已解析的生理字段避免干扰
        remaining = remove(pattern: heightPattern, from: remaining)
        remaining = remove(pattern: weightPattern, from: remaining)
        remaining = remove(pattern: agePattern,    from: remaining)

        // 4. 提取金额（取最大值，通常是订单金额）
        let amount = extractAmount(from: remaining)

        // 5. 识别转化类型
        let (convType, convKeyword) = extractConversionType(from: remaining)

        // 6. 去除金额数字后，寻找地址（含地域特征词）
        let addressAndRest = extractAddress(from: remaining, convKeyword: convKeyword)
        let address  = addressAndRest.address
        let restText = addressAndRest.rest

        // 7. 剩余文本的第一个非空词视为姓名
        let name = extractName(from: restText, convKeyword: convKeyword)
        guard !name.isEmpty else { return nil }
        guard amount != nil else { return nil }

        // 8. 判断是流水还是完整客户
        let isLedger = phone == nil && isLedgerFormat(line)
        let dataType: CustomerDataType = isLedger ? .ledgerEntry : .fullCustomer

        // 9. 提取商品备注（含"+"符号的短语）
        let product = extractProduct(from: line)

        return ParsedRow(
            rawLine:        line,
            rowIndex:       index,
            name:           name,
            phone:          phone,
            address:        address,
            amount:         amount,
            conversionType: convType,
            age:            age,
            height:         height,
            weight:         weight,
            productNote:    product,
            dataType:       dataType
        )
    }

    // MARK: 辅助：判断是否为纯流水格式（无电话、含转化关键词）
    private static func isLedgerFormat(_ line: String) -> Bool {
        let hasConvKw = ledgerKeywords.contains(where: { line.contains($0) })
        let hasPhone  = phonePattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        return hasConvKw && !hasPhone
    }

    // MARK: 辅助：提取转化类型
    private static func extractConversionType(from s: String) -> (ConversionType, String?) {
        for entry in conversionKeywords {
            for kw in entry.keys {
                if s.contains(kw) { return (entry.type, kw) }
            }
        }
        return (.newOrder, nil)
    }

    // MARK: 辅助：提取金额（优先取3-5位的合理金额数字）
    private static func extractAmount(from s: String) -> Double? {
        let range = NSRange(s.startIndex..., in: s)
        let matches = amountPattern.matches(in: s, range: range)
        let candidates: [Double] = matches.compactMap { match -> Double? in
            guard let r = Range(match.range(at: 1), in: s) else { return nil }
            return Double(s[r])
        }
        // 优先 100-50000 范围的金额
        let reasonable = candidates.filter { $0 >= 50 && $0 <= 99999 }
        return reasonable.max() ?? candidates.first
    }

    // MARK: 辅助：提取地址（含地域特征词的最长分段）
    private static func extractAddress(from s: String, convKeyword: String?) -> (address: String?, rest: String) {
        // 按空格或中文标点分词
        var tokens = s.components(separatedBy: CharacterSet.whitespaces)
        if let kw = convKeyword {
            tokens = tokens.filter { !$0.contains(kw) }
        }
        // 移除纯数字 token（金额/手机号残留）
        tokens = tokens.filter {
            let digits = $0.filter { $0.isNumber }
            return digits.count < $0.count || digits.count < 4
        }
        // 找出含地址关键词的 token 合并为地址
        var addrTokens:    [String] = []
        var nonAddrTokens: [String] = []
        for tok in tokens {
            if addressKeywords.contains(where: { tok.contains($0) }) && tok.count > 2 {
                addrTokens.append(tok)
            } else {
                nonAddrTokens.append(tok)
            }
        }
        let address = addrTokens.isEmpty ? nil : addrTokens.joined(separator: "")
        let rest    = nonAddrTokens.joined(separator: " ")
        return (address, rest)
    }

    // MARK: 辅助：从剩余文本提取姓名（第一个 2-4 字短词）
    private static func extractName(from rest: String, convKeyword: String?) -> String {
        var tokens = rest
            .components(separatedBy: CharacterSet.whitespaces)
            .filter { !$0.isEmpty }
        if let kw = convKeyword { tokens = tokens.filter { !$0.contains(kw) } }
        // 排除纯数字
        tokens = tokens.filter { !$0.allSatisfy({ $0.isNumber }) }
        // 取最短的 2-6 字 token
        let candidate = tokens.filter { $0.count >= 2 && $0.count <= 6 }.first
            ?? tokens.first
        return candidate ?? ""
    }

    // MARK: 辅助：商品备注提取（"植物茶2+脂肪粉2" 这类含"+"的片段）
    private static func extractProduct(from s: String) -> String? {
        // 找含"+"的短词组
        let pattern = try! NSRegularExpression(pattern: #"[一-龥\w]+(?:\d*[+＋][一-龥\w]+\d*)+"#)
        let range = NSRange(s.startIndex..., in: s)
        guard let match = pattern.firstMatch(in: s, range: range),
              let r = Range(match.range, in: s) else { return nil }
        return String(s[r])
    }

    // MARK: 辅助：正则移除
    private static func remove(pattern: NSRegularExpression, from s: String) -> String {
        let range = NSRange(s.startIndex..., in: s)
        return pattern.stringByReplacingMatches(in: s, range: range, withTemplate: " ")
    }

    // MARK: 辅助：提取第一个匹配的字符串
    private static func extractFirst(pattern: NSRegularExpression, from s: String) -> String? {
        let range = NSRange(s.startIndex..., in: s)
        guard let match = pattern.firstMatch(in: s, range: range),
              let r = Range(match.range, in: s) else { return nil }
        return String(s[r])
    }

    // MARK: 辅助：从双捕获组的正则提取数字（身高/体重）
    private static func extractBiometric(_ pattern: NSRegularExpression,
                                         from s: String,
                                         range: ClosedRange<Double>) -> Double? {
        let nsRange = NSRange(s.startIndex..., in: s)
        guard let match = pattern.firstMatch(in: s, range: nsRange) else { return nil }
        for i in 1...2 {
            if let r = Range(match.range(at: i), in: s),
               let v = Double(s[r]), range.contains(v) {
                return v
            }
        }
        return nil
    }

    private static func extractBiometricInt(_ pattern: NSRegularExpression,
                                            from s: String,
                                            range: ClosedRange<Int>) -> Int? {
        guard let v = extractBiometric(pattern, from: s, range: Double(range.lowerBound)...Double(range.upperBound)) else { return nil }
        return Int(v)
    }

    // MARK: 辅助：文本标准化
    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\t",       with: " ")
    }
}
