// MARK: - CustomerListView.swift
// 客户列表 — 搜索、筛选、详情

import SwiftUI

struct CustomerListView: View {

    @EnvironmentObject var store: DataStore
    @State private var searchText: String = ""
    @State private var selectedCustomer: Customer?

    var filtered: [Customer] {
        if searchText.isEmpty { return store.customers }
        return store.customers.filter {
            $0.name.contains(searchText) || $0.phone.contains(searchText)
        }
    }

    var body: some View {
        NavigationView {
            List(filtered) { customer in
                Button {
                    selectedCustomer = customer
                } label: {
                    CustomerRow(customer: customer)
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $searchText, prompt: "搜索姓名或电话")
            .navigationTitle("客户列表（\(filtered.count)）")
            .sheet(item: $selectedCustomer) { c in
                CustomerDetailView(customer: c)
            }
        }
    }
}

// MARK: - 客户行
struct CustomerRow: View {
    let customer: Customer

    var body: some View {
        HStack(spacing: 12) {
            // 头像占位
            Circle()
                .fill(Color.blue.gradient)
                .frame(width: 44, height: 44)
                .overlay(
                    Text(String(customer.name.prefix(1)))
                        .font(.headline)
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(customer.name).fontWeight(.semibold)
                Text(customer.phone)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let addr = customer.address {
                    Text(addr)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if !customer.conversions.isEmpty {
                    Text("¥\(Int(customer.totalRevenue))")
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)
                    Text("\(customer.conversions.count) 次转化")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("未转化")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 客户详情
struct CustomerDetailView: View {
    let customer: Customer
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("基础资料") {
                    LabeledContent("姓名",  value: customer.name)
                    LabeledContent("电话",  value: customer.phone)
                    LabeledContent("地址",  value: customer.address ?? "—")
                    LabeledContent("年龄",  value: customer.age.map { "\($0) 岁" } ?? "—")
                    LabeledContent("身高",  value: customer.height.map { "\($0) cm" } ?? "—")
                    LabeledContent("体重",  value: customer.weight.map { "\($0) kg" } ?? "—")
                }

                Section("生命周期 · 转化时间轴") {
                    if customer.conversions.isEmpty {
                        Text("暂无转化记录").foregroundStyle(.secondary)
                    } else {
                        ForEach(customer.conversions.sorted { $0.date < $1.date }) { record in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.type.rawValue).fontWeight(.semibold)
                                    Text(record.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("¥\(Int(record.amount))")
                                    .fontWeight(.bold)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }

                Section("汇总") {
                    LabeledContent("总营业额", value: "¥\(Int(customer.totalRevenue))")
                    LabeledContent("转化次数", value: "\(customer.conversions.count) 次")
                }
            }
            .navigationTitle(customer.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
