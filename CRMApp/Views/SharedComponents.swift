// MARK: - SharedComponents.swift
// 跨视图共享的基础 UI 组件

import SwiftUI

/// iOS 15 兼容的键值展示行（替代 LabeledContent）
struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}
