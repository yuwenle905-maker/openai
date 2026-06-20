// MARK: - ImportView.swift
// 智能粘贴导入界面（废弃文件选择，改为文本粘贴 + 逐条确认 + 去重弹窗）

import SwiftUI

// MARK: - 主界面
struct ImportView: View {

    @EnvironmentObject var store: DataStore
    @State private var pasteText:       String = ""
    @State private var parsedRows:      [ParsedRow]      = []
    @State private var failedRows:      [ParseFailedRow] = []
    @State private var showConfirmSheet = false
    @FocusState private var textFocused: Bool

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // ── 说明卡片 ───────────────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        Text("直接粘贴数据，系统自动解析")
                            .font(.headline)
                        Text("支持格式：姓名 电话 地址 商品 金额 身高/体重/年龄 快递单号")
                            .font(.caption).foregroundColor(.secondary)
                        Text("也支持流水格式：张三 新单 4280（不产生新客户）")
                            .font(.caption).foregroundColor(.orange)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // ── 粘贴文本框 ────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("粘贴数据")
                                .font(.subheadline.bold())
                            Spacer()
                            if !pasteText.isEmpty {
                                Button("清空") {
                                    pasteText   = ""
                                    parsedRows  = []
                                    failedRows  = []
                                    textFocused = false
                                }
                                .font(.caption)
                                .foregroundColor(.red)
                            }
                        }
                        .padding(.horizontal)

                        TextEditor(text: $pasteText)
                            .focused($textFocused)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 180, maxHeight: 320)
                            .padding(8)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                    }

                    // ── 操作按钮 ─────────────────────────────
                    HStack(spacing: 12) {
                        Button {
                            textFocused = false
                            let result  = SmartPasteParser.parse(pasteText)
                            parsedRows  = result.rows
                            failedRows  = result.failed
                            if !parsedRows.isEmpty { showConfirmSheet = true }
                        } label: {
                            Label("解析并预览", systemImage: "text.magnifyingglass")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                            ? Color.gray : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button {
                            textFocused = false
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .padding(10)
                                .background(Color(.secondarySystemGroupedBackground))
                                .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal)

                    // ── 解析失败提示 ─────────────────────────
                    if !failedRows.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("无法解析的行（\(failedRows.count) 条）")
                                .font(.caption.bold()).foregroundColor(.red)
                                .padding(.horizontal).padding(.top, 8)
                            Divider()
                            ForEach(failedRows) { row in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("第\(row.lineNumber)行：\(row.rawLine)")
                                        .font(.caption.monospaced()).lineLimit(2)
                                    Text(row.reason).font(.caption2).foregroundColor(.red)
                                }
                                .padding(.horizontal).padding(.vertical, 6)
                                Divider()
                            }
                        }
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("智能导入")
            .onTapGesture { textFocused = false }
        }
        // 确认弹窗
        .sheet(isPresented: $showConfirmSheet) {
            ImportConfirmSheet(
                rows:      parsedRows,
                failed:    failedRows,
                onConfirm: { confirmed in
                    commitToStore(rows: confirmed)
                    showConfirmSheet = false
                    pasteText  = ""
                    parsedRows = []
                    failedRows = []
                },
                onCancel: { showConfirmSheet = false }
            )
            .environmentObject(store)
        }
    }

    // MARK: 入库逻辑
    private func commitToStore(rows: [ParsedRow]) {
        var batchImported = 0
        var batchFull     = 0
        let batchID       = UUID()

        for row in rows {
            // 流水记录：只追加转化，不新增客户，不计入营业额
            // 注意：流水金额也不写入 ConversionRecord.amount（因为尚未成交）
            if row.dataType == .ledgerEntry {
                // 流水关联：姓名+电话双重匹配，避免同名不同人误关联
                let matchPhone = row.phone
                if let idx = store.customers.firstIndex(where: {
                    $0.name == row.name &&
                    $0.dataType == .fullCustomer &&
                    (matchPhone == nil || $0.phone == matchPhone)
                }) {
                    // 仅记录跟进事件，金额为 0（实际成交时再手动录入）
                    let record = ConversionRecord(
                        type:        row.conversionType,
                        amount:      0,
                        date:        Date(),
                        productNote: row.productNote
                    )
                    store.customers[idx].conversions.append(record)
                    store.save()
                }
                continue
            }

            // 完整客户：leadAmount 存入 Customer，不进 ConversionRecord
            let phone           = row.phone ?? "unknown_\(UUID().uuidString.prefix(8))"
            let currentLineCost = store.settings.leadUnitPrice  // 固化当前单价
            if let idx = store.customers.firstIndex(where: { $0.phone == phone }) {
                if let newAmt = row.leadAmount {
                    store.customers[idx].leadAmount = newAmt
                    store.save()
                }
            } else {
                let customer = Customer(
                    name:          row.name,
                    phone:         phone,
                    address:       row.address,
                    age:           row.age,
                    height:        row.height,
                    weight:        row.weight,
                    gender:        row.gender,
                    leadAmount:    row.leadAmount,
                    lineCost:      currentLineCost,
                    dataType:      .fullCustomer,
                    importBatchID: batchID,
                    importDate:    Date()
                )
                store.addCustomer(customer)
                batchFull += 1
            }
            batchImported += 1
        }

        let batch = ImportBatch(
            id:                batchID,
            source:            "智能粘贴",
            importDate:        Date(),
            recordCount:       batchImported,
            fullCustomerCount: batchFull
        )
        store.addBatch(batch)
    }
}

// MARK: - 确认弹窗 Sheet
struct ImportConfirmSheet: View {

    @EnvironmentObject var store: DataStore
    let rows:      [ParsedRow]
    let failed:    [ParseFailedRow]
    let onConfirm: ([ParsedRow]) -> Void
    let onCancel:  () -> Void

    // 同名+电话冲突（完整客户）
    @State private var conflictRow:       ParsedRow?
    @State private var showConflict       = false
    @State private var confirmedRows:     [ParsedRow]
    @State private var pendingQueue:      [ParsedRow]
    @State private var processedRows:     [ParsedRow] = []

    // 前置同名绑定（流水行）
    @State private var bindingRow:        ParsedRow?
    @State private var bindingCandidates: [Customer] = []
    @State private var showBindingSheet   = false

    init(rows: [ParsedRow], failed: [ParseFailedRow],
         onConfirm: @escaping ([ParsedRow]) -> Void,
         onCancel: @escaping () -> Void) {
        self.rows      = rows
        self.failed    = failed
        self.onConfirm = onConfirm
        self.onCancel  = onCancel
        _confirmedRows = State(initialValue: rows)
        _pendingQueue  = State(initialValue: [])
    }

    var fullCustomerCount: Int { confirmedRows.filter { $0.isFullCustomer }.count }
    var ledgerCount:       Int { confirmedRows.filter { $0.dataType == .ledgerEntry }.count }

    var body: some View {
        NavigationView {
            List {
                // 汇总卡
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("共解析 \(confirmedRows.count) 条")
                                .font(.headline)
                            Text("新客户 \(fullCustomerCount) 人 · 流水记录 \(ledgerCount) 条")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green).font(.title2)
                    }
                    .padding(.vertical, 4)
                }

                // 逐条预览
                Section(header: Text("解析结果预览（可左滑删除不需要的行）")) {
                    ForEach($confirmedRows) { $row in
                        ParsedRowCell(row: $row)
                    }
                    .onDelete { indexSet in
                        confirmedRows.remove(atOffsets: indexSet)
                    }
                }

                // 失败行
                if !failed.isEmpty {
                    Section(header: Text("未能解析（\(failed.count) 行）").foregroundColor(.red)) {
                        ForEach(failed) { f in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.rawLine).font(.caption.monospaced()).lineLimit(2)
                                Text(f.reason).font(.caption2).foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("确认导入数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认入库（\(confirmedRows.count)条）") {
                        handleConfirm()
                    }
                    .disabled(confirmedRows.isEmpty)
                    .font(.headline)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel) { onCancel() }
                }
            }
        }
        // 同名+电话完整客户冲突弹窗（原有）
        .confirmationDialog(
            conflictRow.map { "发现重复：\($0.name)（\($0.phone ?? "")）" } ?? "重复数据",
            isPresented: $showConflict,
            titleVisibility: .visible
        ) {
            Button("覆盖原记录", role: .destructive) { resolveConflict(.overwrite) }
            Button("追加转化记录（合并）")              { resolveConflict(.merge)     }
            Button("跳过此条",  role: .cancel)        { resolveConflict(.skip)      }
        } message: {
            Text("该电话号码在数据库中已存在，请选择处理方式。")
        }
        // 前置同名绑定 Sheet（新增）
        .sheet(isPresented: $showBindingSheet) {
            if let row = bindingRow {
                NameBindingSheet(
                    row:        row,
                    candidates: bindingCandidates,
                    onBind:     { target in handleBind(row: row, to: target) },
                    onNew:      { handleBindAsNew(row: row) }
                )
                .environmentObject(store)
            }
        }
    }

    // MARK: ── 确认入库：先处理流水行同名拦截，再处理完整客户冲突
    private func handleConfirm() {
        // 把所有行放入待处理队列，逐条过一遍
        pendingQueue  = confirmedRows
        processedRows = []
        processNextPending()
    }

    private func processNextPending() {
        guard !pendingQueue.isEmpty else {
            // 队列清空：对 processedRows 里的完整客户再做电话冲突检测
            checkFullCustomerConflicts()
            return
        }

        let row = pendingQueue.removeFirst()

        // 流水行：检索同名客户，有则弹绑定 Sheet
        if row.dataType == .ledgerEntry {
            let matches = store.customers.filter {
                $0.name == row.name && $0.dataType == .fullCustomer
            }
            if !matches.isEmpty {
                bindingRow        = row
                bindingCandidates = matches
                showBindingSheet  = true
                // 流程在此挂起，等用户在 NameBindingSheet 选择后回调
                return
            }
            // 没有同名客户，流水行直接放入 processed（commitToStore 会处理）
            processedRows.append(row)
            processNextPending()
            return
        }

        // 完整客户行：直接放入 processed，后续统一做电话冲突检测
        processedRows.append(row)
        processNextPending()
    }

    // 用户选择「绑定到此客户」
    private func handleBind(row: ParsedRow, to target: Customer) {
        showBindingSheet = false
        // 把成交金额作为 ConversionRecord 写入目标客户
        if let idx = store.customers.firstIndex(where: { $0.id == target.id }) {
            let record = ConversionRecord(
                type:        row.conversionType,
                amount:      row.leadAmount ?? 0,
                date:        Date(),
                productNote: row.productNote
            )
            store.customers[idx].conversions.append(record)
            store.save()
        }
        bindingRow = nil
        processNextPending()
    }

    // 用户选择「新建独立客户」
    private func handleBindAsNew(row: ParsedRow) {
        showBindingSheet = false
        // 把这条流水行以 fullCustomer 身份放入 processed
        var newRow          = row
        newRow.dataType     = .fullCustomer
        processedRows.append(newRow)
        bindingRow = nil
        processNextPending()
    }

    // MARK: ── 完整客户电话冲突检测（原有逻辑）
    private func checkFullCustomerConflicts() {
        let conflicting = processedRows.filter { row in
            guard let phone = row.phone else { return false }
            return store.customers.contains {
                $0.phone == phone && $0.name == row.name
            }
        }
        if conflicting.isEmpty {
            onConfirm(processedRows)
        } else {
            let queue     = conflicting
            let clean     = processedRows.filter { row in
                guard let phone = row.phone else { return true }
                return !store.customers.contains {
                    $0.phone == phone && $0.name == row.name
                }
            }
            // 重置队列，借用原有 conflictRow 流程
            pendingQueue  = queue
            processedRows = clean
            showNextConflict()
        }
    }

    private func showNextConflict() {
        guard !pendingQueue.isEmpty else {
            onConfirm(processedRows)
            return
        }
        conflictRow = pendingQueue.removeFirst()
        showConflict = true
    }

    private func resolveConflict(_ resolution: DuplicateResolution) {
        guard let row = conflictRow, let phone = row.phone else {
            showNextConflict(); return
        }
        switch resolution {
        case .skip: break
        case .overwrite, .merge:
            if var existing = store.findExisting(phone: phone) {
                if resolution == .overwrite {
                    var newCustomer  = existing
                    newCustomer.name    = row.name
                    newCustomer.address = row.address ?? existing.address
                    newCustomer.age        = row.age        ?? existing.age
                    newCustomer.height     = row.height     ?? existing.height
                    newCustomer.weight     = row.weight     ?? existing.weight
                    newCustomer.gender     = row.gender != "未知" ? row.gender : existing.gender
                    newCustomer.leadAmount = row.leadAmount ?? existing.leadAmount
                    store.updateCustomer(newCustomer)
                } else {
                    existing.leadAmount = row.leadAmount ?? existing.leadAmount
                    store.updateCustomer(existing)
                }
            }
        }
        conflictRow = nil
        showNextConflict()
    }
}

// MARK: - 单行预览卡片（可编辑）
struct ParsedRowCell: View {
    @Binding var row: ParsedRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // 类型标签
                Text(row.dataType == .fullCustomer ? "新客户" : "流水")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(row.dataType == .fullCustomer
                                ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15))
                    .foregroundColor(row.dataType == .fullCustomer ? .blue : .orange)
                    .cornerRadius(4)

                Text(row.name).fontWeight(.semibold)
                Spacer()
                if let amt = row.leadAmount {
                    Text("¥\(Int(amt))").fontWeight(.bold).foregroundColor(.green)
                }
            }

            if let phone = row.phone {
                Text(phone).font(.caption).foregroundColor(.secondary)
            }
            if let addr = row.address {
                Text(addr).font(.caption2).foregroundColor(.secondary).lineLimit(1)
            }

            HStack(spacing: 12) {
                Text(row.conversionType.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)

                if let age = row.age    { Text("\(age)岁").font(.caption2).foregroundColor(.secondary) }
                if let h   = row.height { Text("\(Int(h))cm").font(.caption2).foregroundColor(.secondary) }
                if let w   = row.weight { Text("\(Int(w))kg").font(.caption2).foregroundColor(.secondary) }
                if row.gender != "未知" { Text(row.gender).font(.caption2).foregroundColor(.secondary) }
                if let p   = row.productNote { Text(p).font(.caption2).foregroundColor(.secondary).lineLimit(1) }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 前置同名绑定 Sheet
struct NameBindingSheet: View {

    @Environment(\.dismiss) var dismiss
    let row:        ParsedRow
    let candidates: [Customer]
    let onBind:     (Customer) -> Void
    let onNew:      () -> Void

    // 「查看完整资料」用 sheet(item:) 驱动，关闭后无缝返回本面板
    @State private var previewCustomer: Customer? = nil

    var body: some View {
        NavigationView {
            List {

                // ── 本次录入内容摘要 ──────────────────────────
                Section(header: Text("本次录入内容")) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Text(String(row.name.prefix(1)))
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.orange)
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.name).fontWeight(.semibold)
                            Text(row.conversionType.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }
                        Spacer()
                        if let amt = row.leadAmount {
                            Text("¥\(Int(amt))")
                                .font(.title3).fontWeight(.bold).foregroundColor(.green)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // ── 同名候选客户：每条独立展示，两个互斥按钮 ──
                Section(header: Text("系统中检索到 \(candidates.count) 位同名客户")) {
                    ForEach(candidates) { candidate in
                        VStack(alignment: .leading, spacing: 10) {

                            // 客户简要信息行
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color.blue.opacity(0.12))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Text(String(candidate.name.prefix(1)))
                                            .font(.subheadline).fontWeight(.semibold)
                                            .foregroundColor(.blue)
                                    )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(candidate.name).fontWeight(.semibold)
                                    Text(candidate.phone)
                                        .font(.caption).foregroundColor(.secondary)
                                    HStack(spacing: 6) {
                                        if let h = candidate.height {
                                            Text("\(Int(h))cm").font(.caption2).foregroundColor(.secondary)
                                        }
                                        if let w = candidate.weight {
                                            Text("\(Int(w))kg").font(.caption2).foregroundColor(.secondary)
                                        }
                                        if candidate.gender != "未知" {
                                            Text(candidate.gender).font(.caption2).foregroundColor(.secondary)
                                        }
                                        if let addr = candidate.address {
                                            Text(String(addr.prefix(10)))
                                                .font(.caption2).foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                Spacer()
                                // 查看完整资料入口
                                Button {
                                    previewCustomer = candidate
                                } label: {
                                    Label("完整资料", systemImage: "doc.text.magnifyingglass")
                                        .font(.caption)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(Color(.secondarySystemGroupedBackground))
                                        .cornerRadius(8)
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                            }

                            // 互斥操作按钮组
                            HStack(spacing: 10) {
                                // 按钮A：追加到该已有客户
                                Button {
                                    onBind(candidate)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "person.crop.circle.badge.checkmark")
                                        Text("追加到此客户")
                                    }
                                    .font(.subheadline).fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)

                                // 按钮B：作为同名新客户写入
                                Button {
                                    onNew()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "person.badge.plus")
                                        Text("同名新客户")
                                    }
                                    .font(.subheadline).fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundColor(.orange)
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                // ── 底部：直接新建（无需对照已有客户）────────
                Section {
                    Button {
                        onNew()
                    } label: {
                        HStack {
                            Spacer()
                            Label("直接新建独立客户", systemImage: "plus.circle")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("检测到同名客户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("跳过此条", role: .cancel) { onNew() }
                }
            }
        }
        // 查看完整客户资料（关闭后无缝返回本面板）
        .sheet(item: $previewCustomer) { customer in
            NavigationView {
                CustomerDetailView(customer: customer)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("关闭") { previewCustomer = nil }
                        }
                    }
            }
        }
    }
}
