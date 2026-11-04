import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var transactions: [LedgerTransaction]
    @Published private(set) var categories: [LedgerCategory]
    @Published private(set) var settings: AppSettings
    @Published var toastMessage: String?
    @Published var errorMessage: String?

    private let persistence: PersistenceService
    private var deletedTransactionIDs: [String: Date]
    private var deletedCategoryIDs: [String: Date]

    init(persistence: PersistenceService = PersistenceService()) {
        self.persistence = persistence
        if let saved = try? persistence.load() {
            transactions = saved.transactions
            categories = saved.categories.isEmpty ? LedgerCategory.defaults : saved.categories
            settings = saved.settings
            deletedTransactionIDs = saved.deletedTransactionIDs
            deletedCategoryIDs = saved.deletedCategoryIDs
        } else {
            let sample = SampleData.make()
            transactions = sample.transactions
            categories = sample.categories
            settings = sample.settings
            deletedTransactionIDs = [:]
            deletedCategoryIDs = [:]
            try? persistence.save(sample)
        }
    }

    var snapshot: PersistedState {
        PersistedState(
            transactions: transactions,
            categories: categories,
            settings: settings,
            deletedTransactionIDs: deletedTransactionIDs,
            deletedCategoryIDs: deletedCategoryIDs
        )
    }

    var transferCategory: LedgerCategory {
        LedgerCategory(id: LedgerCategory.transferID, name: "转账", symbol: "arrow.left.arrow.right", kind: .expense)
    }

    func category(for transaction: LedgerTransaction) -> LedgerCategory? {
        transaction.type == .transfer ? transferCategory : category(id: transaction.categoryID)
    }

    func category(id: String) -> LedgerCategory? {
        categories.first { $0.id == id }
    }

    func categories(for type: TransactionType) -> [LedgerCategory] {
        switch type {
        case .expense: categories.filter { $0.kind == .expense }
        case .income: categories.filter { $0.kind == .income }
        case .transfer: [transferCategory]
        }
    }

    func total(_ type: TransactionType, in month: Date = Date()) -> Decimal {
        guard type != .transfer else { return 0 }
        return transactions
            .filter { $0.type == type && Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }

    var monthlyCount: Int {
        transactions.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }.count
    }

    var recordingDays: Int {
        let days = Calendar.current.dateComponents([.day], from: settings.firstUseDate.startOfDay, to: Date().startOfDay).day ?? 0
        return max(1, days + 1)
    }

    var availableMonths: [Date] {
        var months = Set(transactions.map { monthStart(for: $0.date) })
        months.insert(monthStart(for: Date()))
        return months.sorted(by: >)
    }

    func monthStart(for date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date.startOfDay
    }

    func add(_ transaction: LedgerTransaction) throws {
        try validate(transaction)
        transactions.insert(transaction, at: 0)
        sortTransactions()
        persist()
        toast("账单已保存")
    }

    func update(_ transaction: LedgerTransaction) throws {
        try validate(transaction)
        guard let index = transactions.firstIndex(where: { $0.id == transaction.id }) else { return }
        var changed = transaction
        changed.updatedAt = Date()
        transactions[index] = changed
        sortTransactions()
        persist()
        toast("修改已保存")
    }

    func delete(id: UUID) {
        transactions.removeAll { $0.id == id }
        deletedTransactionIDs[id.uuidString] = Date()
        persist()
        toast("账单已删除")
    }

    func updateBudget(_ value: Decimal) throws {
        guard value > 0, value <= CalculatorEngine.maximumAmount else { throw LedgerError.invalidBudget }
        settings.monthlyBudget = Formatters.rounded(value)
        settings.updatedAt = Date()
        persist()
        toast("每月预算已更新")
    }

    func updateUserName(_ value: String) throws {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 20 else { throw LedgerError.invalidCategory }
        settings.userName = name
        settings.updatedAt = Date()
        persist()
    }

    func updateAppearance(_ appearance: AppearanceOption) {
        settings.appearance = appearance
        settings.updatedAt = Date()
        persist()
    }

    func updateFaceID(_ enabled: Bool) {
        settings.faceIDEnabled = enabled
        settings.updatedAt = Date()
        persist()
    }

    func updateICloud(_ enabled: Bool) {
        settings.iCloudSyncEnabled = enabled
        if !enabled { settings.lastSyncDate = nil }
        settings.updatedAt = Date()
        persist()
    }

    func markSynced(at date: Date = Date()) {
        settings.lastSyncDate = date
        persist()
    }

    func replaceForSync(_ state: PersistedState) {
        transactions = state.transactions
        categories = state.categories
        settings = state.settings
        deletedTransactionIDs = state.deletedTransactionIDs
        deletedCategoryIDs = state.deletedCategoryIDs
        sortTransactions()
        persist()
    }

    @discardableResult
    func addCategory(name: String, kind: CategoryKind) throws -> LedgerCategory {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 8,
              !categories.contains(where: { $0.name == trimmed && $0.kind == kind }) else {
            throw LedgerError.invalidCategory
        }
        let category = LedgerCategory(id: UUID().uuidString, name: trimmed, symbol: "tag", kind: kind)
        categories.append(category)
        persist()
        return category
    }

    func renameCategory(id: String, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = categories.firstIndex(where: { $0.id == id }),
              !trimmed.isEmpty, trimmed.count <= 8,
              !categories.contains(where: { $0.id != id && $0.name == trimmed && $0.kind == categories[index].kind }) else {
            throw LedgerError.invalidCategory
        }
        categories[index].name = trimmed
        categories[index].updatedAt = Date()
        persist()
    }

    func deleteCategory(id: String) throws {
        guard id != LedgerCategory.expenseFallbackID, id != LedgerCategory.incomeFallbackID,
              let index = categories.firstIndex(where: { $0.id == id }) else {
            throw LedgerError.invalidCategory
        }
        let kind = categories[index].kind
        guard categories.filter({ $0.kind == kind }).count > 1 else { throw LedgerError.invalidCategory }
        let fallback = kind == .expense ? LedgerCategory.expenseFallbackID : LedgerCategory.incomeFallbackID
        for transactionIndex in transactions.indices where transactions[transactionIndex].categoryID == id {
            transactions[transactionIndex].categoryID = fallback
        }
        categories.remove(at: index)
        deletedCategoryIDs[id] = Date()
        persist()
    }

    func filteredTransactions(
        query: String = "",
        type: TransactionType? = nil,
        categoryID: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> [LedgerTransaction] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return transactions.filter { transaction in
            if let type, transaction.type != type { return false }
            if let categoryID, transaction.categoryID != categoryID { return false }
            if let startDate, transaction.date < startDate.startOfDay { return false }
            if let endDate {
                let end = Calendar.current.date(byAdding: .day, value: 1, to: endDate.startOfDay) ?? endDate
                if transaction.date >= end { return false }
            }
            if !keyword.isEmpty {
                let haystack = [transaction.merchant, transaction.note, category(for: transaction)?.name ?? ""]
                    .joined(separator: " ").lowercased()
                if !haystack.contains(keyword) { return false }
            }
            return true
        }
    }

    func toast(_ message: String) {
        toastMessage = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled, self?.toastMessage == message else { return }
            self?.toastMessage = nil
        }
    }

    private func validate(_ transaction: LedgerTransaction) throws {
        guard transaction.amount > 0, transaction.amount <= CalculatorEngine.maximumAmount else {
            throw LedgerError.invalidAmount
        }
        if transaction.type == .transfer,
           transaction.sourceAccount == transaction.destinationAccount {
            throw LedgerError.identicalAccounts
        }
    }

    private func sortTransactions() {
        transactions.sort { lhs, rhs in
            lhs.date == rhs.date ? lhs.createdAt > rhs.createdAt : lhs.date > rhs.date
        }
    }

    private func persist() {
        do {
            try persistence.save(snapshot)
        } catch {
            errorMessage = "数据保存失败：\(error.localizedDescription)"
        }
    }
}

private enum SampleData {
    static func make() -> PersistedState {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        func date(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
            let daysInMonth = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
            let currentDay = calendar.component(.day, from: now)
            let clampedDay = min(max(1, day), daysInMonth, currentDay)
            let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.date(byAdding: .day, value: clampedDay - 1, to: month) ?? month) ?? month
            return candidate > now ? now.addingTimeInterval(-60) : candidate
        }

        var items: [LedgerTransaction] = [
            .init(type: .expense, amount: 126.80, categoryID: "shopping", merchant: "超市采购", date: date(29, 18, 24)),
            .init(type: .expense, amount: 42, categoryID: "food", merchant: "一乐拉面", date: date(29, 12, 16)),
            .init(type: .expense, amount: 6, categoryID: "transport", merchant: "地铁出行", date: date(29, 8, 42)),
            .init(type: .expense, amount: 68, categoryID: "culture", merchant: "云端书城", date: date(28, 20, 8)),
            .init(type: .expense, amount: 3, categoryID: "transport", merchant: "共享单车", date: date(28, 9, 20)),
            .init(type: .income, amount: 18_000, categoryID: "salary", merchant: "十月工资", date: date(10, 10))
        ]

        let plans: [(String, Decimal, String, [String])] = [
            ("food", 3_689 - 42, "餐饮", ["山丘咖啡", "外婆家", "清晨食堂", "鲜果铺"]),
            ("shopping", 2_402 - 126.8, "购物", ["无印良品", "生活超市", "好物商店"]),
            ("transport", 1_630 - 9, "交通", ["高铁出行", "滴滴出行", "地铁出行"]),
            ("other", 859 - 68, "日常", ["居住缴费", "文化生活", "日用杂项"])
        ]

        for (category, total, fallback, names) in plans {
            var remaining = total
            for (index, name) in names.enumerated() {
                let portions = Decimal(names.count - index)
                var amount = index == names.count - 1 ? remaining : Formatters.rounded(remaining / portions)
                amount = max(0, amount)
                items.append(.init(type: .expense, amount: amount, categoryID: category == "other" && name == "文化生活" ? "culture" : category,
                                   merchant: name.isEmpty ? fallback : name, date: date(max(1, 26 - items.count), 11 + index)))
                remaining -= amount
            }
        }

        return PersistedState(transactions: items, categories: LedgerCategory.defaults, settings: AppSettings())
    }
}
