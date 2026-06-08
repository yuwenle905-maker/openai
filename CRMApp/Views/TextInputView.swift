// MARK: - TextInputView.swift
// 手动文本批量录入界面（iOS 15 兼容）

import SwiftUI

struct TextInputView: View {

    @EnvironmentObject var store: DataStore
    @State private var inputText:    String = ""
    @State private var parseResults: [TextParseResult] = []
    @State private var parseErrors:  [TextParseError]  = []
    @State private var showPreview:  Bool = false
    @State private var savedCount:   Int  = 0
    @State private var showSaveToast: Bool = false
    // 修复 Bug 3：收起键盘
    @FocusState private var editorFocused: Bool

    var body: some View {
        NavigationView {
            // 修复 Bug 3：点击背景收起键盘
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {

                    // ── 说明 ──────────────────────────────────────
                    VStack(alignment: .leading, spacing: 4) {
                        Text("批量粘贴文本")
                            .font(.headline)
                        Text("每行格式：姓名 状态 金额")
                            .font(.caption).foregroundColor(.secondary)
                        Text("例：张三 新单 4280")
                            .font(.caption).foregroundColor(.secondary)
                        Text("支持全角/半角空格，状态可写新单/二次/三次")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top)

                    // ── 输入框 ───────────────────────────────────
                    TextEditor(text: $inputText)
                        .focused($editorFocused)
                        .font(.body.monospaced())
                        .frame(minHeight: 160, maxHeight: 240)
                        .padding(8)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)

                    // ── 操作按钮行 ───────────────────────────────
                    HStack(spacing: 12) {
                        // 修复 Bug 3：点击解析同时收起键盘
                        Button("解析预览") {
                            editorFocused = false
                            let r = TextParser.parse(inputText)
                            parseResults = r.results
                            parseErrors  = r.errors
                            showPreview  = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("收起键盘") {
                            editorFocused = false
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)

                        Button("清空") {
                            editorFocused = false
                            inputText    = ""
                            parseResults = []
                            parseErrors  = []
                            showPreview  = false
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .padding(.horizontal)

                    // ── 解析结果预览 ─────────────────────────────
                    if showPreview {

                        // 成功列表
                        if !parseResults.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("解析成功 (\(parseResults.count) 条)")
                                    .font(.caption).foregroundColor(.secondary)
                                    .padding(.horizontal).padding(.top, 8)

                                Divider()

                                ForEach(parseResults) { r in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(r.name).fontWeight(.semibold)
                                            Text(r.rawLine)
                                                .font(.caption.monospaced())
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
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

                        // 失败列表
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

                        // 修复 Bug 3：保存按钮独立于 List，直接用 Button 不被拦截
                        if !parseResults.isEmpty {
                            Button {
                                saveConversions()
                            } label: {
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

                    Spacer(minLength: 40)
                }
            }
            // 点空白收起键盘
            .onTapGesture { editorFocused = false }
            .navigationTitle("手动录入")
            .background(Color(.systemGroupedBackground))
            .overlay(alignment: .bottom) {
                if showSaveToast {
                    Text("已保存 \(savedCount) 条转化记录")
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

    // MARK: 保存
    private func saveConversions() {
        var saved = 0
        for result in parseResults {
            let record = ConversionRecord(type: result.conversionType, amount: result.amount, date: Date())
            if let idx = store.customers.firstIndex(where: { $0.name == result.name }) {
                store.customers[idx].conversions.append(record)
                saved += 1
            } else {
                let newCustomer = Customer(
                    name:        result.name,
                    phone:       "待补全_\(result.name)",
                    importDate:  Date(),
                    conversions: [record]
                )
                store.customers.append(newCustomer)
                saved += 1
            }
        }
        store.save()
        savedCount   = saved
        parseResults = []
        parseErrors  = []
        inputText    = ""
        showPreview  = false
        withAnimation { showSaveToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { showSaveToast = false }
        }
    }

    private func conversionColor(_ type: ConversionType) -> Color {
        switch type {
        case .newOrder: return .blue
        case .second:   return .green
        case .third:    return .orange
        case .fourth:   return .purple
        case .unknown:  return .gray
        }
    }
}
