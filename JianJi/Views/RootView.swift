import SwiftUI

enum AppTab: Hashable {
    case home
    case statistics
    case bills
    case profile
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedTab: AppTab = .home
    @State private var isAdding = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.background.ignoresSafeArea()
            TabView(selection: $selectedTab) {
                HomeView(showAllBills: { selectedTab = .bills }).tag(AppTab.home)
                StatisticsView().tag(AppTab.statistics)
                BillsView().tag(AppTab.bills)
                ProfileView().tag(AppTab.profile)
            }
            .toolbar(.hidden, for: .tabBar)
            .background(Palette.background)

            CustomTabBar(selection: $selectedTab, add: { isAdding = true })
        }
        .tint(Palette.primary)
        .sheet(isPresented: $isAdding) {
            AddTransactionView()
                .environmentObject(store)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Palette.background)
        }
        .overlay(alignment: .bottom) {
            if let message = store.toastMessage {
                Text(message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(hex: 0x20231F))
                    .clipShape(Capsule())
                    .padding(.bottom, 94)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityLabel(message)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.toastMessage)
        .alert("提示", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

private struct CustomTabBar: View {
    @Binding var selection: AppTab
    let add: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            tabButton(.home, title: "首页", symbol: "house")
            tabButton(.statistics, title: "统计", symbol: "chart.bar")
            Color.clear.frame(maxWidth: .infinity)
            tabButton(.bills, title: "账单", symbol: "doc.plaintext")
            tabButton(.profile, title: "我的", symbol: "person")
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .frame(height: 74, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(Palette.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.border).frame(height: 0.5)
        }
        .overlay(alignment: .top) {
            Button(action: add) {
                Image(systemName: "plus")
                    .font(.system(size: 27, weight: .light))
                    .foregroundStyle(Palette.onPrimary)
                    .frame(width: 56, height: 56)
                    .background(Palette.primary)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Palette.background, lineWidth: 4.6))
            }
            .offset(y: -26.5)
            .accessibilityLabel("记一笔")
        }
    }

    private func tabButton(_ tab: AppTab, title: String, symbol: String) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .symbolVariant(selection == tab ? .fill : .none)
                    .font(.system(size: 18, weight: .regular))
                    .frame(height: 20)
                Text(title)
                    .font(.system(size: 14))
            }
            .foregroundStyle(selection == tab ? Palette.primary : Palette.tertiary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}
