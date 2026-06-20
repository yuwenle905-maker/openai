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
    // 到达这里的行已经过用户的所有弹窗确认，直接写入
    private func commitToStore(rows: [ParsedRow]) {
        var batchImported = 0
        var batchFull     = 0
        let batchID       = UUID()

        for row in rows {
            // 流水记录：只追加转化，不新增客户，不计入营业额
            if row.dataType == .ledgerEntry {
                // 姓名+电话双重匹配，避免同名不同人误关联
                let matchPhone = row.phone
                if let idx = store.customers.firstIndex(where: {
                    $0.name == row.name &&
                    $0.dataType == .fullCustomer &&
                    (matchPhone == nil || $0.phone == matchPhone)
                }) {
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

            // 完整客户写入（forceNew = true 时强制新 UUID，不走电话查重）
            let phone           = row.phone ?? "unknown_\(UUID().uuidString.prefix(8))"
            let currentLineCost = store.settings.leadUnitPrice
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
            batchFull    += 1
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

    @State private var confirmedRows: [ParsedRow]
    @State private var pendingQueue:  [ParsedRow] = []
    @State private var processedRows: [ParsedRow] = []

    // 同名同电话二次确认 Sheet（需求3）
    @State private var showDoubleCheckSheet = false
    @State private var doubleCheckRow:       ParsedRow?
    @State private var doubleCheckExisting:  Customer?

    init(rows: [ParsedRow], failed: [ParseFailedRow],
         onConfirm: @escaping ([ParsedRow]) -> Void,
         onCancel: @escaping () -> Void) {
        self.rows      = rows
        self.failed    = failed
        self.onConfirm = onConfirm
        self.onCancel  = onCancel
        _confirmedRows = State(initialValue: rows)
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
                        startProcessing()
                    }
                    .disabled(confirmedRows.isEmpty)
                    .font(.headline)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel) { onCancel() }
                }
            }
        }
        // 同名同电话二次确认 Sheet（需求3）
        .sheet(isPresented: $showDoubleCheckSheet) {
            if let row = doubleCheckRow, let existing = doubleCheckExisting {
                DoubleCheckSheet(
                    incomingRow: row,
                    existing:    existing,
                    onMerge:     { handleMerge(row: row, into: existing) },
                    onForceNew:  { handleForceNew(row: row) }
                )
                .environmentObject(store)
            }
        }
    }

    // MARK: ── 处理队列入口
    private func startProcessing() {
        pendingQueue  = confirmedRows
        processedRows = []
        processNext()
    }

    private func processNext() {
        guard !pendingQueue.isEmpty else {
            onConfirm(processedRows)
            return
        }
        let row = pendingQueue.removeFirst()

        // 流水行：姓名+电话匹配 → 直接放行（commitToStore 负责写入）
        // 同名但电话不同 → 不拦截，也直接放行作新客户
        if row.dataType == .ledgerEntry {
            processedRows.append(row)
            processNext()
            return
        }

        // 完整客户行：检查是否同名同电话
        guard let phone = row.phone else {
            // 无电话：直接新建，不拦截
            processedRows.append(row)
            processNext()
            return
        }

        // 同名且同电话：拦截弹窗，等用户决策（需求2+3）
        if let existing = store.customers.first(where: {
            $0.phone == phone && $0.name == row.name && $0.dataType == .fullCustomer
        }) {
            doubleCheckRow      = row
            doubleCheckExisting = existing
            showDoubleCheckSheet = true
            return   // 挂起，等回调
        }

        // 同名但电话不同：静默新建（需求2）
        processedRows.append(row)
        processNext()
    }

    // 用户选「合并/追加到已有客户」
    private func handleMerge(row: ParsedRow, into existing: Customer) {
        showDoubleCheckSheet = false
        if let idx = store.customers.firstIndex(where: { $0.id == existing.id }) {
            let record = ConversionRecord(
                type:        row.conversionType,
                amount:      row.leadAmount ?? 0,
                date:        Date(),
                productNote: row.productNote
            )
            store.customers[idx].conversions.append(record)
            if let newAmt = row.leadAmount {
                store.customers[idx].leadAmount = newAmt
            }
            store.save()
        }
        doubleCheckRow      = nil
        doubleCheckExisting = nil
        processNext()
    }

    // 用户选「作为独立新客户写入」
    private func handleForceNew(row: ParsedRow) {
        showDoubleCheckSheet = false
        processedRows.append(row)   // 带原始 phone 进 commitToStore，生成新 UUID
        doubleCheckRow      = nil
        doubleCheckExisting = nil
        processNext()
    }
}

// MARK: - 单行预览卡片
struct ParsedRowCell: View {
    @Binding var row: ParsedRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
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

// MARK: - 同名同电话二次确认 Sheet（需求3）
struct DoubleCheckSheet: View {

    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) var dismiss

    let incomingRow: ParsedRow
    let existing:    Customer
    let onMerge:     () -> Void
    let onForceNew:  () -> Void

    @State private var previewCustomer: Customer? = nil

    var body: some View {
        NavigationView {
            List {

                // ── 本次录入内容 ──────────────────────────────
                Section(header: Text("本次录入内容")) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 38, height: 38)
                            .overlay(
                                Text(String(incomingRow.name.prefix(1)))
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.orange)
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(incomingRow.name).fontWeight(.semibold)
                            HStack(spacing: 6) {
                                Text(incomingRow.conversionType.rawValue)
                                    .font(.caption)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.12))
                                    .foregroundColor(.orange)
                                    .cornerRadius(4)
                                if let p = incomingRow.phone {
                                    Text(p).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                        Spacer()
                        if let amt = incomingRow.leadAmount {
                            Text("¥\(Int(amt))")
                                .font(.title3).fontWeight(.bold).foregroundColor(.green)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // ── 系统已有客户档案 ──────────────────────────
                Section(header: Text("系统中已有同名同电话客户")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color.blue.opacity(0.12))
                                .frame(width: 38, height: 38)
                                .overlay(
                                    Text(String(existing.name.prefix(1)))
                                        .font(.subheadline).fontWeight(.semibold)
                                        .foregroundColor(.blue)
                                )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(existing.name).fontWeight(.semibold)
                                Text(existing.phone)
                                    .font(.caption).foregroundColor(.secondary)
                                HStack(spacing: 6) {
                                    if let h = existing.height { Text("\(Int(h))cm").font(.caption2).foregroundColor(.secondary) }
                                    if let w = existing.weight { Text("\(Int(w))kg").font(.caption2).foregroundColor(.secondary) }
                                    if existing.gender != "未知" { Text(existing.gender).font(.caption2).foregroundColor(.secondary) }
                                    Text("已转化 \(existing.conversions.count) 次")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                                if let addr = existing.address {
                                    Text(String(addr.prefix(20)))
                                        .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            // 查看完整资料卡入口
                            Button {
                                previewCustomer = existing
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: "doc.text.magnifyingglass")
                                        .font(.title3)
                                    Text("完整资料")
                                        .font(.caption2)
                                }
                                .foregroundColor(.blue)
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .background(Color(.secondarySystemGroupedBackground))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // ── 双通道选择按钮 ────────────────────────────
                Section(header: Text("请选择处理方式")) {
                    // 按钮A：合并追加
                    Button {
                        onMerge()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("合并 / 追加到该已有客户")
                                    .font(.subheadline).fontWeight(.semibold)
                                Text("金额和备注将累加到老档案中")
                                    .font(.caption).foregroundColor(.white.opacity(0.8))
                            }
                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)

                    // 按钮B：强制新建
                    Button {
                        onForceNew()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.badge.plus")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("作为独立新客户写入")
                                    .font(.subheadline).fontWeight(.semibold)
                                Text("生成全新 UUID，与上方客户完全独立")
                                    .font(.caption).foregroundColor(.orange.opacity(0.8))
                            }
                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.12))
                        .foregroundColor(.orange)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("发现同名同电话客户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("跳过此条", role: .cancel) { onForceNew() }
                }
            }
        }
        // 查看完整资料卡（关闭后无缝返回本 Sheet）
        .sheet(item: $previewCustomer) { customer in
            NavigationView {
                CustomerDetailView(customer: customer)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("关闭") { previewCustomer = nil }
                        }
                    }
            }
            .environmentObject(store)
        }
    }
}
