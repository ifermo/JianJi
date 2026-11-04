import SwiftUI

private struct CategoryTotal: Identifiable {
    let id: String
    let name: String
    let amount: Decimal
    let color: Color
}

struct StatisticsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedMonth = Date()
    @State private var showsMonthPicker = false

    private var monthExpenses: [LedgerTransaction] {
        store.transactions.filter {
            $0.type == .expense && Calendar.current.isDate($0.date, equalTo: selectedMonth, toGranularity: .month)
        }
    }

    private var spent: Decimal { monthExpenses.reduce(0) { $0 + $1.amount } }

    private var categoryTotals: [CategoryTotal] {
        let grouped = Dictionary(grouping: monthExpenses, by: \.categoryID)
        let sorted = grouped.map { id, transactions in
            (id: id, amount: transactions.reduce(0) { $0 + $1.amount })
        }.sorted { $0.amount > $1.amount }
        let colors: [Color] = [Palette.primary, Color(hex: 0x7FA68F), Color(hex: 0xC8D5C9), Palette.mint]
        let visible = sorted.prefix(3)
        var result = visible.enumerated().map { index, item in
            CategoryTotal(id: item.id, name: store.category(id: item.id)?.name ?? "其他", amount: item.amount, color: colors[index])
        }
        if sorted.count > 3 {
            let rest = sorted.dropFirst(3).reduce(0) { $0 + $1.amount }
            result.append(CategoryTotal(id: "rest", name: "其他支出", amount: rest, color: colors[3]))
        }
        return result
    }

    private var dailyAverage: Decimal {
        let calendar = Calendar.current
        let isCurrent = calendar.isDate(selectedMonth, equalTo: Date(), toGranularity: .month)
        let days = isCurrent ? calendar.component(.day, from: Date()) : (calendar.range(of: .day, in: .month, for: selectedMonth)?.count ?? 30)
        return spent / Decimal(max(1, days))
    }

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let isCurrent = calendar.isDate(selectedMonth, equalTo: Date(), toGranularity: .month)
        let end: Date
        if isCurrent {
            end = Date()
        } else {
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: store.monthStart(for: selectedMonth)) ?? selectedMonth
            end = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? selectedMonth
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0 - 6, to: end.startOfDay) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("统计").font(.system(size: 20, weight: .medium))
                        Spacer()
                        Button(selectedMonth.monthTitle) { showsMonthPicker = true }
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.primary)
                    }
                    .frame(height: 42)

                    overviewCard.padding(.top, 14)
                    SectionHeading(title: "近七日支出")
                        .padding(.top, 20)
                        .padding(.bottom, 10)
                    weeklyCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 102)
            }
            .background(Palette.background)
            .navigationBarHidden(true)
            .sheet(isPresented: $showsMonthPicker) {
                MonthPicker(selectedMonth: $selectedMonth, months: store.availableMonths)
                    .presentationDetents([.medium])
                    .presentationBackground(Palette.background)
            }
        }
    }

    private var overviewCard: some View {
        VStack(spacing: 0) {
            Text(Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: .month) ? "本月支出" : "\(selectedMonth.monthTitle)支出")
                .font(.system(size: 15))
                .foregroundStyle(Palette.secondary)
            Text("¥ \(Formatters.integer(spent))")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Palette.text)
                .padding(.top, 4)

            if spent == 0 {
                EmptyState(title: "暂无支出", message: "这个月的支出分类会显示在这里")
                    .padding(.vertical, 4)
            } else {
                donut
                    .frame(width: 150, height: 150)
                    .padding(.vertical, 8)
                VStack(spacing: 0) {
                    ForEach(categoryTotals) { item in
                        HStack {
                            Circle().fill(item.color).frame(width: 8, height: 8)
                            Text(item.name)
                            Spacer()
                            Text("\(percent(item.amount))% · ¥ \(Formatters.integer(item.amount))")
                        }
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.text)
                        .padding(.vertical, 9)
                        .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 0.5) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private var donut: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().stroke(Palette.soft, lineWidth: 13)
                ForEach(Array(categoryTotals.enumerated()), id: \.element.id) { index, item in
                    let start = categoryTotals.prefix(index).reduce(0.0) { $0 + fraction($1.amount) }
                    let length = fraction(item.amount)
                    Circle()
                        .trim(from: start, to: min(1, start + max(0, length - 0.012)))
                        .stroke(item.color, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 4) {
                    Text("日均支出").font(.system(size: 14)).foregroundStyle(Palette.secondary)
                    Text("¥ \(Formatters.integer(dailyAverage))")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Palette.text)
                }
            }
            .frame(width: size, height: size)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("支出分类占比图，日均支出 \(Formatters.money(dailyAverage))")
    }

    private var weeklyCard: some View {
        let values = weekDays.map { day in
            monthExpenses.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.amount }
        }
        let maximum = values.max() ?? 0
        return VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(Array(weekDays.enumerated()), id: \.offset) { index, day in
                    let ratio = maximum > 0 ? NSDecimalNumber(decimal: values[index] / maximum).doubleValue : 0
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Calendar.current.isDateInToday(day) ? Palette.primary : Palette.mint)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(3, 82 * ratio))
                        .accessibilityLabel("\(day.shortDayTitle)，支出 \(Formatters.money(values[index]))")
                }
            }
            .frame(height: 98, alignment: .bottom)
            .padding(.horizontal, 8)
            .padding(.top, 7)
            HStack {
                ForEach(weekDays, id: \.self) { day in
                    Text(Calendar.current.isDateInToday(day) ? "今" : day.weekdaySymbol)
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(Palette.secondary)
        }
        .cardStyle(padding: 14)
    }

    private func fraction(_ value: Decimal) -> Double {
        guard spent > 0 else { return 0 }
        return NSDecimalNumber(decimal: value / spent).doubleValue
    }

    private func percent(_ value: Decimal) -> Int {
        Int((fraction(value) * 100).rounded())
    }
}

private struct MonthPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedMonth: Date
    let months: [Date]

    var body: some View {
        NavigationStack {
            List(months, id: \.self) { month in
                Button {
                    selectedMonth = month
                    dismiss()
                } label: {
                    HStack {
                        Text(month.formatted(.dateTime.year().month().locale(Locale(identifier: "zh_CN"))))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        if Calendar.current.isDate(month, equalTo: selectedMonth, toGranularity: .month) {
                            Image(systemName: "checkmark").foregroundStyle(Palette.primary)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("选择月份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}
