import SwiftUI

struct BillsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var selectedType: TransactionType?
    @State private var selectedCategory: String?
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var usesDateRange = false
    @State private var showsFilters = false

    private var filtered: [LedgerTransaction] {
        store.filteredTransactions(
            query: query,
            type: selectedType,
            categoryID: selectedCategory,
            startDate: usesDateRange ? startDate : nil,
            endDate: usesDateRange ? endDate : nil
        )
    }

    private var groups: [(day: Date, items: [LedgerTransaction])] {
        let grouped = Dictionary(grouping: filtered) { $0.date.startOfDay }
        return grouped.map { (day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    private var hasAdvancedFilters: Bool {
        selectedCategory != nil || usesDateRange
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    HStack {
                        Text("账单").font(.system(size: 20, weight: .medium))
                        Spacer()
                        Button {
                            showsFilters = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("筛选")
                                if hasAdvancedFilters { Circle().fill(Palette.primary).frame(width: 5, height: 5) }
                            }
                        }
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.primary)
                    }
                    .frame(height: 42)

                    searchField
                    typeChips
                    if filtered.isEmpty {
                        EmptyState(title: "没有找到账单", message: "换个关键词，或调整筛选条件试试")
                    } else {
                        ForEach(groups, id: \.day) { group in
                            dayHeader(group)
                            VStack(spacing: 0) {
                                ForEach(group.items) { transaction in
                                    NavigationLink {
                                        TransactionDetailView(transactionID: transaction.id)
                                    } label: {
                                        TransactionRow(transaction: transaction, category: store.category(for: transaction))
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) { store.delete(id: transaction.id) } label: {
                                            Label("删除账单", systemImage: "trash")
                                        }
                                    }
                                }
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
            .sheet(isPresented: $showsFilters) {
                FilterSheet(
                    type: $selectedType,
                    categoryID: $selectedCategory,
                    startDate: $startDate,
                    endDate: $endDate,
                    usesDateRange: $usesDateRange
                )
                .presentationDetents([.medium, .large])
                .presentationBackground(Palette.background)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
            TextField("搜索商户、分类或备注", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .accessibilityLabel("清空搜索")
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(Palette.secondary)
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(Palette.field)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var typeChips: some View {
        HStack(spacing: 8) {
            FilterChip(title: "全部", selected: selectedType == nil) {
                selectedType = nil
                selectedCategory = nil
            }
            FilterChip(title: "支出", selected: selectedType == .expense) {
                selectedType = .expense
                selectedCategory = nil
            }
            FilterChip(title: "收入", selected: selectedType == .income) {
                selectedType = .income
                selectedCategory = nil
            }
            Spacer()
        }
    }

    private func dayHeader(_ group: (day: Date, items: [LedgerTransaction])) -> some View {
        let expense = group.items.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        let income = group.items.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let title: String
        if Calendar.current.isDateInToday(group.day) {
            title = "今天 · \(group.day.shortDayTitle)"
        } else if Calendar.current.isDateInYesterday(group.day) {
            title = "昨天 · \(group.day.shortDayTitle)"
        } else {
            title = group.day.shortDayTitle
        }
        return HStack {
            Text(title)
            Spacer()
            if expense > 0 { Text("支出 ¥ \(Formatters.number(expense))") }
            if income > 0 { Text("收入 ¥ \(Formatters.number(income))") }
        }
        .font(.system(size: 15))
        .foregroundStyle(Palette.secondary)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }
}

private struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.system(size: 15))
            .foregroundStyle(selected ? Palette.onPrimary : Palette.secondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(selected ? Palette.primary : Palette.soft)
            .clipShape(Capsule())
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct FilterSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Binding var type: TransactionType?
    @Binding var categoryID: String?
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var usesDateRange: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("账单类型") {
                    Picker("类型", selection: $type) {
                        Text("全部").tag(TransactionType?.none)
                        Text("支出").tag(TransactionType?.some(.expense))
                        Text("收入").tag(TransactionType?.some(.income))
                        Text("转账").tag(TransactionType?.some(.transfer))
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: type) { _, _ in categoryID = nil }
                }

                if let type, type != .transfer {
                    Section("分类") {
                        Picker("分类", selection: $categoryID) {
                            Text("全部分类").tag(String?.none)
                            ForEach(store.categories(for: type)) { category in
                                Label(category.name, systemImage: category.symbol).tag(String?.some(category.id))
                            }
                        }
                    }
                }

                Section {
                    Toggle("按日期范围筛选", isOn: $usesDateRange)
                    if usesDateRange {
                        DatePicker("开始日期", selection: $startDate, in: ...endDate, displayedComponents: .date)
                        DatePicker("结束日期", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("筛选账单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("重置") {
                        type = nil
                        categoryID = nil
                        usesDateRange = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
