// MARK: - TextInputView.swift
// 手动流水录入界面（iOS 15 兼容）

import SwiftUI

struct TextInputView: View {

    @EnvironmentObject var store: DataStore
    @State private var inputText:    String = ""
    @State private var parseResults: [TextParseResult] = []
    @State private var parseErrors:  [TextParseError]  = []
    @State private var showPreview:  Bool = false
    @State private var savedCount:   Int  = 0
    @State private var showSaveToast: Bool = false
    @State private var toastMessage:  String = ""
    @FocusState private var editorFocused: Bool

    // 同名匹配确认面板
    @State private var pendingSaveQueue:  [TextParseResult] = []
    @State private var currentPending:    TextParseResult?
    @State private var currentCandidates: [Customer] = []
    @State private var showMatchSheet:    Bool = false
    @State private var matchedCount:      Int = 0
    @State private var orphanedCount:     Int = 0

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {

                    // ── 说明卡片 ──────────────────────────────────
                    VStack(alignment: .leading, spacing: 4) {
                        Text("流水录入").font(.headline)
                        Text("格式：姓名 状态 金额（此处金额计入营业额）")
                            .font(.caption).foregroundColor(.secondary)
                        Text("例：张三 新单 4280  /  张三 五次 168000")
                            .font(.caption).foregroundColor(.secondary)
                        Text("⚠️ 姓名需与已导入的客户一致，否则仅记录为待关联流水")
                            .font(.caption2).foregroundColor(.orange)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // ── 输入框 ───────────────────────────────────
                    TextEditor(text: $inputText)
                        .focused($editorFocused)
                        .font(.body.monospaced())
                        .frame(minHeight: 160, maxHeight: 240)
                        .padding(8)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)

                    // ── 操作按钮 ─────────────────────────────────
                    HStack(spacing: 12) {
                        Button("解析预览") {
                            editorFocused = false
                            let r = TextParser.parse(inputText)
                            parseResults = r.results
                            parseErrors  = r.errors
                            showPreview  = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("收起键盘") { editorFocused = false }
                            .buttonStyle(.bordered).tint(.secondary)

                        Button("清空") {
                            editorFocused = false
                            inputText = ""; parseResults = []; parseErrors = []; showPreview = false
                        }
                        .buttonStyle(.bordered).tint(.red)
                    }
                    .padding(.horizontal)

                    // ── 解析预览区 ───────────────────────────────
                    if showPreview {

                        if !parseResults.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("解析成功 (\(parseResults.count) 条)")
                                    .font(.caption).foregroundColor(.secondary)
                                    .padding(.horizontal).padding(.top, 8)
                                Divider()
                                ForEach(parseResults) { r in
                                    let candidates = store.customers.filter {
                                        $0.name == r.name && $0.dataType == .fullCustomer
                                    }
                                    HStack(alignment: .top, spacing: 8) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 6) {
                                                Text(r.name).fontWeight(.semibold)
                                                if !candidates.isEmpty {
                                                    Text("已匹配 \(candidates.count) 位客户")
                                                        .font(.caption2)
                                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                                        .background(Color.green.opacity(0.15))
                                                        .foregroundColor(.green)
                                                        .cornerRadius(4)
                                                } else {
                                                    Text("未找到客户")
                                                        .font(.caption2)
                                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                                        .background(Color.orange.opacity(0.15))
                                                        .foregroundColor(.orange)
                                                        .cornerRadius(4)
                                                }
                                            }
                                            Text(r.rawLine)
                                                .font(.caption.monospaced())
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 3) {
                                            Text(r.conversionType.rawValue)
                                                .font(.caption)
                                                .padding(.horizontal, 8).padding(.vertical, 2)
                                                .background(conversionColor(r.conversionType).opacity(0.15))
                                                .foregroundColor(conversionColor(r.conversionType))
                                                .clipShape(Capsule())
                                            Text("¥\(Int(r.amount))")
                                                .fontWeight(.semibold).foregroundColor(.green)
                                        }
                                    }
                                    .padding(.horizontal).padding(.vertical, 8)
                                    Divider()
                                }
                            }
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

                        if !parseErrors.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("解析失败 (\(parseErrors.count) 行)")
                                    .font(.caption).foregroundColor(.red)
                                    .padding(.horizontal).padding(.top, 8)
                                Divider()
                                ForEach(parseErrors) { e in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("第 \(e.lineNumber) 行：\(e.rawLine)")
                                            .font(.caption.monospaced())
                                        Text(e.reason).font(.caption2).foregroundColor(.red)
                                    }
                                    .padding(.horizontal).padding(.vertical, 6)
                                    Divider()
                                }
                            }
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

                        if !parseResults.isEmpty {
                            Button { startSaveFlow() } label: {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("保存 \(parseResults.count) 条转化记录")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(14)
                            }
                            .padding(.horizontal)
                        }
                    }

                    // ── 流水待关联列表 ────────────────────────────
                    let orphans = store.customers.filter {
                        $0.dataType == .ledgerEntry && $0.phone.hasPrefix("待补全_")
                    }
                    if !orphans.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text("待关联流水（\(orphans.count) 条）")
                                    .font(.caption.bold()).foregroundColor(.orange)
                                Spacer()
                                Text("先导入完整客户后系统自动关联")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                            .padding(.horizontal).padding(.top, 8)
                            Divider()
                            ForEach(orphans) { c in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(c.name).fontWeight(.semibold)
                                    ForEach(c.conversions) { rec in
                                        HStack {
                                            Text(rec.type.rawValue).font(.caption)
                                                .foregroundColor(conversionColor(rec.type))
                                            Spacer()
                                            Text("¥\(Int(rec.amount))")
                                                .font(.caption).foregroundColor(.green)
                                            Text(rec.date.formatted(date: .abbreviated, time: .omitted))
                                                .font(.caption2).foregroundColor(.secondary)
                                        }
                                    }
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
            }
            .onTapGesture { editorFocused = false }
            .navigationTitle("流水录入")
            .background(Color(.systemGroupedBackground))
            .overlay(alignment: .bottom) {
                if showSaveToast {
                    Text(toastMessage)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .padding(.bottom, 32)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        // 同名匹配确认面板
        .sheet(isPresented: $showMatchSheet) {
            if let result = currentPending {
                LedgerMatchSheet(
                    result:     result,
                    candidates: currentCandidates,
                    onAppend:   { target in handleAppend(result: result, to: target) },
                    onNewEntry: { handleNewEntry(result: result) }
                )
                .environmentObject(store)
            }
        }
    }

    // MARK: ── 保存入口：拦截有同名客户的条目
    private func startSaveFlow() {
        editorFocused  = false
        matchedCount   = 0
        orphanedCount  = 0
        pendingSaveQueue = parseResults
        processNextSave()
    }

    private func processNextSave() {
        guard !pendingSaveQueue.isEmpty else {
            // 全部处理完，清场并显示 toast
            finalizeSave()
            return
        }
        let result = pendingSaveQueue.removeFirst()
        let candidates = store.customers.filter {
            $0.name == result.name && $0.dataType == .fullCustomer
        }
        if candidates.isEmpty {
            // 无同名客户：直接存为孤儿流水
            writeOrphan(result: result)
            orphanedCount += 1
            processNextSave()
        } else {
            // 有同名客户：弹出确认面板，挂起队列
            currentPending    = result
            currentCandidates = candidates
            showMatchSheet    = true
        }
    }

    // 用户选「追加到已有客户」
    private func handleAppend(result: TextParseResult, to target: Customer) {
        showMatchSheet = false
        if let idx = store.customers.firstIndex(where: { $0.id == target.id }) {
            let record = ConversionRecord(
                type:   result.conversionType,
                amount: result.amount,
                date:   Date()
            )
            store.customers[idx].conversions.append(record)
            store.save()
            matchedCount += 1
        }
        currentPending    = nil
        currentCandidates = []
        processNextSave()
    }

    // 用户选「作为同名新客户写入」
    private func handleNewEntry(result: TextParseResult) {
        showMatchSheet = false
        writeOrphan(result: result)
        orphanedCount += 1
        currentPending    = nil
        currentCandidates = []
        processNextSave()
    }

    // 写入孤儿流水（无同名客户，或用户强制新建）
    private func writeOrphan(result: TextParseResult) {
        let record = ConversionRecord(
            type:   result.conversionType,
            amount: result.amount,
            date:   Date()
        )
        let orphan = Customer(
            name:        result.name,
            phone:       "待补全_\(result.name)_\(UUID().uuidString.prefix(6))",
            dataType:    .ledgerEntry,
            importDate:  Date(),
            conversions: [record]
        )
        store.customers.append(orphan)
        store.save()
    }

    // 全部处理完毕：清场 + toast
    private func finalizeSave() {
        parseResults = []
        parseErrors  = []
        inputText    = ""
        showPreview  = false

        if orphanedCount == 0 {
            toastMessage = "✅ 已关联 \(matchedCount) 条转化记录到客户"
        } else if matchedCount == 0 {
            toastMessage = "⚠️ \(orphanedCount) 条暂存为待关联流水（客户未找到）"
        } else {
            toastMessage = "✅ 关联 \(matchedCount) 条，⚠️ \(orphanedCount) 条待关联"
        }
        withAnimation { showSaveToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { showSaveToast = false }
        }
    }

    private func conversionColor(_ type: ConversionType) -> Color {
        switch type {
        case .newOrder: return .blue
        case .second:   return .green
        case .third:    return .orange
        case .fourth:   return .purple
        case .fifth:    return .red
        case .sixth:    return .indigo
        case .seventh:  return Color(red: 0, green: 0.5, blue: 0.5)
        case .eighth:   return Color(red: 0, green: 0.7, blue: 0.9)
        case .unknown:  return .gray
        }
    }
}

// MARK: - 流水同名匹配确认面板
struct LedgerMatchSheet: View {

    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) var dismiss

    let result:     TextParseResult
    let candidates: [Customer]
    let onAppend:   (Customer) -> Void
    let onNewEntry: () -> Void

    @State private var previewCustomer: Customer? = nil

    var body: some View {
        NavigationView {
            List {

                // ── 本次录入内容摘要 ──────────────────────────
                Section(header: Text("本次录入内容")) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 38, height: 38)
                            .overlay(
                                Text(String(result.name.prefix(1)))
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.orange)
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.name).fontWeight(.semibold)
                            Text(result.conversionType.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }
                        Spacer()
                        Text("¥\(Int(result.amount))")
                            .font(.title3).fontWeight(.bold).foregroundColor(.green)
                    }
                    .padding(.vertical, 4)
                }

                // ── 同名候选客户（每条独立，两个互斥按钮） ──
                Section(header: Text("请你决定如何处理（系统不会自动匹配）")) {
                    ForEach(candidates) { candidate in
                        VStack(alignment: .leading, spacing: 10) {

                            // 客户简要信息 + 查看完整资料按钮
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
                                        Text("转化\(candidate.conversions.count)次")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                    if let addr = candidate.address {
                                        Text(String(addr.prefix(15)))
                                            .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                                Button {
                                    previewCustomer = candidate
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

                            // 互斥操作按钮组（视觉完全平等，由你决定）
                            HStack(spacing: 10) {
                                // 按钮A：绑定到该已有客户
                                Button {
                                    onAppend(candidate)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "link.circle.fill")
                                        Text("绑定到该客户")
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .foregroundColor(.blue)
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.blue.opacity(0.4), lineWidth: 1.5)
                                    )
                                }
                                .buttonStyle(.plain)

                                // 按钮B：作为同名新客户写入
                                Button {
                                    onNewEntry()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "person.badge.plus")
                                        Text("同名新客户")
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .foregroundColor(.orange)
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.orange.opacity(0.4), lineWidth: 1.5)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                // ── 底部兜底：直接新建 ────────────────────────
                Section {
                    Button { onNewEntry() } label: {
                        HStack {
                            Spacer()
                            Label("跳过匹配，直接新建独立记录", systemImage: "plus.circle")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("请选择处理方式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("新建独立记录", role: .cancel) { onNewEntry() }
                }
            }
        }
        // 查看完整资料（关闭后无缝返回本面板）
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
