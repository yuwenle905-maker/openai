// MARK: - TextParser.swift
// 手动文本正则解析引擎 — 支持批量粘贴 "姓名 状态 金额"

import Foundation

// MARK: 单条解析结果
struct TextParseResult {
    let rawLine: String
    let name: String
    let conversionType: ConversionType
    let amount: Double
}

// MARK: 解析错误行信息（供 UI 展示）
struct TextParseError: Identifiable {
    let id = UUID()
    let lineNumber: Int
    let rawLine: String
    let reason: String
}

// MARK: 解析器
enum TextParser {

    // 核心正则：^([^\s]+)\s+([^\s]+)\s+(\d+(?:\.\d+)?)$
    private static let linePattern = try! NSRegularExpression(
        pattern: #"^([^\s]+)\s+([^\s]+)\s+(\d+(?:\.\d+)?)$"#
    )

    // MARK: 批量解析多行文本
    /// 返回 (成功结果列表, 解析失败行列表)
    static func parse(_ text: String) -> (results: [TextParseResult], errors: [TextParseError]) {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var results: [TextParseResult] = []
        var errors:  [TextParseError]  = []

        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1
            switch parseSingleLine(line) {
            case .success(let r):
                results.append(r)
            case .failure(let reason):
                errors.append(TextParseError(
                    lineNumber: lineNumber,
                    rawLine: line,
                    reason: reason
                ))
            }
        }
        return (results, errors)
    }

    // MARK: 解析单行
    static func parseSingleLine(_ line: String) -> Result<TextParseResult, String> {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let range = NSRange(trimmed.startIndex..., in: trimmed)

        guard let match = linePattern.firstMatch(in: trimmed, range: range),
              let nameRange   = Range(match.range(at: 1), in: trimmed),
              let typeRange   = Range(match.range(at: 2), in: trimmed),
              let amountRange = Range(match.range(at: 3), in: trimmed)
        else {
            return .failure("格式不符：需要 "姓名 状态 金额"，例如 "张三 新单 4280"")
        }

        let name   = String(trimmed[nameRange])
        let typeRaw = String(trimmed[typeRange])
        let amountStr = String(trimmed[amountRange])

        guard let amount = Double(amountStr), amount >= 0 else {
            return .failure("金额解析失败：\(amountStr)")
        }

        // 模糊匹配转化类型
        let convType = mapConversionType(typeRaw)

        return .success(TextParseResult(
            rawLine: line,
            name: name,
            conversionType: convType,
            amount: amount
        ))
    }

    // MARK: 转化类型模糊映射
    private static func mapConversionType(_ raw: String) -> ConversionType {
        switch raw {
        case let s where s.contains("新单") || s.contains("首单") || s.contains("新"):
            return .newOrder
        case let s where s.contains("二次") || s.contains("二") || s.contains("2"):
            return .second
        case let s where s.contains("三次") || s.contains("三") || s.contains("3"):
            return .third
        case let s where s.contains("四次") || s.contains("四") || s.contains("4"):
            return .fourth
        default:
            return .unknown
        }
    }
}
