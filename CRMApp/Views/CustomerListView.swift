// MARK: - CustomerListView.swift
// 客户列表：三层树状（年→月→日）+ 全局搜索 + 滑动删除

import SwiftUI

// MARK: - 分组数据结构

struct DayGroup: Identifiable {
    let id = UUID()
    let dayKey:     String    // yyyy-MM-dd
    let dayDisplay: String    // M月d日
    var customers:  [Customer]
}

struct MonthGroup: Identifiable {
    let id = UUID()
    let monthKey:    String   // yyyy-MM
    let monthDisplay: String  // X月
    var dayGroups:   [DayGroup]
    var totalCount:  Int { dayGroups.reduce(0) { $0 + $1.customers.count } }
}

struct YearGroup: Identifiable {
    let id = UUID()
    let yearKey:    String    // yyyy
    let yearDisplay: String   // XXXX年
    var monthGroups: [MonthGroup]
    var totalCount:  Int { monthGroups.reduce(0) { $0 + $1.totalCount } }
}

// MARK: - 主列表视图
struct CustomerListView: View {

    @EnvironmentObject var store: DataStore
    @State private var searchText = ""

    // 仅完整客户（不含流水记录）
    private var realCustomers: [Customer] {
        store.customers.filter { $0.dataType == .fullCustomer }
    }

    // 搜索结果：全库检索（不受日期分类限制）
    private var searchResults: [Customer] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return store.customers.filter {
            $0.name.lowercased().contains(q) ||
            $0.phone.contains(q) ||
            ($0.address ?? "").lowercased().contains(q)
        }
    }

    // 三层分组
    private var yearGroups: [YearGroup] {
        buildYearGroups(from: realCustomers)
    }

    var body: some View {
        NavigationView {
            Group {
                if !searchText.isEmpty {
                    SearchResultList(results: searchResults)
                } else {
                    TreeListView(yearGroups: yearGroups)
                }
            }
            .searchable(text: $searchText, prompt: "搜索姓名、电话、地址（全库）")
            .navigationTitle("客户（\(realCustomers.count) 人）")
        }
    }

    // MARK: 构建三层分组
    private func buildYearGroups(from customers: [Customer]) -> [YearGroup] {
        let cal = DateFormatter()

        // 按年月日逐层分组
        let byYear = Dictionary(grouping: customers) { c -> String in
            cal.dateFormat = "yyyy"
            return cal.string(from: c.importDate)
        }

        return byYear.map { (yearKey, yCusts) in
            let byMonth = Dictionary(grouping: yCusts) { c -> String in
                cal.dateFormat = "yyyy-MM"
                return cal.string(from: c.importDate)
            }
            let monthGroups: [MonthGroup] = byMonth.map { (monthKey, mCusts) in
                let byDay = Dictionary(grouping: mCusts) { c -> String in
                    cal.dateFormat = "yyyy-MM-dd"
                    return cal.string(from: c.importDate)
                }
                let dayGroups: [DayGroup] = byDay.map { (dayKey, dCusts) in
                    cal.dateFormat = "M月d日"
                    let display = cal.string(from: dCusts.first!.importDate)
                    return DayGroup(
                        dayKey:     dayKey,
                        dayDisplay: display,
                        customers:  dCusts.sorted { $0.importDate > $1.importDate }
                    )
                }.sorted { $0.dayKey > $1.dayKey }

                cal.dateFormat = "MM"
                let mNum = cal.string(from: mCusts.first!.importDate)
                return MonthGroup(
                    monthKey:     monthKey,
                    monthDisplay: "\(mNum)月",
                    dayGroups:    dayGroups
                )
            }.sorted { $0.monthKey > $1.monthKey }

            return YearGroup(
                yearKey:     yearKey,
                yearDisplay: "\(yearKey)年",
                monthGroups: monthGroups
            )
        }.sorted { $0.yearKey > $1.yearKey }
    }
}

// MARK: - 三层树状列表
struct TreeListView: View {

    @EnvironmentObject var store: DataStore
    let yearGroups: [YearGroup]

    // 展开状态
    @State private var expandedYears:  Set<String> = []
    @State private var expandedMonths: Set<String> = []

    var body: some View {
        List {
            if yearGroups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.3").font(.system(size: 44)).foregroundColor(.secondary)
                    Text("暂无客户数据").foregroundColor(.secondary)
                    Text("在「智能导入」标签粘贴数据开始").font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity).padding(48)
                .listRowBackground(Color.clear)
            } else {
                ForEach(yearGroups) { year in
                    yearSection(year)
                }
            }
        }
        .listStyle(.insetGrouped)
        .onAppear {
            // 默认展开最近一年和最近一月
            if let firstYear = yearGroups.first {
                expandedYears.insert(firstYear.yearKey)
                if let firstMonth = firstYear.monthGroups.first {
                    expandedMonths.insert(firstMonth.monthKey)
                }
            }
        }
    }

    // MARK: 年级 Section
    @ViewBuilder
    private func yearSection(_ year: YearGroup) -> some View {
        Section {
            // 年份折叠行
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedYears.contains(year.yearKey) {
                        expandedYears.remove(year.yearKey)
                    } else {
                        expandedYears.insert(year.yearKey)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: expandedYears.contains(year.yearKey)
                          ? "chevron.down.circle.fill" : "chevron.right.circle")
                        .foregroundColor(.blue)
                    Text(year.yearDisplay)
                        .font(.headline).foregroundColor(.primary)
                    Spacer()
                    Text("共 \(year.totalCount) 人")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            // 展开后显示月份
            if expandedYears.contains(year.yearKey) {
                ForEach(year.monthGroups) { month in
                    monthRows(month)
                }
            }
        }
    }

    // MARK: 月份行 + 日期行
    @ViewBuilder
    private func monthRows(_ month: MonthGroup) -> some View {
        // 月份折叠行
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if expandedMonths.contains(month.monthKey) {
                    expandedMonths.remove(month.monthKey)
                } else {
                    expandedMonths.insert(month.monthKey)
                }
            }
        } label: {
            HStack {
                Image(systemName: expandedMonths.contains(month.monthKey)
                      ? "folder.fill" : "folder")
                    .foregroundColor(.orange)
                Text(month.monthDisplay)
                    .font(.subheadline.bold()).foregroundColor(.primary)
                Spacer()
                Text("\(month.totalCount) 人")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.leading, 16)
        }
        .buttonStyle(.plain)

        // 展开后显示每日数据卡片
        if expandedMonths.contains(month.monthKey) {
            ForEach(month.dayGroups) { day in
                dayCard(day)
            }
        }
    }

    // MARK: 每日数据卡片（需求4核心）
    @ViewBuilder
    private func dayCard(_ day: DayGroup) -> some View {
        NavigationLink(destination: DayCustomerList(day: day)) {
            VStack(alignment: .leading, spacing: 4) {
                // 卡片头部：导入日期 | 该批次数据条数
                HStack {
                    Image(systemName: "calendar.badge.plus")
                        .foregroundColor(.green).font(.caption)
                    Text("\(day.dayDisplay)  |  \(day.customers.count) 条数据")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                }

                // 预览前两条客户名
                let preview = day.customers.prefix(2).map { $0.name }.joined(separator: "、")
                let suffix   = day.customers.count > 2 ? " 等…" : ""
                Text(preview + suffix)
                    .font(.caption).foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 4)
            .padding(.leading, 32)
        }
    }
}

// MARK: - 某日客户二级页面
struct DayCustomerList: View {

    @EnvironmentObject var store: DataStore
    let day: DayGroup

    var body: some View {
        List {
            Section(header:
                Text("\(day.dayDisplay)  |  共 \(day.customers.count) 条数据")
                    .font(.subheadline.bold())
            ) {
                ForEach(day.customers) { customer in
                    NavigationLink(destination: CustomerDetailView(customer: customer)) {
                        CustomerRow(customer: customer)
                    }
                }
                .onDelete { indexSet in
                    let toDelete = indexSet.map { day.customers[$0] }
                    store.customers.removeAll { c in toDelete.contains(where: { $0.id == c.id }) }
                    store.save()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(day.dayDisplay)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 搜索结果平铺（全库，跨日期）
struct SearchResultList: View {

    @EnvironmentObject var store: DataStore
    let results: [Customer]

    var body: some View {
        List {
            if results.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 44)).foregroundColor(.secondary)
                    Text("无匹配结果").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity).padding(48)
                .listRowBackground(Color.clear)
            } else {
                Section(header: Text("找到 \(results.count) 条结果")) {
                    ForEach(results) { customer in
                        NavigationLink(destination: CustomerDetailView(customer: customer)) {
                            CustomerRow(customer: customer)
                        }
                    }
                    .onDelete { indexSet in
                        let toDelete = indexSet.map { results[$0] }
                        store.customers.removeAll { c in toDelete.contains(where: { $0.id == c.id }) }
                        store.save()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - 客户行组件
struct CustomerRow: View {
    let customer: Customer

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(customer.dataType == .fullCustomer ? Color.blue : Color.orange)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(customer.name.prefix(1)))
                        .font(.subheadline.bold()).foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(customer.name).fontWeight(.semibold)
                    if customer.dataType == .ledgerEntry {
                        Text("流水").font(.caption2)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange).cornerRadius(3)
                    }
                }
                Text(customer.phone).font(.caption).foregroundColor(.secondary)
                if let addr = customer.address {
                    Text(addr).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if !customer.conversions.isEmpty {
                    Text("¥\(Int(customer.totalRevenue))")
                        .font(.subheadline.bold()).foregroundColor(.green)
                    Text("\(customer.conversions.count) 次转化")
                        .font(.caption2).foregroundColor(.secondary)
                } else {
                    Text("未转化").font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 客户详情页
struct CustomerDetailView: View {

    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) var dismiss
    let customer: Customer

    var body: some View {
        List {
            Section(header: Text("基础资料")) {
                InfoRow(label: "姓名",  value: customer.name)
                InfoRow(label: "电话",  value: customer.phone)
                InfoRow(label: "地址",  value: customer.address ?? "—")
                InfoRow(label: "年龄",  value: customer.age.map    { "\($0) 岁"  } ?? "—")
                InfoRow(label: "身高",  value: customer.height.map { "\($0) cm"  } ?? "—")
                InfoRow(label: "体重",  value: customer.weight.map { "\($0) kg"  } ?? "—")
            }

            Section(header: Text("消费时间轴")) {
                if customer.conversions.isEmpty {
                    Text("暂无消费记录").foregroundColor(.secondary)
                } else {
                    ForEach(customer.conversions.sorted { $0.date > $1.date }) { record in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.type.rawValue).fontWeight(.semibold)
                                if let p = record.productNote {
                                    Text(p).font(.caption).foregroundColor(.secondary)
                                }
                                Text(record.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("¥\(Int(record.amount))")
                                .fontWeight(.bold).foregroundColor(.green)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section(header: Text("汇总")) {
                if let lead = customer.leadAmount {
                    InfoRow(label: "线索金额", value: "¥\(Int(lead))（仅记录，不计营业额）")
                }
                InfoRow(label: "总营业额", value: "¥\(Int(customer.totalRevenue))")
                InfoRow(label: "转化次数", value: "\(customer.conversions.count) 次")
                InfoRow(label: "导入日期", value: customer.importDayDisplay)
            }

            Section {
                Button(role: .destructive) {
                    store.customers.removeAll { $0.id == customer.id }
                    store.save()
                    dismiss()
                } label: {
                    HStack {
                        Spacer()
                        Label("删除此客户", systemImage: "trash")
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(customer.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
