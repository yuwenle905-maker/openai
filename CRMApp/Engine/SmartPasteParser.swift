// MARK: - SmartPasteParser.swift
// 智能粘贴解析引擎 v4
//
// 新增能力：
//   带中文冒号/逗号标签的结构化文本（朵朵，15394078069，地址\n产品：xxx\n今天：600 ...）
//   通过"标签清洗 + 统一拼行"后再走六维度提取
//
//   v4 新增：制表符分隔纯数字多列智能匹配
//   当列顺序为：姓名\t电话\t地址\t身高\t体重\t年龄[\t性别]... 时
//   三个连续纯数字列自动识别为身高/体重/年龄，后续"男"/"女"列识别为性别

import Foundation

// MARK: 解析结果
struct ParsedRow: Identifiable {
    let id       = UUID()
    let rawLine:  String
    let rowIndex: Int

    var name:           String
    var phone:          String?
    var address:        String?
    var leadAmount:     Double?
    var conversionType: ConversionType
    var age:            Int?
    var height:         Double?
    var weight:         Double?
    var gender:         String = "未知"
    var productNote:    String?
    var dataType:       CustomerDataType

    var isValid:        Bool { !name.isEmpty }
    var isFullCustomer: Bool { dataType == .fullCustomer && phone != nil }
}

// MARK: 解析失败行
struct ParseFailedRow: Identifiable {
    let id         = UUID()
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
    private static let genderRx = try! NSRegularExpression(
        pattern: #"性别[：:]\s*([男女])|(性别)\s*([男女])"#
    )
    private static let trackingRx = try! NSRegularExpression(
        // 快递单号：SF/YT/ZT/JD/EMS 等字母前缀 + 8-20 位数字
        pattern: #"(?:[A-Z]{2,4}|顺丰|圆通|韵达|中通|申通|邮政)\d{8,20}"#,
        options: .caseInsensitive
    )
    private static let productRx = try! NSRegularExpression(
        pattern: #"[一-龥\w]+(?:\d*[+＋][一-龥\w]+\d*)+"#
    )

    // 中文冒号标签白名单（这些前缀后跟的内容提取后可去掉前缀）
    private static let labelPrefixes = [
        "产品", "今天", "信息", "快递", "备注", "地址", "姓名",
        "电话", "手机", "单号", "金额", "收货", "收件", "寄件"
    ]

    // 流水关键词
    private static let ledgerKeywords = [
        "新单","首单","二次","三次","四次","五次","六次","七次","八次","复购"
    ]

    // 转化类型优先级表
    private static let convKwTable: [(keys: [String], type: ConversionType)] = [
        (["八次","8次","第八"],              .eighth),
        (["七次","7次","第七"],              .seventh),
        (["六次","6次","第六"],              .sixth),
        (["五次","5次","第五"],              .fifth),
        (["四次","4次","第四"],              .fourth),
        (["三次","3次","第三"],              .third),
        (["二次","2次","第二","复购"],        .second),
        (["新单","首单","一次","1次","新"],   .newOrder),
    ]

    // 地址特征词
    private static let addrKeywords = [
        "省","市","区","县","路","街","镇","乡","村","号","楼","室","单元","巷","弄",
        "广东","广西","海南","上海","江苏","浙江","安徽","福建","江西","山东","台湾",
        "北京","天津","河北","山西","内蒙古","内蒙","辽宁","吉林","黑龙江",
        "河南","湖北","湖南","重庆","四川","贵州","云南","西藏",
        "陕西","甘肃","甘州","张掖","青海","宁夏","新疆","香港","澳门",
        "广州","深圳","珠海","佛山","东莞","中山","惠州",
        "南京","杭州","苏州","宁波","无锡","武汉","成都","西安","沈阳","长春","哈尔滨"
    ]

    // MARK: ─── 公开入口 ─────────────────────────────────────

    static func parse(_ text: String) -> (rows: [ParsedRow], failed: [ParseFailedRow]) {
        // 第一步：整体标准化（换行符/特殊空格统一）—— 保留 \t 直到块解析时处理
        let step1 = normalizeWhitespace(text)

        // 第二步：切分客户块
        let blocks = splitIntoCustomerBlocks(step1)

        var rows:   [ParsedRow]      = []
        var failed: [ParseFailedRow] = []

        for (i, block) in blocks.enumerated() {
            // 优先尝试制表符分隔解析（纯数字多列格式）
            if block.contains("\t"), let row = parseTabRow(block, rawOriginal: block, index: i) {
                rows.append(row)
                continue
            }
            // 第三步：对每个块做标签清洗，再解析
            let cleaned = cleanLabels(block)
            if let row = parseBlock(cleaned, rawOriginal: block, index: i) {
                rows.append(row)
            } else {
                failed.append(ParseFailedRow(
                    lineNumber: i + 1,
                    rawLine:    block,
                    reason:     "无法提取有效字段（需包含姓名，建议附上电话和地址）"
                ))
            }
        }
        return (rows, failed)
    }

    // MARK: ─── 制表符多列行专用解析器 ───────────────────────
    //
    // 适配格式：姓名\t电话\t地址\t身高\t体重\t年龄[\t性别]\t...
    // 连续三个纯数字列（紧随姓名+电话+地址）→ 身高/体重/年龄
    // 紧邻下一列若为"男"/"女" → 性别

    private static func parseTabRow(_ raw: String, rawOriginal: String, index: Int) -> ParsedRow? {
        let cols = raw.components(separatedBy: "\t").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard cols.count >= 2 else { return nil }

        // 找电话列
        var phoneIdx: Int? = nil
        var extractedPhone: String? = nil
        for (i, col) in cols.enumerated() {
            if phoneRx.firstMatch(in: col, range: NSRange(col.startIndex..., in: col)) != nil {
                phoneIdx = i
                extractedPhone = col
                break
            }
        }
        guard let pIdx = phoneIdx, pIdx >= 1 else { return nil }

        // 姓名：电话列前第一个非空列
        let name = cols[0..<pIdx].last { !$0.isEmpty } ?? ""
        guard !name.isEmpty else { return nil }

        // 地址：电话列之后第一个含地址特征词的列
        var addrIdx: Int? = nil
        var extractedAddress: String? = nil
        for i in (pIdx + 1)..<cols.count {
            let col = cols[i]
            if addrKeywords.contains(where: { col.contains($0) }) {
                addrIdx = i
                extractedAddress = col
                break
            }
        }

        // 数字列起点：地址列之后，或电话列+1（若无地址列）
        let numStart = (addrIdx ?? pIdx) + 1

        // 从 numStart 开始连续检测三个纯数字列 → 身高/体重/年龄
        var height: Double? = nil
        var weight: Double? = nil
        var age:    Int?    = nil
        var gender: String  = "未知"
        var leadAmount: Double? = nil

        // 收集 numStart 之后所有纯数字列（及其索引）
        var numericCols: [(idx: Int, val: Double)] = []
        for i in numStart..<cols.count {
            let col = cols[i]
            if col.isEmpty { continue }
            if col.allSatisfy({ $0.isNumber || $0 == "." }), let v = Double(col) {
                numericCols.append((i, v))
            } else {
                // 遇到非数字中断连续检测
                break
            }
        }

        // 按合理范围依次赋值
        var genderSearchStart = numStart
        if numericCols.count >= 3 {
            let h = numericCols[0].val
            let w = numericCols[1].val
            let a = numericCols[2].val
            if (100...220).contains(h) && (30...200).contains(w) && (1...99).contains(a) {
                height = h
                weight = w
                age    = Int(a)
                genderSearchStart = numericCols[2].idx + 1
            }
        } else if numericCols.count == 2 {
            let h = numericCols[0].val
            let w = numericCols[1].val
            if (100...220).contains(h) && (30...200).contains(w) {
                height = h
                weight = w
                genderSearchStart = numericCols[1].idx + 1
            }
        } else if numericCols.count == 1 {
            let h = numericCols[0].val
            if (100...220).contains(h) {
                height = h
                genderSearchStart = numericCols[0].idx + 1
            }
        }

        // 性别检测：从数字列结束后顺序扫描
        for i in genderSearchStart..<cols.count {
            let col = cols[i]
            if col == "男" || col == "女" {
                gender = col
                break
            }
        }

        // 金额提取：从所有列中找最大合理数字（不在身高/体重/年龄范围内）
        for (_, v) in numericCols.dropFirst(3) {
            if v >= 50 && v <= 99999 {
                leadAmount = v
                break
            }
        }
        // 若 numericCols 不足3个也搜索剩余列
        if leadAmount == nil {
            for i in genderSearchStart..<cols.count {
                let col = cols[i]
                if col.allSatisfy({ $0.isNumber || $0 == "." }),
                   let v = Double(col), v >= 50 && v <= 99999 {
                    leadAmount = v
                    break
                }
            }
        }

        // 转化类型（从全行文本检测）
        let fullText = cols.joined(separator: " ")
        let (convType, _) = detectConvType(in: fullText)

        let hasAllThree = extractedPhone != nil && extractedAddress != nil
        let dataType: CustomerDataType = hasAllThree ? .fullCustomer : .ledgerEntry

        return ParsedRow(
            rawLine:        rawOriginal,
            rowIndex:       index,
            name:           name,
            phone:          extractedPhone,
            address:        extractedAddress,
            leadAmount:     leadAmount,
            conversionType: convType,
            age:            age,
            height:         height,
            weight:         weight,
            gender:         gender,
            productNote:    nil,
            dataType:       dataType
        )
    }

    // MARK: ─── 第一步：文本整体标准化 ───────────────────────
    // 注意：\t 在此步骤保留，由各块解析器自行处理

    private static func normalizeWhitespace(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r",   with: "\n")
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2003}", with: " ")
        // \t 不在此处替换，保留给 parseTabRow 使用
    }

    // MARK: ─── 第二步：切分客户块 ────────────────────────────
    //
    // 规则：
    //   1. 空行 → 强制分隔
    //   2. 当前行含手机号且前序积累行已含手机号 → 新块
    //   3. 含标签行（"产品："等）→ 属于当前块，不分隔

    private static func splitIntoCustomerBlocks(_ text: String) -> [String] {
        let rawLines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var blocks:       [String] = []
        var currentLines: [String] = []

        for line in rawLines {
            if line.isEmpty {
                if !currentLines.isEmpty {
                    blocks.append(currentLines.joined(separator: "\n"))
                    currentLines = []
                }
                continue
            }

            let lineHasPhone   = containsPhone(line)
            let accumHasPhone  = currentLines.contains { containsPhone($0) }
            // 制表符行不作为标签行处理
            let isLabelLine    = !line.contains("\t") && labelPrefixes.contains {
                line.hasPrefix($0 + "：") || line.hasPrefix($0 + ":")
            }

            if lineHasPhone && accumHasPhone && !isLabelLine {
                // 新客户起点
                blocks.append(currentLines.joined(separator: "\n"))
                currentLines = [line]
            } else {
                currentLines.append(line)
            }
        }
        if !currentLines.isEmpty {
            blocks.append(currentLines.joined(separator: "\n"))
        }

        // 后备：若只有一块且原文有换行，按行再切一次
        if blocks.count == 1 && text.contains("\n") {
            let fallback = rawLines.filter { !$0.isEmpty }
            if fallback.count > 1 {
                let phoneLines = fallback.filter { containsPhone($0) }
                if phoneLines.count > 1 {
                    return fallback.filter { containsPhone($0) }
                }
            }
        }

        return blocks.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func containsPhone(_ s: String) -> Bool {
        phoneRx.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    // MARK: ─── 第三步：标签清洗（非制表符行） ───────────────
    //
    // 把 "产品：xxx" 中的标签前缀去掉，只保留值；
    // 把中文逗号分隔的首行（姓名，电话，地址）拆成空格分隔

    private static func cleanLabels(_ block: String) -> String {
        // 将保留的换行转为空格后处理
        var s = block.replacingOccurrences(of: "\n", with: " ")
                     .replacingOccurrences(of: "\t", with: " ")

        // 1. 中文逗号替换为空格
        s = s.replacingOccurrences(of: "，", with: " ")

        // 2. 去除标签前缀（"产品：" "今天：" 等），保留后面的值
        for prefix in labelPrefixes {
            s = s.replacingOccurrences(of: prefix + "：", with: " ")
            s = s.replacingOccurrences(of: prefix + ":", with: " ")
        }

        // 3. 压缩多余空格
        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: ─── 第四步：解析单个块（非制表符） ───────────────

    private static func parseBlock(_ s: String, rawOriginal: String, index: Int) -> ParsedRow? {
        var remaining = s.trimmingCharacters(in: .whitespaces)
        guard !remaining.isEmpty else { return nil }

        // 移除快递单号
        remaining = removePattern(trackingRx, from: remaining)

        // 提取 & 移除手机号
        let phone = firstMatch(phoneRx, in: remaining)
        remaining = removePattern(phoneRx, from: remaining)

        // 提取 & 移除身高/体重/年龄（优先于金额，避免数字干扰）
        let height = extractNumeric(heightRx, from: remaining, range: 100...220)
        let weight = extractNumeric(weightRx, from: remaining, range:  30...150)
        let age    = extractNumericInt(ageRx, from: remaining, range:   1...99)
        remaining  = removePattern(heightRx, from: remaining)
        remaining  = removePattern(weightRx, from: remaining)
        remaining  = removePattern(ageRx,    from: remaining)

        // 提取性别（"性别：男" / "性别：女" 格式）
        let gender = extractGender(from: remaining) ?? "未知"
        remaining  = removePattern(genderRx, from: remaining)

        // 提取商品备注（含"+"的组合词，需在移除数字前）
        let product = firstMatch(productRx, in: remaining)

        // 提取金额（线索金额，不计营业额）
        let amount = extractBestAmount(from: remaining)

        // 提取转化类型
        let (convType, convKw) = detectConvType(in: remaining)

        // 提取地址
        let (address, rest) = extractAddrAndRest(from: remaining, removeKw: convKw)

        // 提取姓名
        let name = extractName(from: rest, removeKw: convKw)
        guard !name.isEmpty else { return nil }

        let hasAllThree = phone != nil && address != nil
        let dataType: CustomerDataType = hasAllThree ? .fullCustomer : .ledgerEntry

        return ParsedRow(
            rawLine:        rawOriginal,
            rowIndex:       index,
            name:           name,
            phone:          phone,
            address:        address,
            leadAmount:     amount,
            conversionType: convType,
            age:            age,
            height:         height,
            weight:         weight,
            gender:         gender,
            productNote:    product,
            dataType:       dataType
        )
    }

    // MARK: ─── 辅助方法 ─────────────────────────────────────

    private static func extractBestAmount(from s: String) -> Double? {
        let range    = NSRange(s.startIndex..., in: s)
        let matches  = amountRx.matches(in: s, range: range)
        let candidates: [Double] = matches.compactMap { m in
            guard let r = Range(m.range(at: 1), in: s) else { return nil }
            return Double(s[r])
        }
        return candidates.filter { $0 >= 50 && $0 <= 99999 }.max()
            ?? candidates.first
    }

    private static func detectConvType(in s: String) -> (ConversionType, String?) {
        for entry in convKwTable {
            for kw in entry.keys where s.contains(kw) {
                return (entry.type, kw)
            }
        }
        return (.newOrder, nil)
    }

    private static func extractGender(from s: String) -> String? {
        let ns = NSRange(s.startIndex..., in: s)
        guard let m = genderRx.firstMatch(in: s, range: ns) else { return nil }
        for i in 1..<m.numberOfRanges {
            guard let r = Range(m.range(at: i), in: s) else { continue }
            let v = String(s[r])
            if v == "男" || v == "女" { return v }
        }
        return nil
    }

    private static func extractAddrAndRest(from s: String,
                                            removeKw: String?) -> (address: String?, rest: String) {
        var tokens = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if let kw = removeKw {
            tokens = tokens.map { $0.replacingOccurrences(of: kw, with: "") }.filter { !$0.isEmpty }
        }
        // 移除纯数字 token
        tokens = tokens.filter { !$0.allSatisfy { $0.isNumber || $0 == "." } }

        var addrParts: [String] = []
        var rest:      [String] = []
        for tok in tokens {
            if tok.count >= 2 && addrKeywords.contains(where: { tok.contains($0) }) {
                addrParts.append(tok)
            } else {
                rest.append(tok)
            }
        }
        return (addrParts.isEmpty ? nil : addrParts.joined(), rest.joined(separator: " "))
    }

    private static func extractName(from rest: String, removeKw: String?) -> String {
        var tokens = rest.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if let kw = removeKw { tokens = tokens.filter { !$0.contains(kw) } }
        tokens = tokens.filter { !$0.allSatisfy { $0.isNumber || $0 == "." } }
        return tokens.filter { $0.count >= 1 && $0.count <= 8 }.first ?? tokens.first ?? ""
    }

    private static func removePattern(_ rx: NSRegularExpression, from s: String) -> String {
        rx.stringByReplacingMatches(in: s,
                                    range: NSRange(s.startIndex..., in: s),
                                    withTemplate: " ")
    }

    private static func firstMatch(_ rx: NSRegularExpression, in s: String) -> String? {
        guard let m = rx.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range, in: s) else { return nil }
        return String(s[r])
    }

    private static func extractNumeric(_ rx: NSRegularExpression,
                                       from s: String,
                                       range vRange: ClosedRange<Double>) -> Double? {
        let ns = NSRange(s.startIndex..., in: s)
        guard let m = rx.firstMatch(in: s, range: ns) else { return nil }
        for i in 1..<m.numberOfRanges {
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

// MARK: 解析失败行
struct ParseFailedRow: Identifiable {
    let id         = UUID()
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
        // 快递单号：SF/YT/ZT/JD/EMS 等字母前缀 + 8-20 位数字
        pattern: #"(?:[A-Z]{2,4}|顺丰|圆通|韵达|中通|申通|邮政)\d{8,20}"#,
        options: .caseInsensitive
    )
    private static let productRx = try! NSRegularExpression(
        pattern: #"[一-龥\w]+(?:\d*[+＋][一-龥\w]+\d*)+"#
    )

    // 中文冒号标签白名单（这些前缀后跟的内容提取后可去掉前缀）
    private static let labelPrefixes = [
        "产品", "今天", "信息", "快递", "备注", "地址", "姓名",
        "电话", "手机", "单号", "金额", "收货", "收件", "寄件"
    ]

    // 流水关键词
    private static let ledgerKeywords = [
        "新单","首单","二次","三次","四次","五次","六次","七次","八次","复购"
    ]

    // 转化类型优先级表
    private static let convKwTable: [(keys: [String], type: ConversionType)] = [
        (["八次","8次","第八"],              .eighth),
        (["七次","7次","第七"],              .seventh),
        (["六次","6次","第六"],              .sixth),
        (["五次","5次","第五"],              .fifth),
        (["四次","4次","第四"],              .fourth),
        (["三次","3次","第三"],              .third),
        (["二次","2次","第二","复购"],        .second),
        (["新单","首单","一次","1次","新"],   .newOrder),
    ]

    // 地址特征词
    private static let addrKeywords = [
        "省","市","区","县","路","街","镇","乡","村","号","楼","室","单元","巷","弄",
        "广东","广西","海南","上海","江苏","浙江","安徽","福建","江西","山东","台湾",
        "北京","天津","河北","山西","内蒙古","内蒙","辽宁","吉林","黑龙江",
        "河南","湖北","湖南","重庆","四川","贵州","云南","西藏",
        "陕西","甘肃","甘州","张掖","青海","宁夏","新疆","香港","澳门",
        "广州","深圳","珠海","佛山","东莞","中山","惠州",
        "南京","杭州","苏州","宁波","无锡","武汉","成都","西安","沈阳","长春","哈尔滨"
    ]

    // MARK: ─── 公开入口 ─────────────────────────────────────

    static func parse(_ text: String) -> (rows: [ParsedRow], failed: [ParseFailedRow]) {
        // 第一步：整体标准化（换行符/特殊空格统一）
        let step1 = normalizeWhitespace(text)

        // 第二步：切分客户块
        let blocks = splitIntoCustomerBlocks(step1)

        var rows:   [ParsedRow]      = []
        var failed: [ParseFailedRow] = []

        for (i, block) in blocks.enumerated() {
            // 第三步：对每个块做标签清洗，再解析
            let cleaned = cleanLabels(block)
            if let row = parseBlock(cleaned, rawOriginal: block, index: i) {
                rows.append(row)
            } else {
                failed.append(ParseFailedRow(
                    lineNumber: i + 1,
                    rawLine:    block,
                    reason:     "无法提取有效字段（需包含姓名，建议附上电话和地址）"
                ))
            }
        }
        return (rows, failed)
    }

    // MARK: ─── 第一步：文本整体标准化 ───────────────────────

    private static func normalizeWhitespace(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r",   with: "\n")
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2003}", with: " ")
            .replacingOccurrences(of: "\t",        with: " ")
    }

    // MARK: ─── 第二步：切分客户块 ────────────────────────────
    //
    // 规则：
    //   1. 空行 → 强制分隔
    //   2. 当前行含手机号且前序积累行已含手机号 → 新块
    //   3. 含标签行（"产品：""今天："等）→ 属于当前块，不分隔

    private static func splitIntoCustomerBlocks(_ text: String) -> [String] {
        let rawLines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var blocks:       [String] = []
        var currentLines: [String] = []

        for line in rawLines {
            if line.isEmpty {
                if !currentLines.isEmpty {
                    blocks.append(currentLines.joined(separator: " "))
                    currentLines = []
                }
                continue
            }

            let lineHasPhone   = containsPhone(line)
            let accumHasPhone  = currentLines.contains { containsPhone($0) }
            let isLabelLine    = labelPrefixes.contains { line.hasPrefix($0 + "：") || line.hasPrefix($0 + ":") }

            if lineHasPhone && accumHasPhone && !isLabelLine {
                // 新客户起点
                blocks.append(currentLines.joined(separator: " "))
                currentLines = [line]
            } else {
                currentLines.append(line)
            }
        }
        if !currentLines.isEmpty {
            blocks.append(currentLines.joined(separator: " "))
        }

        // 后备：若只有一块且原文有换行，按行再切一次
        if blocks.count == 1 && text.contains("\n") {
            let fallback = rawLines.filter { !$0.isEmpty }
            if fallback.count > 1 {
                // 检查每行是否独立含足够信息（含手机号的行作为独立客户）
                let phoneLines = fallback.filter { containsPhone($0) }
                if phoneLines.count > 1 {
                    return fallback.filter { containsPhone($0) }
                }
            }
        }

        return blocks.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func containsPhone(_ s: String) -> Bool {
        phoneRx.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    // MARK: ─── 第三步：标签清洗 ──────────────────────────────
    //
    // 把 "产品：xxx" 中的标签前缀去掉，只保留值；
    // 把中文逗号分隔的首行（姓名，电话，地址）拆成空格分隔
    //
    // 示例：
    //   "朵朵，15394078069，甘肃省张掖市...  产品：产品茶2+脂肪粉2  今天：600  信息：身高155..."
    // 清洗后：
    //   "朵朵 15394078069 甘肃省张掖市... 产品茶2+脂肪粉2 600 身高155..."

    private static func cleanLabels(_ block: String) -> String {
        var s = block

        // 1. 中文逗号替换为空格（常见于"姓名，电话，地址"首行）
        s = s.replacingOccurrences(of: "，", with: " ")

        // 2. 去除标签前缀（"产品：" "今天：" 等），保留后面的值
        for prefix in labelPrefixes {
            s = s.replacingOccurrences(of: prefix + "：", with: " ")
            s = s.replacingOccurrences(of: prefix + ":", with: " ")
        }

        // 3. 压缩多余空格
        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: ─── 第四步：解析单个块 ────────────────────────────

    private static func parseBlock(_ s: String, rawOriginal: String, index: Int) -> ParsedRow? {
        var remaining = s.trimmingCharacters(in: .whitespaces)
        guard !remaining.isEmpty else { return nil }

        // 移除快递单号
        remaining = removePattern(trackingRx, from: remaining)

        // 提取 & 移除手机号
        let phone = firstMatch(phoneRx, in: remaining)
        remaining = removePattern(phoneRx, from: remaining)

        // 提取 & 移除身高/体重/年龄（优先于金额，避免数字干扰）
        let height = extractNumeric(heightRx, from: remaining, range: 100...220)
        let weight = extractNumeric(weightRx, from: remaining, range:  30...150)
        let age    = extractNumericInt(ageRx, from: remaining, range:   1...99)
        remaining  = removePattern(heightRx, from: remaining)
        remaining  = removePattern(weightRx, from: remaining)
        remaining  = removePattern(ageRx,    from: remaining)

        // 提取商品备注（含"+"的组合词，需在移除数字前）
        let product = firstMatch(productRx, in: remaining)

        // 提取金额（线索金额，不计营业额）
        let amount = extractBestAmount(from: remaining)

        // 提取转化类型
        let (convType, convKw) = detectConvType(in: remaining)

        // 提取地址
        let (address, rest) = extractAddrAndRest(from: remaining, removeKw: convKw)

        // 提取姓名
        let name = extractName(from: rest, removeKw: convKw)
        guard !name.isEmpty else { return nil }

        // 判定数据类型：姓名+电话+地址三项齐全 → fullCustomer
        let hasAllThree = phone != nil && address != nil
        let dataType: CustomerDataType = hasAllThree ? .fullCustomer : .ledgerEntry

        return ParsedRow(
            rawLine:        rawOriginal,
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

    // MARK: ─── 辅助方法 ─────────────────────────────────────

    private static func extractBestAmount(from s: String) -> Double? {
        let range    = NSRange(s.startIndex..., in: s)
        let matches  = amountRx.matches(in: s, range: range)
        let candidates: [Double] = matches.compactMap { m in
            guard let r = Range(m.range(at: 1), in: s) else { return nil }
            return Double(s[r])
        }
        return candidates.filter { $0 >= 50 && $0 <= 99999 }.max()
            ?? candidates.first
    }

    private static func detectConvType(in s: String) -> (ConversionType, String?) {
        for entry in convKwTable {
            for kw in entry.keys where s.contains(kw) {
                return (entry.type, kw)
            }
        }
        return (.newOrder, nil)
    }

    private static func extractAddrAndRest(from s: String,
                                            removeKw: String?) -> (address: String?, rest: String) {
        var tokens = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if let kw = removeKw {
            tokens = tokens.map { $0.replacingOccurrences(of: kw, with: "") }.filter { !$0.isEmpty }
        }
        // 移除纯数字 token
        tokens = tokens.filter { !$0.allSatisfy { $0.isNumber || $0 == "." } }

        var addrParts: [String] = []
        var rest:      [String] = []
        for tok in tokens {
            if tok.count >= 2 && addrKeywords.contains(where: { tok.contains($0) }) {
                addrParts.append(tok)
            } else {
                rest.append(tok)
            }
        }
        return (addrParts.isEmpty ? nil : addrParts.joined(), rest.joined(separator: " "))
    }

    private static func extractName(from rest: String, removeKw: String?) -> String {
        var tokens = rest.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if let kw = removeKw { tokens = tokens.filter { !$0.contains(kw) } }
        tokens = tokens.filter { !$0.allSatisfy { $0.isNumber || $0 == "." } }
        return tokens.filter { $0.count >= 1 && $0.count <= 8 }.first ?? tokens.first ?? ""
    }

    private static func removePattern(_ rx: NSRegularExpression, from s: String) -> String {
        rx.stringByReplacingMatches(in: s,
                                    range: NSRange(s.startIndex..., in: s),
                                    withTemplate: " ")
    }

    private static func firstMatch(_ rx: NSRegularExpression, in s: String) -> String? {
        guard let m = rx.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range, in: s) else { return nil }
        return String(s[r])
    }

    private static func extractNumeric(_ rx: NSRegularExpression,
                                       from s: String,
                                       range vRange: ClosedRange<Double>) -> Double? {
        let ns = NSRange(s.startIndex..., in: s)
        guard let m = rx.firstMatch(in: s, range: ns) else { return nil }
        for i in 1..<m.numberOfRanges {
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
