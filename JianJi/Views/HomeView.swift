import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    let showAllBills: () -> Void

    private var spent: Decimal { store.total(.expense) }
    private var income: Decimal { store.total(.income) }
    private var available: Decimal { store.settings.monthlyBudget - spent }
    private var usage: Double {
        guard store.settings.monthlyBudget > 0 else { return 0 }
        return min(1, max(0, NSDecimalNumber(decimal: spent / store.settings.monthlyBudget).doubleValue))
    }
    private var usedPercent: Int { Int((usage * 100).rounded()) }
    private var daysRemaining: Int {
        let calendar = Calendar.current
        let now = Date()
        let days = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let today = calendar.component(.day, from: now)
        return max(0, days - today)
    }
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "早上好"
        case 11..<14: return "中午好"
        case 14..<18: return "下午好"
        default: return "晚上好"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    budgetHero.padding(.top, 14)
                    summaryCards
                    HStack {
                        SectionHeading(title: "最近账单")
                        Spacer()
                        Button("全部账单", action: showAllBills)
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.primary)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 2)

                    if store.transactions.isEmpty {
                        EmptyState(title: "还没有账单", message: "点击下方的加号，记下第一笔")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(store.transactions.prefix(3))) { transaction in
                                NavigationLink {
                                    TransactionDetailView(transactionID: transaction.id)
                                } label: {
                                    TransactionRow(transaction: transaction, category: store.category(for: transaction), showsDate: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 102)
            }
            .background(Palette.background)
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(Date().fullDayTitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.secondary)
                Text("\(greeting)，\(store.settings.userName)")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 10)
            Text(String(store.settings.userName.prefix(1)).uppercased())
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.primary)
                .frame(width: 34, height: 34)
                .background(Palette.mint)
                .clipShape(Circle())
        }
        .frame(minHeight: 42)
    }

    private var budgetHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("本月可用")
                Spacer()
                Text("日常预算")
            }
            .font(.system(size: 15))
            .foregroundStyle(Palette.primary.opacity(0.75))

            Text(Formatters.money(available))
                .font(.system(size: 36, weight: .medium))
                .tracking(-1.2)
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.top, 7)
                .padding(.bottom, 16)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.primary.opacity(0.2))
                    Capsule().fill(Palette.primary).frame(width: geometry.size.width * usage)
                }
            }
            .frame(height: 5)
            .padding(.vertical, 3)

            HStack {
                Text(spent > store.settings.monthlyBudget ? "已超出预算" : "已使用 \(usedPercent)%")
                Spacer()
                Text("剩余 \(daysRemaining) 天")
            }
            .font(.system(size: 15))
            .foregroundStyle(Palette.primary.opacity(0.75))
            .padding(.top, 5)
        }
        .padding(18)
        .background(Palette.hero)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var summaryCards: some View {
        HStack(spacing: 10) {
            SummaryCard(title: "本月支出", value: Formatters.money(spent))
            SummaryCard(title: "本月收入", value: Formatters.money(income))
        }
        .padding(.vertical, 12)
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Palette.secondary)
            Text(value)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 14)
    }
}
