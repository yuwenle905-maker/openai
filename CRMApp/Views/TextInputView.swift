// MARK: - TextInputView.swift
// 手动流水录入界面（iOS 15 兼容）

import SwiftUI

// MARK: - 活跃 Sheet 枚举，确保同一时刻只有一个 sheet 存在，彻底防止白屏死锁
private enum ActiveSheet: Identifiable {
    case newCustomer(TextParseResult)   // 场景A：库中无此人，建新档
    case matchExisting(TextParseResult, [Customer])  // 场景B：库中有同名，让用户选择

    var id: String {
        switch self {
        case .newCustomer(let r):       return "new_\(r.id)"
        case .matchExisting(let r, _):  return "match_\(r.id)"
        }
    }
}

struct TextInputView: View {

    @EnvironmentObject var store: DataStore
    @State private var inputText:    String = ""
    @State private var parseResults: [TextParseResult] = []
    @State private var parseErrors:  [TextParseError]  = []
    @State private var showPreview:  Bool = false
    @State private var showSaveToast: Bool = false
    @State private var toastMessage:  String = ""
    @FocusState private var editorFocused: Bool

    // 单一 sheet 驱动源，杜绝多 sheet 并发
    @State private var activeSheet:    ActiveSheet? = nil
    @State private var pendingQueue:   [TextParseResult] = []
    @State private var matchedCount:   Int = 0
    @State private var newBuiltCount:  Int = 0

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
                        Text("库中无此客户时，系统引导你建立新档案")
                            .font(.caption2).foregroundColor(.blue)
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
                            inputText = ""
                            parseResults = []
                            parseErrors  = []
                            showPreview  = false
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
                                                    Text("已匹配 \(candidates.count) 位")
                                                        .font(.caption2)
                                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                                        .background(Color.green.opacity(0.15))
                                                        .foregroundColor(.green).cornerRadius(4)
                                                } else {
                                                    Text("新客户")
                                                        .font(.caption2)
                                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                                        .background(Color.blue.opacity(0.12))
                                                        .foregroundColor(.blue).cornerRadius(4)
                                                }
                                            }
                                            Text(r.rawLine)
                                                .font(.caption.monospaced())
                                                .foregroundColor(.secondary).lineLimit(1)
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
                            // 保存按钮文案根据匹配情况动态变化
                            let allNew = parseResults.allSatisfy { r in
                                store.customers.filter { c in
                                    c.name == r.name && c.dataType == .fullCustomer
                                }.isEmpty
                            }
                            let firstNewName = parseResults.first(where: { r in
                                store.customers.filter { c in
                                    c.name == r.name && c.dataType == .fullCustomer
                                }.isEmpty
                            })?.name

                            let buttonLabel: String = {
                                if allNew && parseResults.count == 1, let n = firstNewName {
                                    return "保存并新建客户：\(n)"
                                }
                                return "保存 \(parseResults.count) 条转化记录"
                            }()

                            Button { startSaveFlow() } label: {
                                HStack {
                                    Image(systemName: allNew && parseResults.count == 1
                                          ? "person.crop.circle.badge.plus"
                                          : "checkmark.circle.fill")
                                    Text(buttonLabel).fontWeight(.semibold)
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
        // 单一 sheet 驱动，彻底防止多 sheet 并发白屏
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newCustomer(let result):
                NewCustomerFromLedgerSheet(
                    result:   result,
                    onCreate: { customerNumber in
                        activeSheet = nil
                        DispatchQueue.main.async {
                            commitNewCustomer(result: result, customerNumber: customerNumber)
                            processNextSave()
                        }
                    }
                )
                .environmentObject(store)

            case .matchExisting(let result, let candidates):
                LedgerMatchSheet(
                    result:     result,
                    candidates: candidates,
                    onAppend: { target in
                        activeSheet = nil
                        DispatchQueue.main.async {
                            appendToExisting(result: result, target: target)
                            processNextSave()
                        }
                    },
                    onNewEntry: {
                        // 转到场景A弹窗，让用户填编号
                        activeSheet = .newCustomer(result)
                    }
                )
                .environmentObject(store)
            }
        }
    }

    // MARK: ── 保存主流程
    private func startSaveFlow() {
        editorFocused   = false
        matchedCount    = 0
        newBuiltCount   = 0
        pendingQueue    = parseResults
        processNextSave()
    }

    private func processNextSave() {
        guard !pendingQueue.isEmpty else {
            finalizeSave()
            return
        }
        let result = pendingQueue.removeFirst()
        // 防御性过滤：确保结果非空且不引发 nil 解包
        let candidates = store.customers.filter {
            !$0.name.isEmpty &&
            $0.name == result.name &&
            $0.dataType == .fullCustomer
        }
        if candidates.isEmpty {
            // 场景A：无匹配 → 弹新建档案面板
            activeSheet = .newCustomer(result)
        } else {
            // 场景B：有匹配 → 弹绑定确认面板
            activeSheet = .matchExisting(result, candidates)
        }
    }

    private func commitNewCustomer(result: TextParseResult, customerNumber: String?) {
        let record = ConversionRecord(
            type:   result.conversionType,
            amount: result.amount,
            date:   Date()
        )
        let numStr = customerNumber?.trimmingCharacters(in: .whitespaces)
        let newCustomer = Customer(
            name:           result.name,
            phone:          "待补全_\(UUID().uuidString.prefix(8))",
            customerNumber: (numStr?.isEmpty == false) ? numStr : nil,
            lineCost:       store.settings.leadUnitPrice,
            dataType:       .fullCustomer,
            importDate:     Date(),
            conversions:    [record]
        )
        store.customers.append(newCustomer)
        store.save()
        newBuiltCount += 1
    }

    private func appendToExisting(result: TextParseResult, target: Customer) {
        guard let idx = store.customers.firstIndex(where: { $0.id == target.id }) else { return }
        let record = ConversionRecord(
            type:   result.conversionType,
            amount: result.amount,
            date:   Date()
        )
        store.customers[idx].conversions.append(record)
        store.save()
        matchedCount += 1
    }

    private func finalizeSave() {
        parseResults = []
        parseErrors  = []
        inputText    = ""
        showPreview  = false
        activeSheet  = nil

        let total = matchedCount + newBuiltCount
        if newBuiltCount == 0 {
            toastMessage = "✅ 已关联 \(matchedCount) 条转化记录到已有客户"
        } else if matchedCount == 0 {
            toastMessage = "✅ 新建 \(newBuiltCount) 位客户档案并写入成交记录"
        } else {
            toastMessage = "✅ 关联 \(matchedCount) 条，新建 \(newBuiltCount) 位，共 \(total) 条"
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

// MARK: - 场景A：新建客户档案面板
struct NewCustomerFromLedgerSheet: View {

    @Environment(\.dismiss) var dismiss
    let result:   TextParseResult
    let onCreate: (String?) -> Void

    @State private var customerNumber: String = ""

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("本次录入内容")) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 38, height: 38)
                            .overlay(
                                Text(String(result.name.prefix(1)))
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.blue)
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.name).fontWeight(.semibold)
                            Text(result.conversionType.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12))
                                .foregroundColor(.blue).cornerRadius(4)
                        }
                        Spacer()
                        Text("¥\(Int(result.amount))")
                            .font(.title3).fontWeight(.bold).foregroundColor(.green)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill").foregroundColor(.blue)
                            Text("正在为新客户「\(result.name)」建立档案")
                                .font(.subheadline).fontWeight(.semibold)
                        }
                        Text("系统未找到同名已有客户。请填写客户编号，或点击「跳过并直接创建」留空处理。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("客户编号（选填）")) {
                    HStack {
                        Text("编号").foregroundColor(.secondary).frame(width: 44, alignment: .leading)
                        TextField("如：8888（不填则留空）", text: $customerNumber)
                    }
                }

                Section {
                    Button {
                        onCreate(customerNumber)
                    } label: {
                        HStack {
                            Spacer()
                            HStack(spacing: 6) {
                                Image(systemName: "person.crop.circle.badge.plus")
                                let num = customerNumber.trimmingCharacters(in: .whitespaces)
                                Text(num.isEmpty ? "直接创建（编号留空）" : "确定创建（编号：\(num)）")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            Spacer()
                        }
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("新建客户档案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("跳过并直接创建", role: .cancel) { onCreate(nil) }
                }
            }
        }
    }
}

// MARK: - 场景B：同名客户绑定确认面板
struct LedgerMatchSheet: View {

    @EnvironmentObject var store: DataStore

    let result:     TextParseResult
    let candidates: [Customer]
    let onAppend:   (Customer) -> Void
    let onNewEntry: () -> Void

    @State private var previewCustomer: Customer? = nil

    var body: some View {
        NavigationView {
            List {
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
                                .foregroundColor(.orange).cornerRadius(4)
                        }
                        Spacer()
                        Text("¥\(Int(result.amount))")
                            .font(.title3).fontWeight(.bold).foregroundColor(.green)
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("请你决定如何处理（系统不会自动匹配）")) {
                    ForEach(candidates) { candidate in
                        VStack(alignment: .leading, spacing: 10) {
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
                                    HStack(spacing: 4) {
                                        Text(candidate.name).fontWeight(.semibold)
                                        Text("（\(candidate.customerNumber.map { "编号 \($0)" } ?? "未录入编号")）")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
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
                                        Image(systemName: "doc.text.magnifyingglass").font(.title3)
                                        Text("完整资料").font(.caption2)
                                    }
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 8).padding(.vertical, 6)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }

                            HStack(spacing: 10) {
                                Button { onAppend(candidate) } label: {
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
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.blue.opacity(0.4), lineWidth: 1.5))
                                }
                                .buttonStyle(.plain)

                                Button { onNewEntry() } label: {
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
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.orange.opacity(0.4), lineWidth: 1.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("请选择处理方式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("新建独立档案", role: .cancel) { onNewEntry() }
                }
            }
        }
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
