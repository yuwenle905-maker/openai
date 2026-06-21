import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            DS.Gradient.appBackground.ignoresSafeArea()

            TabView(selection: $selectedTab) {
                WorkbenchView()
                    .tag(0)
                AccountView()
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // 自定义 Tab Bar
            CustomTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Custom Tab Bar

private struct CustomTabBar: View {
    @Binding var selectedTab: Int

    private let items: [(icon: String, label: String)] = [
        ("cpu.fill", "工作台"),
        ("person.2.fill", "账户管理")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<items.count, id: \.self) { index in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = index
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: items[index].icon)
                            .font(.system(size: 20, weight: selectedTab == index ? .bold : .regular))
                            .foregroundStyle(
                                selectedTab == index
                                    ? AnyShapeStyle(DS.Gradient.sendButton)
                                    : AnyShapeStyle(DS.Color.textMuted)
                            )
                            .scaleEffect(selectedTab == index ? 1.1 : 1.0)

                        Text(items[index].label)
                            .font(DS.Font.labelSmall)
                            .foregroundColor(
                                selectedTab == index ? DS.Color.cyan : DS.Color.textMuted
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.bottom, 8)
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                Rectangle()
                    .fill(DS.Color.bgCard.opacity(0.9))
                Rectangle()
                    .fill(DS.Color.borderHighlight)
                    .frame(height: 0.5)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        )
    }
}
