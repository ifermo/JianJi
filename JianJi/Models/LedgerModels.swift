import Foundation

enum TransactionType: String, Codable, CaseIterable, Identifiable {
    case expense
    case income
    case transfer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: "支出"
        case .income: "收入"
        case .transfer: "转账"
        }
    }
}

struct LedgerTransaction: Identifiable, Codable, Hashable {
    var id = UUID()
    var type: TransactionType
    var amount: Decimal
    var categoryID: String
    var merchant: String
    var note: String
    var date: Date
    var createdAt = Date()
    var updatedAt: Date
    var sourceAccount: String?
    var destinationAccount: String?

    init(
        id: UUID = UUID(),
        type: TransactionType,
        amount: Decimal,
        categoryID: String,
        merchant: String,
        note: String = "",
        date: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sourceAccount: String? = nil,
        destinationAccount: String? = nil
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.categoryID = categoryID
        self.merchant = merchant
        self.note = note
        self.date = date
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceAccount = sourceAccount
        self.destinationAccount = destinationAccount
    }
}

enum CategoryKind: String, Codable, CaseIterable {
    case expense
    case income

    var title: String { self == .expense ? "支出分类" : "收入分类" }
}

struct LedgerCategory: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var symbol: String
    var kind: CategoryKind
    var updatedAt = Date()

    static let expenseFallbackID = "other"
    static let incomeFallbackID = "other-income"
    static let transferID = "transfer"

    static let defaults: [LedgerCategory] = [
        .init(id: "food", name: "餐饮", symbol: "fork.knife", kind: .expense),
        .init(id: "shopping", name: "购物", symbol: "bag", kind: .expense),
        .init(id: "transport", name: "交通", symbol: "tram", kind: .expense),
        .init(id: "housing", name: "居住", symbol: "house", kind: .expense),
        .init(id: "culture", name: "文化", symbol: "book", kind: .expense),
        .init(id: "medical", name: "医疗", symbol: "cross.case", kind: .expense),
        .init(id: "entertainment", name: "娱乐", symbol: "gamecontroller", kind: .expense),
        .init(id: expenseFallbackID, name: "其他", symbol: "square.grid.2x2", kind: .expense),
        .init(id: "salary", name: "工资", symbol: "briefcase", kind: .income),
        .init(id: "bonus", name: "奖金", symbol: "gift", kind: .income),
        .init(id: "parttime", name: "兼职", symbol: "person.crop.circle", kind: .income),
        .init(id: "investment", name: "理财", symbol: "chart.line.uptrend.xyaxis", kind: .income)
    ]
}

enum AppearanceOption: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
}

struct AppSettings: Codable {
    var monthlyBudget: Decimal = 15_000
    var userName = "JOJO"
    var appearance: AppearanceOption = .system
    var faceIDEnabled = false
    var iCloudSyncEnabled = false
    var firstUseDate = Calendar.current.date(byAdding: .day, value: -127, to: Date()) ?? Date()
    var lastSyncDate: Date?
    var updatedAt = Date()
}

struct PersistedState: Codable {
    var transactions: [LedgerTransaction]
    var categories: [LedgerCategory]
    var settings: AppSettings
    var deletedTransactionIDs: [String: Date] = [:]
    var deletedCategoryIDs: [String: Date] = [:]
}

enum LedgerError: LocalizedError {
    case invalidAmount
    case invalidBudget
    case invalidCategory
    case identicalAccounts
    case authenticationUnavailable
    case authenticationFailed
    case syncDisabled

    var errorDescription: String? {
        switch self {
        case .invalidAmount: "请输入大于 0 的有效金额"
        case .invalidBudget: "预算必须大于 0"
        case .invalidCategory: "该分类不可删除"
        case .identicalAccounts: "转出与转入账户不能相同"
        case .authenticationUnavailable: "当前设备无法使用面容 ID"
        case .authenticationFailed: "面容 ID 验证未完成"
        case .syncDisabled: "请先在设置中开启 iCloud 同步"
        }
    }
}
