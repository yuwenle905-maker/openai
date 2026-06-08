// MARK: - SmartPasteParser.swift
// 智能粘贴解析引擎 v2
//
// 核心改进：
//   1. 客户块切分：先把整段文本切成"客户块"，每块对应一个客户
//      切分规则：检测到手机号 → 开始新块；空行也作为分隔符
//   2. 块内合并：同一客户的分段长文（姓名/电话/地址各占一行）
//      在块内拼成单行后统一解析
//   3. 金额只存 leadAmount（不写入 ConversionRecord，不计营业额）

import Foundation

// MARK: 解析结果
struct ParsedRow: Identifiable {
    let id = UUID()
    let rawLine: String      // 原始合并文本（供预览）
    let rowIndex: Int

    var name:           String
    var phone:          String?
    var address:        String?
    var leadAmount:     Double?       // 线索金额，仅用于画像，不计营业额
    var conversionType: ConversionType
    var age:            Int?
    var height:         Double?
    var weight:         Double?
    var productNote:    String?
    var dataType:       CustomerDataType

    var isValid:        Bool { !name.isEmpty }
    var isFullCustomer: Bool { dataType == .fullCustomer && phone != nil }
}

// MARK: 解析失败行
struct ParseFailedRow: Identifiable {
    let id = UUID()
    let lineNumber: Int
    let rawLine:    String
    let reason:     String
}

// MARK: 主解析器
enum SmartPasteParser {

    // ── 正则（预编译）────────────────────────────────────────
    private static let phoneRx = try! NSRegularExpression(
        pattern: #"(?<![0-9])1[3-9]\d{9}(?![0-9])"#
    )
    private static let amountRx = try! NSRegularExpression(
        // 匹配 2-6 位数字（含小数），排除快递单号数字
        pattern: #"(?<![0-9A-Za-z])(\d{2,6}(?:\.\d{1,2})?)(?:\s*[元￥])?(?![0-9])"#
    )
    private static let heightRx = try! NSRegularExpression(
        pattern: #"身高\s*(\d{2,3})|(\d{2,3})\s*(?:cm|厘米)"#,
        options: .caseInsensitive
    )
    private static let weightRx = try! NSRegularExpression(
        pattern: #"体重\s*(\d{2,3})|(\d{2,3})\s*(?:kg|斤|公斤)"#,
        options: .caseInsensitive
    )
    private static let ageRx = try! NSRegularExpression(
        pattern: #"年龄\s*(\d{1,3})|(\d{1,3})\s*岁"#
    )
    private static let trackingRx = try! NSRegularExpression(
        // 快递单号：字母前缀 + 8-20位数字
        pattern: #"[A-Za-z]{2,4}\d{8,20}"#
    )
    private static let productRx = try! NSRegularExpression(
        pattern: #"[一-龥\w]+(?:\d*[+＋][一-龥\w]+\d*)+"#
    )

    // 流水关键词（无电话 + 含这些词 → ledgerEntry）
    private static let ledgerKeywords = ["新单","首单","二次","三次","四次","复购"]

    // 转化类型优先级表
    private static let convKwTable: [(keys: [String], type: ConversionType)] = [
        (["四次","4次","第四"],             .fourth),
        (["三次","3次","第三"],             .third),
        (["二次","2次","第二","复购"],       .second),
        (["新单","首单","一次","1次","新"],  .newOrder),
    ]

    // 地址特征词（用于识别哪些 token 属于地址）
    private static let addrKeywords = [
        "省","市","区","县","路","街","镇","乡","村","号","楼","室","单元","巷","弄",
        "广东","广西","海南","上海","江苏","浙江","安徽","福建","江西","山东","台湾",
        "北京","天津","河北","山西","内蒙","内蒙古","辽宁","吉林","黑龙江",
        "河南","湖北","湖南","重庆","四川","贵州","云南","西藏",
        "陕西","甘肃","青海","宁夏","新疆","香港","澳门",
        "广州","深圳","珠海","佛山","东莞","中山","惠州",
        "南京","杭州","苏州","宁波","无锡","武汉","成都","西安","沈阳","长春","哈尔滨"
    ]

    // MARK: ─── 公开入口 ─────────────────────────────────────

    static func parse(_ text: String) -> (rows: [ParsedRow], failed: [ParseFailedRow]) {
        // 第一步：文本标准化
        let cleaned = normalizeText(text)

        // 第二步：切分成客户块
        let blocks = splitIntoCustomerBlocks(cleaned)

        var rows:   [ParsedRow]      = []
        var failed: [ParseFailedRow] = []

        for (i, block) in blocks.enumerated() {
            if let row = parseBlock(block, index: i) {
                rows.append(row)
            } else {
                failed.append(ParseFailedRow(
                    lineNumber: i + 1,
                    rawLine:    block,
                    reason:     "无法提取有效字段（需包含姓名；线索金额可选）"
                ))
            }
        }
        return (rows, failed)
    }

    // MARK: ─── 第一步：文本标准化 ────────────────────────────

    private static func normalizeText(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r",   with: "\n")
            .replacingOccurrences(of: "\u{3000}", with: " ")   // 全角空格
            .replacingOccurrences(of: "\u{00A0}", with: " ")   // 不间断空格
            .replacingOccurrences(of: "\u{2003}", with: " ")   // Em Space
            .replacingOccurrences(of: "\t",        with: " ")  // Tab
    }

    // MARK: ─── 第二步：切分客户块 ────────────────────────────
    //
    // 策略：
    //   - 空行 → 强制分隔（不同客户）
    //   - 检测到手机号所在行 → 该行是新客户的锚点；
    //     若前若干行没有手机号，它们与该行合并为同一块
    //   - 若整段无空行且无手机号 → 按行切，每行一块

    private static func splitIntoCustomerBlocks(_ text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var blocks:      [String] = []
        var currentLines: [String] = []

        for line in lines {
            let isEmpty = line.isEmpty

            if isEmpty {
                // 空行 → 当前块结束
                if !currentLines.isEmpty {
                    blocks.append(currentLines.joined(separator: " "))
                    currentLines = []
                }
                continue
            }

            let hasPhone = containsPhone(line)

            if hasPhone && !currentLines.isEmpty {
                // 当前行含手机号，且已有积累行：
                // 若积累行里已有手机号，说明是新客户 → 提交旧块，开新块
                // 若积累行里无手机号，说明是同一客户的上文 → 合并入当前块
                let accHasPhone = currentLines.contains(where: { containsPhone($0) })
                if accHasPhone {
                    blocks.append(currentLines.joined(separator: " "))
                    currentLines = [line]
                } else {
                    currentLines.append(line)
                }
            } else {
                currentLines.append(line)
            }
        }

        // 收尾
        if !currentLines.isEmpty {
            blocks.append(currentLines.joined(separator: " "))
        }

        // 后备：若没切出多块（整段无空行无手机号），按行切
        if blocks.count == 1 && text.contains("\n") {
            let fallback = text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if fallback.count > 1 { return fallback }
        }

        return blocks.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func containsPhone(_ s: String) -> Bool {
        let range = NSRange(s.startIndex..., in: s)
        return phoneRx.firstMatch(in: s, range: range) != nil
    }

    // MARK: ─── 第三步：解析单个客户块 ────────────────────────

    private static func parseBlock(_ raw: String, index: Int) -> ParsedRow? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        // 移除快递单号（避免干扰数字提取）
        s = removePattern(trackingRx, from: s)

        // 提取 & 移除手机号
        let phone = firstMatch(phoneRx, in: s)
        s = removePattern(phoneRx, from: s)

        // 提取 & 移除身高/体重/年龄
        let height = extractNumeric(heightRx, from: s, range: 100...220)
        let weight = extractNumeric(weightRx, from: s, range: 30...150)
        let age    = extractNumericInt(ageRx,    from: s, range: 1...99)
        s = removePattern(heightRx, from: s)
        s = removePattern(weightRx, from: s)
        s = removePattern(ageRx,    from: s)

        // 提取商品备注（含"+"的组合词）
        let product = firstMatch(productRx, in: raw)

        // 提取金额（线索金额，不计营业额）
        let amount = extractBestAmount(from: s)

        // 提取转化类型
        let (convType, convKw) = detectConvType(in: s)

        // 提取地址
        let (address, rest) = extractAddrAndRest(from: s, removeKw: convKw)

        // 提取姓名
        let name = extractName(from: rest, removeKw: convKw)
        guard !name.isEmpty else { return nil }

        // 判断类型：无电话 + 含流水关键词 → ledgerEntry
        let isLedger = phone == nil && ledgerKeywords.contains(where: { raw.contains($0) })
        let dataType: CustomerDataType = isLedger ? .ledgerEntry : .fullCustomer

        return ParsedRow(
            rawLine:        raw,
            rowIndex:       index,
            name:           name,
            phone:          phone,
            address:        address,
            leadAmount:     amount,
            conversionType: convType,
            age:            age,
            height:         height,
            weight:         weight,
            productNote:    product,
            dataType:       dataType
        )
    }

    // MARK: ─── 辅助：金额提取 ────────────────────────────────

    private static func extractBestAmount(from s: String) -> Double? {
        let range = NSRange(s.startIndex..., in: s)
        let matches = amountRx.matches(in: s, range: range)
        let candidates: [Double] = matches.compactMap { m -> Double? in
            guard let r = Range(m.range(at: 1), in: s) else { return nil }
            return Double(s[r])
        }
        // 优先返回 50-99999 范围内最大值（过滤年龄/身高等小数字残留）
        let sane = candidates.filter { $0 >= 50 && $0 <= 99999 }
        return sane.max() ?? candidates.first
    }

    // MARK: ─── 辅助：转化类型 ────────────────────────────────

    private static func detectConvType(in s: String) -> (ConversionType, String?) {
        for entry in convKwTable {
            for kw in entry.keys {
                if s.contains(kw) { return (entry.type, kw) }
            }
        }
        return (.newOrder, nil)
    }

    // MARK: ─── 辅助：地址提取 ────────────────────────────────

    private static func extractAddrAndRest(from s: String,
                                            removeKw: String?) -> (address: String?, rest: String) {
        // 按空白切 token
        var tokens = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if let kw = removeKw { tokens = tokens.map { $0.replacingOccurrences(of: kw, with: "") }.filter { !$0.isEmpty } }

        // 移除纯数字 token（已提取的数字残留）
        tokens = tokens.filter {
            let allNum = $0.allSatisfy({ $0.isNumber || $0 == "." })
            return !allNum
        }

        var addrParts: [String] = []
        var rest:      [String] = []

        for tok in tokens {
            if tok.count >= 2 && addrKeywords.contains(where: { tok.contains($0) }) {
                addrParts.append(tok)
            } else {
                rest.append(tok)
            }
        }

        let address = addrParts.isEmpty ? nil : addrParts.joined()
        return (address, rest.joined(separator: " "))
    }

    // MARK: ─── 辅助：姓名提取 ────────────────────────────────

    private static func extractName(from rest: String, removeKw: String?) -> String {
        var tokens = rest.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if let kw = removeKw { tokens = tokens.filter { !$0.contains(kw) } }
        tokens = tokens.filter { !$0.allSatisfy({ $0.isNumber || $0 == "." }) }
        // 取 1-6 字的短词（中文姓名通常 2-4 字，英文昵称也兼容）
        return tokens.filter { $0.count >= 1 && $0.count <= 8 }.first ?? tokens.first ?? ""
    }

    // MARK: ─── 基础正则工具 ──────────────────────────────────

    private static func removePattern(_ rx: NSRegularExpression, from s: String) -> String {
        rx.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
    }

    private static func firstMatch(_ rx: NSRegularExpression, in s: String) -> String? {
        let range = NSRange(s.startIndex..., in: s)
        guard let m = rx.firstMatch(in: s, range: range),
              let r = Range(m.range, in: s) else { return nil }
        return String(s[r])
    }

    /// 从双捕获组正则（"前缀数字 | 数字后缀单位"）提取数值
    private static func extractNumeric(_ rx: NSRegularExpression,
                                       from s: String,
                                       range vRange: ClosedRange<Double>) -> Double? {
        let nsRange = NSRange(s.startIndex..., in: s)
        guard let m = rx.firstMatch(in: s, range: nsRange) else { return nil }
        for i in 1...min(m.numberOfRanges - 1, 3) {
            guard let r = Range(m.range(at: i), in: s),
                  let v = Double(s[r]), vRange.contains(v) else { continue }
            return v
        }
        return nil
    }

    private static func extractNumericInt(_ rx: NSRegularExpression,
                                          from s: String,
                                          range vRange: ClosedRange<Int>) -> Int? {
        guard let v = extractNumeric(rx, from: s,
                                     range: Double(vRange.lowerBound)...Double(vRange.upperBound))
        else { return nil }
        return Int(v)
    }
}
