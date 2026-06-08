// MARK: - DashboardView.swift
// ROI 核心看板 — 月/年 ROI + 可折叠漏斗 + 画像统计

import SwiftUI

struct DashboardView: View {

    @EnvironmentObject var store: DataStore
    @State private var selectedYear:  Int  = Calendar.current.component(.year,  from: Date())
    @State private var selectedMonth: Int  = Calendar.current.component(.month, from: Date())
    @State private var funnelExpanded: Bool = true

    // 当前选中月数据
    private var monthCustomers: [Customer] {
        store.customers(inYear: selectedYear, month: selectedMonth)
    }
    private var yearCustomers: [Customer] {
        store.customers(inYear: selectedYear)
    }

    private var monthSummary: PeriodSummary {
        ROIEngine.summary(customers: monthCustomers, leadUnitPrice: store.settings.leadUnitPrice)
    }
    private var yearSummary: PeriodSummary {
        ROIEngine.summary(customers: yearCustomers,  leadUnitPrice: store.settings.leadUnitPrice)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {

                    // ── 时间选择器 ─────────────────────────────
                    PeriodPickerView(year: $selectedYear, month: $selectedMonth)
                        .padding(.horizontal)

                    // ── ROI KPI 卡片 ───────────────────────────
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        KPICard(
                            title:    "本月 ROI",
                            value:    monthSummary.roiText,
                            subtitle: "营业额 / 成本",
                            color:    monthSummary.roi >= 1 ? .green : .orange
                        )
                        KPICard(
                            title:    "年度 ROI",
                            value:    yearSummary.roiText,
                            subtitle: "年度累计",
                            color:    yearSummary.roi >= 1 ? .green : .orange
                        )
                        KPICard(
                            title:    "本月成本",
                            value:    "¥\(Int(monthSummary.totalCost))",
                            subtitle: "\(monthSummary.importedLeadCount) 条 × ¥\(Int(store.settings.leadUnitPrice))",
                            color:    .blue
                        )
                        KPICard(
                            title:    "本月营业额",
                            value:    "¥\(Int(monthSummary.totalRevenue))",
                            subtitle: "含所有转化",
                            color:    .indigo
                        )
                    }
                    .padding(.horizontal)

                    // ── 可折叠漏斗详情 ─────────────────────────
                    FunnelCard(
                        stages:   monthSummary.funnelStages,
                        expanded: $funnelExpanded
                    )
                    .padding(.horizontal)

                    // ── 地域画像 ───────────────────────────────
                    ProfileCard(
                        title:    "地域分布",
                        profiles: ROIEngine.regionProfiles(customers: monthCustomers)
                            .map { ($0.name, $0.count, $0.percentageText) }
                    )
                    .padding(.horizontal)

                    // ── 年龄段画像 ─────────────────────────────
                    ProfileCard(
                        title:    "年龄段分布",
                        profiles: ROIEngine.ageProfiles(customers: monthCustomers)
                            .map { ($0.label, $0.count, $0.percentageText) }
                    )
                    .padding(.horizontal)

                    Spacer(minLength: 32)
                }
                .padding(.top)
            }
            .navigationTitle("数据看板")
            .background(Color(.systemGroupedBackground))
        }
    }
}

// MARK: - 时间选择器
struct PeriodPickerView: View {
    @Binding var year: Int
    @Binding var month: Int

    private let months = (1...12).map { "\($0)月" }

    var body: some View {
        HStack {
            Stepper("\(year)年", value: $year, in: 2020...2099)
                .labelsHidden()
            Text("\(year)年")
                .fontWeight(.semibold)
            Spacer()
            Picker("月份", selection: $month) {
                ForEach(1...12, id: \.self) { m in
                    Text("\(m)月").tag(m)
                }
            }
            .pickerStyle(.menu)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - KPI 卡片
struct KPICard: View {
    let title:    String
    let value:    String
    let subtitle: String
    let color:    Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - 漏斗卡片
struct FunnelCard: View {
    let stages:    [FunnelStage]
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // 标题行（点击折叠）
            Button {
                withAnimation(.spring(response: 0.3)) { expanded.toggle() }
            } label: {
                HStack {
                    Text("销售漏斗")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .padding()
            }

            if expanded {
                Divider()
                VStack(spacing: 0) {
                    ForEach(stages) { stage in
                        FunnelRow(stage: stage)
                        if stage.id != stages.last?.id {
                            Divider().padding(.leading)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

struct FunnelRow: View {
    let stage: FunnelStage

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(stage.label)
                    .font(.subheadline.bold())
                Text("\(stage.count) 单 · \(stage.totalAmountText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(stage.conversionRateText)
                    .font(.title3.bold())
                    .foregroundStyle(.blue)
                Text("\(stage.count)/\(stage.denominator)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

// MARK: - 画像卡片（通用）
struct ProfileCard: View {
    let title: String
    let profiles: [(name: String, count: Int, pct: String)]

    var total: Int { profiles.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            ForEach(profiles, id: \.name) { item in
                VStack(spacing: 4) {
                    HStack {
                        Text(item.name)
                            .font(.subheadline)
                        Spacer()
                        Text("\(item.count) 人")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.pct)
                            .font(.subheadline.bold())
                            .foregroundStyle(.blue)
                            .frame(width: 52, alignment: .trailing)
                    }
                    // 进度条
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.blue.gradient)
                                .frame(
                                    width: total > 0
                                        ? geo.size.width * CGFloat(item.count) / CGFloat(total)
                                        : 0,
                                    height: 6
                                )
                                .animation(.easeInOut, value: item.count)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.horizontal)
            }

            Spacer(minLength: 12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}
