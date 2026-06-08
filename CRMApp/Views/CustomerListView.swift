// MARK: - CustomerListView.swift
// 客户列表：按天折叠 + 全局搜索 + 滑动删除

import SwiftUI

// MARK: - 主列表
struct CustomerListView: View {

    @EnvironmentObject var store: DataStore
    @State private var searchText   = ""
    @State private var selectedDay:  DayGroup?

    // 仅完整客户（不含流水记录）
    private var realCustomers: [Customer] {
        store.customers.filter { $0.dataType == .fullCustomer }
    }

    // 搜索模式：全库检索（跨日期）
    private var searchResults: [Customer] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return store.customers.filter {
            $0.name.lowercased().contains(q) ||
            $0.phone.contains(q) ||
            ($0.address ?? "").contains(q)
        }
    }

    // 按天分组（仅完整客户）
    private var dayGroups: [DayGroup] {
        let grouped = Dictionary(grouping: realCustomers) { $0.importDayKey }
        return grouped
            .map { key, customers in
                DayGroup(
                    dayKey:     key,
                    dayDisplay: customers.first?.importDayDisplay ?? key,
                    customers:  customers.sorted { $0.importDate > $1.importDate }
                )
            }
            .sorted { $0.dayKey > $1.dayKey }
    }

    var body: some View {
        NavigationView {
            Group {
                if !searchText.isEmpty {
                    // 搜索结果：平铺展示
                    SearchResultList(results: searchResults)
                } else {
                    // 正常模式：按天折叠
                    DayGroupedList(groups: dayGroups)
                }
            }
            .searchable(text: $searchText, prompt: "搜索姓名、电话、地址")
            .navigationTitle("客户列表（\(realCustomers.count) 人）")
        }
    }
}

// MARK: 天分组模型
struct DayGroup: Identifiable {
    let id = UUID()
    let dayKey:     String   // yyyy-MM-dd，用于排序
    let dayDisplay: String   // M月d日
    var customers:  [Customer]
}

// MARK: 按天折叠列表
struct DayGroupedList: View {

    @EnvironmentObject var store: DataStore
    let groups: [DayGroup]

    var body: some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.customers) { customer in
                        NavigationLink(destination: CustomerDetailView(customer: customer)) {
                            CustomerRow(customer: customer)
                        }
                    }
                    .onDelete { indexSet in
                        deleteCustomers(group: group, at: indexSet)
                    }
                } header: {
                    HStack {
                        Text(group.dayDisplay)
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                        Spacer()
                        Text("共 \(group.customers.count) 条")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func deleteCustomers(group: DayGroup, at offsets: IndexSet) {
        let toDelete = offsets.map { group.customers[$0] }
        store.customers.removeAll { c in toDelete.contains(where: { $0.id == c.id }) }
        store.save()
    }
}

// MARK: 搜索结果平铺列表
struct SearchResultList: View {

    @EnvironmentObject var store: DataStore
    let results: [Customer]

    var body: some View {
        List {
            if results.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 48)).foregroundColor(.secondary)
                    Text("无匹配结果").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity).padding(40)
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

// MARK: - 客户行
struct CustomerRow: View {
    let customer: Customer

    var body: some View {
        HStack(spacing: 12) {
            // 头像
            Circle()
                .fill(customer.dataType == .fullCustomer ? Color.blue : Color.orange)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(customer.name.prefix(1)))
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(customer.name).fontWeight(.semibold)
                    if customer.dataType == .ledgerEntry {
                        Text("流水").font(.caption2)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(3)
                    }
                }
                Text(customer.phone)
                    .font(.caption).foregroundColor(.secondary)
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
    var customer: Customer

    var body: some View {
        List {
            // 基础资料
            Section(header: Text("基础资料")) {
                InfoRow(label: "姓名",  value: customer.name)
                InfoRow(label: "电话",  value: customer.phone)
                InfoRow(label: "地址",  value: customer.address ?? "—")
                InfoRow(label: "年龄",  value: customer.age.map    { "\($0) 岁"  } ?? "—")
                InfoRow(label: "身高",  value: customer.height.map { "\($0) cm"  } ?? "—")
                InfoRow(label: "体重",  value: customer.weight.map { "\($0) kg"  } ?? "—")
                InfoRow(label: "类型",  value: customer.dataType == .fullCustomer ? "正式客户" : "流水记录")
            }

            // 生命周期时间轴
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

            // 汇总
            Section(header: Text("汇总")) {
                InfoRow(label: "总营业额", value: "¥\(Int(customer.totalRevenue))")
                InfoRow(label: "转化次数", value: "\(customer.conversions.count) 次")
                InfoRow(label: "导入日期", value: customer.importDayDisplay)
            }

            // 危险操作
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
