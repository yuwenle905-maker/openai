// MARK: - TextParser.swift
// 手动文本批量录入解析引擎
// 新策略：不依赖空格，从右向左提取「金额→状态关键词→剩余为姓名」

import Foundation

// MARK: 解析错误
enum ParseError: Error {
    case formatMismatch(String)
    case invalidAmount(String)
}

// MARK: 单条解析结果
struct TextParseResult: Identifiable {
    let id = UUID()
    let rawLine: String
    let name: String
    let conversionType: ConversionType
    let amount: Double
}

// MARK: 解析错误行
struct TextParseError: Identifiable {
    let id = UUID()
    let lineNumber: Int
    let rawLine: String
    let reason: String
}

// MARK: 主解析器
enum TextParser {

    // 状态关键词表（按优先级顺序）
    private static let conversionKeywords: [(keywords: [String], type: ConversionType)] = [
        (["四次", "4次", "第四"],  .fourth),
        (["三次", "3次", "第三"],  .third),
        (["二次", "2次", "第二", "复购"], .second),
        (["新单", "首单", "一次", "1次", "第一", "新"], .newOrder),
    ]

    // 末尾金额正则：匹配行末的数字（含小数）
    private static let trailingAmountPattern = try! NSRegularExpression(
        pattern: #"(\d+(?:[.,]\d+)?)\s*[元￥]?\s*$"#
    )

    // MARK: 批量解析
    static func parse(_ text: String) -> (results: [TextParseResult], errors: [TextParseError]) {
        // 预处理：全角/特殊空格/Tab/中文标点统一为半角空格
        let normalized = text
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2003}", with: " ")
            .replacingOccurrences(of: "\t",        with: " ")
            .replacingOccurrences(of: "，",         with: " ")
            .replacingOccurrences(of: "、",         with: " ")
            .replacingOccurrences(of: "　",         with: " ")

        let lines = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var results: [TextParseResult] = []
        var errors:  [TextParseError]  = []

        for (i, line) in lines.enumerated() {
            switch parseLine(line) {
            case .success(let r):
                results.append(r)
            case .failure(let err):
                let reason: String
                switch err {
                case .formatMismatch(let m): reason = m
                case .invalidAmount(let m):  reason = m
                }
                errors.append(TextParseError(lineNumber: i + 1, rawLine: line, reason: reason))
            }
        }
        return (results, errors)
    }

    // MARK: 单行解析（不依赖空格）
    static func parseLine(_ raw: String) -> Result<TextParseResult, ParseError> {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else {
            return .failure(.formatMismatch("空行"))
        }

        // 1. 从末尾提取金额
        let nsRange = NSRange(s.startIndex..., in: s)
        guard let amountMatch = trailingAmountPattern.firstMatch(in: s, range: nsRange),
              let amtRange = Range(amountMatch.range(at: 1), in: s) else {
            return .failure(.formatMismatch("找不到金额数字，请确保行末包含金额，例如：张三新单4280"))
        }
        let amountStr = String(s[amtRange]).replacingOccurrences(of: ",", with: "")
        guard let amount = Double(amountStr), amount >= 0 else {
            return .failure(.invalidAmount("金额解析失败：\(amountStr)"))
        }

        // 去掉末尾金额部分，得到前缀
        let prefixEnd = amountMatch.range.location == NSNotFound
            ? s.endIndex
            : s.index(s.startIndex, offsetBy: amountMatch.range.location)
        let prefix = String(s[s.startIndex..<prefixEnd])
            .trimmingCharacters(in: .whitespaces)

        // 2. 从前缀中识别状态关键词
        var convType: ConversionType = .unknown
        var nameCandidate = prefix

        for entry in conversionKeywords {
            for kw in entry.keywords {
                if prefix.contains(kw) {
                    convType = entry.type
                    // 去掉关键词，剩余为姓名
                    nameCandidate = prefix
                        .replacingOccurrences(of: kw, with: "")
                        .trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            if convType != .unknown { break }
        }

        // 3. 姓名为空检查
        let name = nameCandidate.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            return .failure(.formatMismatch("解析出的姓名为空，请检查格式。示例：张三新单4280"))
        }

        return .success(TextParseResult(
            rawLine:        raw,
            name:           name,
            conversionType: convType,
            amount:         amount
        ))
    }
}
