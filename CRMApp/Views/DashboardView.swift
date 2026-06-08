// MARK: - DashboardView.swift
// ROI 核心看板 — 月/年 ROI + 可折叠漏斗 + 可点击画像统计（iOS 15 兼容）

import SwiftUI

struct DashboardView: View {

    @EnvironmentObject var store: DataStore
    @State private var selectedYear:  Int  = Calendar.current.component(.year,  from: Date())
    @State private var selectedMonth: Int  = Calendar.current.component(.month, from: Date())
    @State private var funnelExpanded: Bool = true

    // 完整客户（用于画像统计：地域/年龄/金额分布）
    private var monthCustomers: [Customer] {
        store.customers(inYear: selectedYear, month: selectedMonth)
    }
    private var yearCustomers: [Customer] {
        store.customers(inYear: selectedYear)
    }
    // 所有客户包括流水条目（用于营业额/ROI/漏斗统计）
    private var monthAllCustomers: [Customer] {
        store.allCustomers(inYear: selectedYear, month: selectedMonth)
    }
    private var yearAllCustomers: [Customer] {
        store.allCustomers(inYear: selectedYear)
    }
    private var monthSummary: PeriodSummary {
        ROIEngine.summary(customers: monthAllCustomers, leadUnitPrice: store.settings.leadUnitPrice)
    }
    private var yearSummary: PeriodSummary {
        ROIEngine.summary(customers: yearAllCustomers, leadUnitPrice: store.settings.leadUnitPrice)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {

                    PeriodPickerView(year: $selectedYear, month: $selectedMonth)
                        .padding(.horizontal)

                    // ROI KPI
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        KPICard(title: "本月 ROI",   value: monthSummary.roiText,
                                subtitle: "营业额 / 成本",
                                color: monthSummary.roi >= 1 ? .green : .orange)
                        KPICard(title: "年度 ROI",   value: yearSummary.roiText,
                                subtitle: "年度累计",
                                color: yearSummary.roi >= 1 ? .green : .orange)
                        KPICard(title: "本月成本",
                                value: "¥\(Int(monthSummary.totalCost))",
                                subtitle: "\(monthSummary.importedLeadCount) 条（各自历史单价）",
                                color: .blue)
                        KPICard(title: "本月营业额",
                                value: "¥\(Int(monthSummary.totalRevenue))",
                                subtitle: "手动录入转化之和", color: .indigo)
                    }
                    .padding(.horizontal)

                    // 漏斗
                    FunnelCard(stages: monthSummary.funnelStages, expanded: $funnelExpanded)
                        .padding(.horizontal)

                    // 地域分布（可点击下钻）
                    DrillDownProfileCard(
                        title:     "地域分布（七大区）",
                        items:     ROIEngine.regionProfiles(customers: monthCustomers),
                        allCustomers: monthCustomers,
                        drillType: .region
                    )
                    .padding(.horizontal)

                    // 年龄段（可点击下钻）
                    DrillDownProfileCard(
                        title:     "年龄段分布",
                        items:     ROIEngine.ageProfiles(customers: monthCustomers),
                        allCustomers: monthCustomers,
                        drillType: .age
                    )
                    .padding(.horizontal)

                    // 线索金额分布（leadAmount，不计营业额）
                    DrillDownProfileCard(
                        title:     "线索金额分布",
                        items:     ROIEngine.amountProfiles(customers: monthCustomers),
                        allCustomers: monthCustomers,
                        drillType: .amount
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

// MARK: - 下钻类型
enum DrillType { case region, age, amount }

// MARK: - 可点击下钻的画像卡片（需求3）
struct DrillDownProfileCard: View {

    let title:        String
    let items:        [ProfileItem]
    let allCustomers: [Customer]
    let drillType:    DrillType

    var total: Int { items.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).padding(.horizontal).padding(.top)

            ForEach(items) { item in
                NavigationLink(destination:
                    DrillDownCustomerList(
                        title:       item.label,
                        filterKey:   item.filterKey,
                        customers:   allCustomers,
                        drillType:   drillType
                    )
                ) {
                    VStack(spacing: 4) {
                        HStack {
                            Text(item.label).font(.subheadline).foregroundColor(.primary)
                            Spacer()
                            Text("\(item.count) 人")
                                .font(.caption).foregroundColor(.secondary)
                            Text(item.percentageText)
                                .font(.subheadline.bold()).foregroundColor(.blue)
                                .frame(width: 56, alignment: .trailing)
                            Image(systemName: "chevron.right")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(.systemGray5)).frame(height: 6)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.blue)
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
                .buttonStyle(.plain)
            }
            Spacer(minLength: 12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - 下钻客户列表页（需求3）
struct DrillDownCustomerList: View {

    let title:      String
    let filterKey:  String
    let customers:  [Customer]
    let drillType:  DrillType

    private var filtered: [Customer] {
        switch drillType {
        case .region:
            return customers.filter { ROIEngine.regionLabel(for: $0.address) == filterKey }
        case .age:
            return customers.filter { c in
                guard let age = c.age else { return false }
                switch filterKey {
                case "20-30岁":  return (20...29).contains(age)
                case "30-40岁":  return (30...39).contains(age)
                case "40岁以上": return age >= 40
                case "20岁以下": return age < 20
                default:         return false
                }
            }
        case .amount:
            return customers.filter { c in
                guard let amt = c.leadAmount else { return false }
                switch filterKey {
                case "300元以内":  return amt <= 300
                case "301-500元": return amt > 300 && amt <= 500
                case "500元以上":  return amt > 500
                default:           return false
                }
            }
        }
    }

    var body: some View {
        List {
            Section(header: Text("\(title) · \(filtered.count) 人")) {
                ForEach(filtered) { customer in
                    NavigationLink(destination: CustomerDetailView(customer: customer)) {
                        CustomerRow(customer: customer)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 时间选择器
struct PeriodPickerView: View {
    @Binding var year: Int
    @Binding var month: Int

    var body: some View {
        HStack {
            Stepper("\(year)年", value: $year, in: 2020...2099).labelsHidden()
            Text("\(year)年").fontWeight(.semibold)
            Spacer()
            Picker("月份", selection: $month) {
                ForEach(1...12, id: \.self) { m in Text("\(m)月").tag(m) }
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
    let title: String; let value: String; let subtitle: String; let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.title2.bold()).foregroundColor(color)
            Text(subtitle).font(.caption2).foregroundColor(.secondary)
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
    let stages: [FunnelStage]
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3)) { expanded.toggle() }
            } label: {
                HStack {
                    Text("销售漏斗").font(.headline).foregroundColor(.primary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary).font(.caption)
                }
                .padding()
            }

            if expanded {
                Divider()
                VStack(spacing: 0) {
                    ForEach(stages) { stage in
                        FunnelRow(stage: stage)
                        if stage.id != stages.last?.id { Divider().padding(.leading) }
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
                Text(stage.label).font(.subheadline.bold())
                Text("\(stage.count) 单 · \(stage.totalAmountText)")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(stage.conversionRateText).font(.title3.bold()).foregroundColor(.blue)
                Text("\(stage.count)/\(stage.denominator)")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal).padding(.vertical, 10)
    }
}
