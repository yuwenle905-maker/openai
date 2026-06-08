// MARK: - ImportView.swift
// 文件导入界面 — 文档选择器 + 弹窗调度

import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {

    @EnvironmentObject var store: DataStore
    @StateObject private var engine = ImportEngine(store: DataStore())  // 注入见 App 入口
    @State private var showingFilePicker = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {

                // 拖放/选择区域
                DropZoneView {
                    showingFilePicker = true
                }
                .padding()

                // 导入进度日志
                if !engine.events.isEmpty {
                    ImportLogView(events: engine.events)
                }

                Spacer()
            }
            .navigationTitle("导入数据")
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [
                    .spreadsheet,
                    UTType(filenameExtension: "xlsx") ?? .data,
                    UTType(filenameExtension: "xls")  ?? .data,
                    .commaSeparatedText
                ],
                allowsMultipleSelection: false
            ) { result in
                handleFilePick(result)
            }
            // 手动补录弹窗
            .sheet(isPresented: $engine.showingEditSheet) {
                if let partial = engine.pendingReviewRow {
                    ManualReviewSheet(
                        partial: partial,
                        onConfirm: { updated in engine.confirmReview(updated: updated) },
                        onSkip:    { engine.skipReview() }
                    )
                }
            }
            // 去重策略弹窗
            .confirmationDialog(
                "检测到重复电话号码",
                isPresented: $engine.showingDuplicateSheet,
                titleVisibility: .visible
            ) {
                Button("覆盖原记录",  role: .destructive) { engine.resolveDuplicate(resolution: .overwrite) }
                Button("追加转化记录（合并）")               { engine.resolveDuplicate(resolution: .merge)     }
                Button("跳过此条",   role: .cancel)        { engine.resolveDuplicate(resolution: .skip)      }
            } message: {
                if let pair = engine.pendingDuplicateRow {
                    Text("已有客户：\(pair.existing.name)（\(pair.existing.phone)）\n请选择处理方式。")
                }
            }
        }
    }

    private func handleFilePick(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }

        // 获取沙盒访问权限
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        // TODO: 集成 CoreXLSX 解析 xlsx；此处用模拟数据演示流程
        let mockRows = mockRawRows(from: url)
        engine.startImport(rows: mockRows, fileName: url.lastPathComponent, hasHeaders: true)
    }

    // MARK: 模拟行数据（待替换为真实 xlsx 解析）
    private func mockRawRows(from url: URL) -> [RawRow] {
        return [
            RawRow(index: 0, cells: ["姓名", "手机号", "地址", "年龄", "身高", "体重"]),
            RawRow(index: 1, cells: ["张三", "13812345678", "广州市天河区", "28", "175", "70"]),
            RawRow(index: 2, cells: ["李四", "13698765432", "上海市浦东新区", "35", "168", "65"]),
            RawRow(index: 3, cells: ["王五", "13511112222", "深圳市南山区", "", "172", ""]),  // 缺年龄/体重 → 触发弹窗
        ]
    }
}

// MARK: - 拖放区域
struct DropZoneView: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue.gradient)
                Text("点击选择文件")
                    .font(.headline)
                Text("支持 .xlsx / .xls / .csv")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.blue.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [8]))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 导入日志视图
struct ImportLogView: View {
    let events: [ImportEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("导入日志")
                .font(.headline)
                .padding(.horizontal)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                        Text(eventDescription(event))
                            .font(.caption.monospaced())
                            .foregroundStyle(eventColor(event))
                            .padding(.horizontal)
                    }
                }
            }
            .frame(maxHeight: 180)
        }
        .padding(.vertical)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func eventDescription(_ e: ImportEvent) -> String {
        switch e {
        case .started(let f):           return "▶ 开始导入：\(f)"
        case .rowParsed(let i, _):      return "  ✓ 第 \(i) 行已解析"
        case .needsReview(let i, _):    return "⚠ 第 \(i) 行需要手动补录"
        case .duplicateFound(let i, let ex, _):
            return "⚠ 第 \(i) 行电话重复（现有：\(ex.name)）"
        case .completed(let imp, let sk):
            return "✅ 完成：导入 \(imp) 条，跳过 \(sk) 条"
        case .failed(let err):          return "❌ 失败：\(err.localizedDescription)"
        }
    }

    private func eventColor(_ e: ImportEvent) -> Color {
        switch e {
        case .completed: return .green
        case .failed:    return .red
        case .needsReview, .duplicateFound: return .orange
        default:         return .secondary
        }
    }
}

// MARK: - 手动补录弹窗
struct ManualReviewSheet: View {

    let partial:   RowParseResult
    let onConfirm: (RowParseResult) -> Void
    let onSkip:    () -> Void

    @State private var ageText:    String
    @State private var heightText: String
    @State private var weightText: String

    init(partial: RowParseResult, onConfirm: @escaping (RowParseResult) -> Void, onSkip: @escaping () -> Void) {
        self.partial   = partial
        self.onConfirm = onConfirm
        self.onSkip    = onSkip
        _ageText    = State(initialValue: partial.age.map { "\($0)" }    ?? "")
        _heightText = State(initialValue: partial.height.map { "\($0)" } ?? "")
        _weightText = State(initialValue: partial.weight.map { "\($0)" } ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    LabeledContent("姓名",  value: partial.name    ?? "—")
                    LabeledContent("电话",  value: partial.phone   ?? "—")
                    LabeledContent("地址",  value: partial.address ?? "—")
                } header: {
                    Text("已识别字段")
                }

                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("以下字段未能自动识别，请手动补录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if partial.age == nil {
                        TextField("年龄（1-120）", text: $ageText)
                            .keyboardType(.numberPad)
                    }
                    if partial.height == nil {
                        TextField("身高 cm（100-220）", text: $heightText)
                            .keyboardType(.decimalPad)
                    }
                    if partial.weight == nil {
                        TextField("体重 kg（30-150）", text: $weightText)
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    Text("需要补录的字段")
                }
            }
            .navigationTitle("数据修正")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") { submit() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("跳过此行", role: .destructive) { onSkip() }
                }
            }
        }
    }

    private func submit() {
        var updated = partial
        if let v = Int(ageText),    v >= 1   && v <= 120 { updated.age    = v }
        if let v = Double(heightText), v >= 100 && v <= 220 { updated.height = v }
        if let v = Double(weightText), v >= 30  && v <= 150 { updated.weight = v }
        onConfirm(updated)
    }
}
