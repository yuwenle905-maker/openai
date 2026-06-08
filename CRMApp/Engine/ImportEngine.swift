// MARK: - ImportEngine.swift
// Excel 导入主流程 — 特征值解析 + 去重弹窗调度

import Foundation
import Combine

// MARK: 导入进度事件
enum ImportEvent {
    case started(fileName: String)
    case rowParsed(index: Int, total: Int)
    // 触发手动补录弹窗
    case needsReview(rowIndex: Int, partial: RowParseResult)
    // 触发去重弹窗
    case duplicateFound(rowIndex: Int, existing: Customer, incoming: Customer)
    case completed(imported: Int, skipped: Int)
    case failed(Error)
}

// MARK: 模拟 Excel Row（真实实现需集成 CoreXLSX 或 xlsxwriter-c）
/// 在 Windows 审计阶段作为占位结构，替换时只需修改 parseXLSX()
struct RawRow {
    let index: Int
    let cells: [String]     // 每列原始字符串
}

// MARK: 主导入引擎
class ImportEngine: ObservableObject {

    @Published var events:  [ImportEvent]  = []
    @Published var isRunning: Bool         = false

    // ── 等待手动处理的行队列 ──────────────────────────────
    @Published var pendingReviewRow:     RowParseResult?
    @Published var pendingReviewIndex:   Int?
    @Published var showingEditSheet:     Bool = false

    @Published var pendingDuplicateRow:  (existing: Customer, incoming: Customer)?
    @Published var showingDuplicateSheet: Bool = false

    private var store: DataStore
    private var importQueue:  [(Int, RowParseResult)] = []  // (rowIndex, partialResult)
    private var batchID: UUID = UUID()
    private var importedCount = 0
    private var skippedCount  = 0

    init(store: DataStore) { self.store = store }

    // MARK: 主入口：从原始行列表开始导入
    func startImport(rows: [RawRow], fileName: String, hasHeaders: Bool) {
        isRunning = true
        importedCount = 0
        skippedCount  = 0
        batchID = UUID()
        importQueue = []
        events = [.started(fileName: fileName)]

        let dataRows = hasHeaders ? Array(rows.dropFirst()) : rows
        let headers  = hasHeaders ? rows.first?.cells ?? [] : []
        let headerMap = hasHeaders ? FeatureDetector.mapHeaders(headers) : [:]

        for row in dataRows {
            let parsed = hasHeaders
                ? parseWithHeaders(row.cells, map: headerMap)
                : FeatureDetector.parseRow(row.cells)
            importQueue.append((row.index, parsed))
        }

        processNextInQueue()
    }

    // MARK: 逐行处理队列
    private func processNextInQueue() {
        guard !importQueue.isEmpty else {
            finalizeImport()
            return
        }

        let (idx, parsed) = importQueue.removeFirst()
        events.append(.rowParsed(index: idx, total: importQueue.count))

        // 1. 最低字段校验（姓名 + 电话）
        guard parsed.isMinimallyValid else {
            skippedCount += 1
            processNextInQueue()
            return
        }

        // 2. 触发手动补录弹窗
        if parsed.needsManualReview {
            pendingReviewRow   = parsed
            pendingReviewIndex = idx
            showingEditSheet   = true
            events.append(.needsReview(rowIndex: idx, partial: parsed))
            // 流程在此挂起，等用户在 EditSheet 中调用 confirmReview() 或 skipReview()
            return
        }

        // 3. 去重检测
        let phone = parsed.phone!
        if let existing = store.findExisting(phone: phone) {
            let incoming = buildCustomer(from: parsed, batchID: batchID)
            pendingDuplicateRow = (existing, incoming)
            showingDuplicateSheet = true
            events.append(.duplicateFound(rowIndex: idx, existing: existing, incoming: incoming))
            return
        }

        // 4. 无冲突，直接写入
        let customer = buildCustomer(from: parsed, batchID: batchID)
        store.addCustomer(customer)
        importedCount += 1
        processNextInQueue()
    }

    // MARK: 用户确认手动补录后调用
    func confirmReview(updated: RowParseResult) {
        showingEditSheet = false
        pendingReviewRow = nil

        guard updated.isMinimallyValid else {
            skippedCount += 1
            processNextInQueue()
            return
        }

        let phone = updated.phone!
        if let existing = store.findExisting(phone: phone) {
            let incoming = buildCustomer(from: updated, batchID: batchID)
            pendingDuplicateRow = (existing, incoming)
            showingDuplicateSheet = true
            return
        }

        store.addCustomer(buildCustomer(from: updated, batchID: batchID))
        importedCount += 1
        processNextInQueue()
    }

    // MARK: 用户点击"跳过此行"
    func skipReview() {
        showingEditSheet = false
        pendingReviewRow = nil
        skippedCount += 1
        processNextInQueue()
    }

    // MARK: 用户选择去重策略后调用
    func resolveDuplicate(resolution: DuplicateResolution) {
        showingDuplicateSheet = false
        guard let pair = pendingDuplicateRow else { processNextInQueue(); return }
        pendingDuplicateRow = nil

        var existing = pair.existing
        let handled = store.applyDuplicateResolution(
            existing: &existing,
            incoming: pair.incoming,
            resolution: resolution
        )
        store.save()

        if handled && resolution != .skip { importedCount += 1 }
        else if !handled { skippedCount += 1 }

        processNextInQueue()
    }

    // MARK: 完成
    private func finalizeImport() {
        let batch = ImportBatch(
            id: batchID,
            fileName: "import_\(batchID.uuidString.prefix(8))",
            importDate: Date(),
            recordCount: importedCount
        )
        store.addBatch(batch)
        isRunning = false
        events.append(.completed(imported: importedCount, skipped: skippedCount))
    }

    // MARK: 辅助：有表头模式逐行解析
    private func parseWithHeaders(_ cells: [String], map: [Int: String]) -> RowParseResult {
        var result = RowParseResult()
        for (i, cell) in cells.enumerated() {
            guard let key = map[i] else { continue }
            let value = cell.trimmingCharacters(in: .whitespaces)
            switch key {
            case "name":    result.name    = value
            case "phone":   result.phone   = value
            case "address": result.address = value
            case "age":     result.age     = Int(value)
            case "height":  result.height  = Double(value)
            case "weight":  result.weight  = Double(value)
            default: break
            }
        }
        return result
    }

    // MARK: 辅助：RowParseResult → Customer
    private func buildCustomer(from r: RowParseResult, batchID: UUID) -> Customer {
        Customer(
            name:          r.name ?? "未知",
            phone:         r.phone ?? "",
            address:       r.address,
            age:           r.age,
            height:        r.height,
            weight:        r.weight,
            importBatchID: batchID,
            importDate:    Date()
        )
    }
}
