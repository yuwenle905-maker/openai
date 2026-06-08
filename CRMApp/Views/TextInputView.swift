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
                            // 预览时标记每条是否能关联到已有客户
                            VStack(alignment: .leading, spacing: 0) {
                                Text("解析成功 (\(parseResults.count) 条)")
                                    .font(.caption).foregroundColor(.secondary)
                                    .padding(.horizontal).padding(.top, 8)
                                Divider()
                                ForEach(parseResults) { r in
                                    let matched = store.customers.first {
                                        $0.name == r.name && $0.dataType == .fullCustomer
                                    }
                                    HStack(alignment: .top, spacing: 8) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 6) {
                                                Text(r.name).fontWeight(.semibold)
                                                // 匹配状态标签
                                                if matched != nil {
                                                    Text("已匹配客户")
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
                            Button { saveConversions() } label: {
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

                    // ── 流水待关联列表（让用户看到"未找到客户"的记录）──
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
    }

    // MARK: 保存流水记录
    // 核心原则：只有此处写入的金额才计入营业额（ConversionRecord.amount）
    private func saveConversions() {
        var matched   = 0   // 成功关联到已有完整客户
        var orphaned  = 0   // 未找到客户，暂存为待关联流水

        for result in parseResults {
            let record = ConversionRecord(
                type:   result.conversionType,
                amount: result.amount,   // 此处金额计入营业额
                date:   Date()
            )

            // 优先按姓名精确匹配已有完整客户
            if let idx = store.customers.firstIndex(where: {
                $0.name == result.name && $0.dataType == .fullCustomer
            }) {
                store.customers[idx].conversions.append(record)
                matched += 1
            } else {
                // 未找到完整客户 → 创建待关联流水条目（ledgerEntry，不计入客户总数）
                // 关联规则：下次导入同名完整客户时，可手动/自动合并
                let orphan = Customer(
                    name:        result.name,
                    phone:       "待补全_\(result.name)_\(UUID().uuidString.prefix(6))",
                    dataType:    .ledgerEntry,
                    importDate:  Date(),
                    conversions: [record]
                )
                store.customers.append(orphan)
                orphaned += 1
            }
        }

        store.save()
        savedCount   = matched + orphaned
        parseResults = []
        parseErrors  = []
        inputText    = ""
        showPreview  = false

        // 根据关联情况给不同的提示
        if orphaned == 0 {
            toastMessage = "✅ 已关联 \(matched) 条转化记录到客户"
        } else if matched == 0 {
            toastMessage = "⚠️ \(orphaned) 条暂存为待关联流水（客户未找到）"
        } else {
            toastMessage = "✅ 关联 \(matched) 条，⚠️ \(orphaned) 条待关联"
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
