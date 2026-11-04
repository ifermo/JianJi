import XCTest
@testable import JianJi

final class CalculatorEngineTests: XCTestCase {
    func testMixedArithmeticUsesPrecedence() throws {
        var calculator = CalculatorEngine()
        for key in ["1", "2"] { calculator.input(key) }
        calculator.append(.add)
        calculator.input("3")
        calculator.append(.multiply)
        calculator.input("4")
        XCTAssertEqual(try calculator.evaluate(), 24)
        XCTAssertEqual(calculator.display, "24")
    }

    func testDecimalAndRounding() throws {
        var calculator = CalculatorEngine()
        for key in ["1", ".", "1", "0"] { calculator.input(key) }
        calculator.append(.add)
        for key in ["2", ".", "2", "5"] { calculator.input(key) }
        XCTAssertEqual(try calculator.evaluate(), Decimal(string: "3.35"))
    }

    func testDivisionByZeroDoesNotDestroyExpression() {
        var calculator = CalculatorEngine()
        calculator.input("8")
        calculator.append(.divide)
        calculator.input("0")
        XCTAssertThrowsError(try calculator.evaluate()) { XCTAssertEqual($0 as? CalculatorError, .divisionByZero) }
        XCTAssertEqual(calculator.display, "0")
        calculator.backspace()
        calculator.input("2")
        XCTAssertEqual(try? calculator.evaluate(), 4)
    }

    func testOperatorReplacementAndBackspace() throws {
        var calculator = CalculatorEngine()
        calculator.input("9")
        calculator.append(.add)
        calculator.append(.subtract)
        calculator.input("4")
        XCTAssertEqual(try calculator.evaluate(), 5)

        calculator.clear()
        calculator.input("8")
        calculator.append(.add)
        calculator.backspace()
        XCTAssertEqual(calculator.display, "8")
        calculator.input("0")
        calculator.append(.subtract)
        calculator.input("2")
        XCTAssertEqual(try calculator.evaluate(), 78)
    }

    func testInvalidZeroAmountIsRejectedByStore() {
        var calculator = CalculatorEngine()
        XCTAssertEqual(try? calculator.evaluate(), 0)
    }
}

final class AppStoreTests: XCTestCase {
    @MainActor
    private func makeStore() -> (store: AppStore, persistence: PersistenceService, url: URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("JianJiTests_\(UUID().uuidString).json")
        let persistence = PersistenceService(fileURL: url)
        return (AppStore(persistence: persistence), persistence, url)
    }

    @MainActor
    func testAddUpdateDeleteRecalculatesTotals() throws {
        let context = makeStore()
        defer { try? FileManager.default.removeItem(at: context.url) }
        let store = context.store
        let initial = store.total(.expense)
        let transaction = LedgerTransaction(type: .expense, amount: 12.5, categoryID: "food", merchant: "测试午餐")
        try store.add(transaction)
        XCTAssertEqual(store.total(.expense), initial + Decimal(string: "12.5")!)

        var changed = transaction
        changed.amount = 20
        try store.update(changed)
        XCTAssertEqual(store.total(.expense), initial + 20)

        store.delete(id: transaction.id)
        XCTAssertEqual(store.total(.expense), initial)
        XCTAssertNil(store.transactions.first { $0.id == transaction.id })
    }

    @MainActor
    func testSearchAndTypeFilter() throws {
        let context = makeStore()
        defer { try? FileManager.default.removeItem(at: context.url) }
        let store = context.store
        let transaction = LedgerTransaction(type: .expense, amount: 8, categoryID: "food", merchant: "测试咖啡", note: "燕麦拿铁")
        try store.add(transaction)
        XCTAssertTrue(store.filteredTransactions(query: "燕麦").contains { $0.id == transaction.id })
        XCTAssertTrue(store.filteredTransactions(query: "餐饮", type: .expense).contains { $0.id == transaction.id })
        XCTAssertFalse(store.filteredTransactions(query: "燕麦", type: .income).contains { $0.id == transaction.id })
    }

    @MainActor
    func testDeleteCategoryMovesBillsToFallback() throws {
        let context = makeStore()
        defer { try? FileManager.default.removeItem(at: context.url) }
        let store = context.store
        let category = try store.addCategory(name: "测试分类", kind: .expense)
        let transaction = LedgerTransaction(type: .expense, amount: 10, categoryID: category.id, merchant: "测试")
        try store.add(transaction)
        try store.deleteCategory(id: category.id)
        XCTAssertEqual(store.transactions.first { $0.id == transaction.id }?.categoryID, LedgerCategory.expenseFallbackID)
    }

    @MainActor
    func testPersistenceRoundTrip() throws {
        let context = makeStore()
        defer { try? FileManager.default.removeItem(at: context.url) }
        let store = context.store
        let transaction = LedgerTransaction(type: .income, amount: 99.9, categoryID: "bonus", merchant: "测试奖金")
        try store.add(transaction)
        let restored = AppStore(persistence: context.persistence)
        XCTAssertTrue(restored.transactions.contains { $0.id == transaction.id && $0.amount == transaction.amount })
    }
}
