// MARK: - TextInputView.swift
// 手动文本批量录入界面

import SwiftUI

struct TextInputView: View {

    @EnvironmentObject var store: DataStore
    @State private var inputText:  String = ""
    @State private var parseResults:  [TextParseResult]  = []
    @State private var parseErrors:   [TextParseError]   = []
    @State private var showPreview:   Bool = false
    @State private var savedCount:    Int  = 0
    @State private var showSaveToast: Bool = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {

                // ── 输入框 ─────────────────────────────────────
                VStack(alignment: .leading, spacing: 8) {
                    Text("批量粘贴文本")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top)

                    Text("每行格式：姓名 状态 金额　例：张三 新单 4280")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    TextEditor(text: $inputText)
                        .font(.body.monospaced())
                        .frame(minHeight: 160)
                        .padding(8)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)

                    HStack {
                        Button("解析预览") {
                            let r = TextParser.parse(inputText)
                            parseResults = r.results
                            parseErrors  = r.errors
                            showPreview  = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("清空") {
                            inputText    = ""
                            parseResults = []
                            parseErrors  = []
                            showPreview  = false
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                .background(Color(.systemGroupedBackground))

                // ── 预览 + 存储 ────────────────────────────────
                if showPreview {
                    List {
                        // 成功解析
                        if !parseResults.isEmpty {
                            Section("解析成功 (\(parseResults.count) 条)") {
                                ForEach(parseResults) { r in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(r.name).fontWeight(.semibold)
                                            Text(r.rawLine)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(r.conversionType.rawValue)
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 2)
                                                .background(conversionColor(r.conversionType).opacity(0.15))
                                                .foregroundStyle(conversionColor(r.conversionType))
                                                .clipShape(Capsule())
                                            Text("¥\(Int(r.amount))")
                                                .fontWeight(.semibold)
                                                .foregroundStyle(.green)
                                        }
                                    }
                                }
                            }
                        }

                        // 解析失败
                        if !parseErrors.isEmpty {
                            Section("解析失败 (\(parseErrors.count) 行)") {
                                ForEach(parseErrors) { e in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("第 \(e.lineNumber) 行：\(e.rawLine)")
                                            .font(.caption.monospaced())
                                        Text(e.reason)
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                        }

                        // 保存按钮
                        if !parseResults.isEmpty {
                            Section {
                                Button {
                                    saveConversions()
                                } label: {
                                    Label("保存 \(parseResults.count) 条转化记录", systemImage: "checkmark.circle.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }

                Spacer()
            }
            .navigationTitle("手动录入")
            .overlay(alignment: .bottom) {
                if showSaveToast {
                    Text("✓ 已保存 \(savedCount) 条转化记录")
                        .padding()
                        .background(.green.gradient)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .padding(.bottom, 32)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: 保存转化记录到对应客户
    private func saveConversions() {
        var saved = 0
        for result in parseResults {
            let record = ConversionRecord(
                type:   result.conversionType,
                amount: result.amount,
                date:   Date()
            )
            // 按姓名模糊匹配（实际生产中应配合电话）
            if let idx = store.customers.firstIndex(where: { $0.name == result.name }) {
                store.customers[idx].conversions.append(record)
                saved += 1
            } else {
                // 姓名不存在 → 创建占位客户（电话暂存为姓名，待后续补全）
                let newCustomer = Customer(
                    name:       result.name,
                    phone:      "待补全_\(result.name)",
                    importDate: Date(),
                    conversions: [record]
                )
                store.customers.append(newCustomer)
                saved += 1
            }
        }
        store.save()
        savedCount = saved
        parseResults = []
        parseErrors  = []
        inputText    = ""
        showPreview  = false

        withAnimation {
            showSaveToast = true
        }
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
