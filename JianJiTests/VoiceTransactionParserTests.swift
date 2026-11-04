import XCTest
@testable import JianJi

final class ChineseNumberParserTests: XCTestCase {
    private func amount(_ text: String) -> Decimal? {
        ChineseNumberParser.parseAmountToken(text)
    }

    func testChineseIntegerShorthand() {
        XCTAssertEqual(amount("四十二"), 42)
        XCTAssertEqual(amount("一百二"), 120)
        XCTAssertEqual(amount("一百零五"), 105)
        XCTAssertEqual(amount("两千五"), 2500)
        XCTAssertEqual(amount("一千零五"), 1005)
        XCTAssertEqual(amount("一万八"), 18_000)
    }

    func testMoneyFractions() {
        XCTAssertEqual(amount("十五块八毛"), Decimal(string: "15.8"))
        XCTAssertEqual(amount("三毛"), Decimal(string: "0.3"))
        XCTAssertEqual(amount("五毛二"), Decimal(string: "0.52"))
        XCTAssertEqual(amount("一块零五"), Decimal(string: "1.05"))
        XCTAssertEqual(amount("两块半"), Decimal(string: "2.5"))
        XCTAssertEqual(amount("42.5"), Decimal(string: "42.5"))
        XCTAssertEqual(amount("42元5角"), Decimal(string: "42.5"))
        XCTAssertEqual(amount("三点五"), Decimal(string: "3.5"))
    }
}

final class VoiceTransactionParserTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!
    private var parser: VoiceTransactionParser!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.locale = Locale(identifier: "zh_CN")
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 30
        components.hour = 12
        components.minute = 0
        now = calendar.date(from: components)!
        parser = VoiceTransactionParser(categories: LedgerCategory.defaults)
    }

    private func draft(_ text: String) -> VoiceDraft {
        parser.parse(text, now: now, calendar: calendar)
    }

    private func components(of date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    func testYesterdayLunchWithWeChat() {
        let draft = draft("昨天午饭花了四十二元，用微信支付")
        XCTAssertEqual(draft.type, .expense)
        XCTAssertEqual(draft.amount, 42)
        XCTAssertEqual(draft.categoryID, "food")
        XCTAssertEqual(draft.account, "微信")
        XCTAssertEqual(draft.merchant, "午饭")
        XCTAssertTrue(draft.warnings.isEmpty)
        let date = components(of: draft.date)
        XCTAssertEqual(date.year, 2026)
        XCTAssertEqual(date.month, 10)
        XCTAssertEqual(date.day, 29)
        XCTAssertEqual(date.hour, 12)
    }

    func testTodayTaxi() {
        let draft = draft("今天打车三十五块五")
        XCTAssertEqual(draft.amount, Decimal(string: "35.5"))
        XCTAssertEqual(draft.categoryID, "transport")
        XCTAssertNil(draft.account)
        XCTAssertEqual(draft.merchant, "打车")
        XCTAssertTrue(draft.warnings.isEmpty)
        let date = components(of: draft.date)
        XCTAssertEqual(date.day, 30)
        XCTAssertEqual(date.hour, 12)
    }

    func testLastFridayMovie() {
        let draft = draft("上周五看电影八十")
        XCTAssertEqual(draft.amount, 80)
        XCTAssertEqual(draft.categoryID, "culture")
        XCTAssertEqual(draft.merchant, "看电影")
        let date = components(of: draft.date)
        XCTAssertEqual(date.year, 2026)
        XCTAssertEqual(date.month, 10)
        XCTAssertEqual(date.day, 23)
    }

    func testSalaryIncome() {
        let draft = draft("工资到账一万八")
        XCTAssertEqual(draft.type, .income)
        XCTAssertEqual(draft.amount, 18_000)
        XCTAssertEqual(draft.categoryID, "salary")
        XCTAssertEqual(draft.merchant, "工资")
        XCTAssertTrue(draft.warnings.isEmpty)
    }

    func testRent() {
        let draft = draft("交房租三千五")
        XCTAssertEqual(draft.amount, 3_500)
        XCTAssertEqual(draft.categoryID, "housing")
        XCTAssertEqual(draft.merchant, "房租")
    }

    func testQuantityIsNotAmount() {
        let draft = draft("买了三杯咖啡二十八")
        XCTAssertEqual(draft.amount, 28)
        XCTAssertEqual(draft.categoryID, "food")
        XCTAssertEqual(draft.merchant, "咖啡")
    }

    func testYesterdayAfternoonCoffee() {
        let draft = draft("昨天下午3点喝咖啡28")
        XCTAssertEqual(draft.amount, 28)
        XCTAssertEqual(draft.categoryID, "food")
        XCTAssertTrue(draft.merchant.contains("咖啡"))
        let date = components(of: draft.date)
        XCTAssertEqual(date.day, 29)
        XCTAssertEqual(date.hour, 15)
        XCTAssertEqual(date.minute, 0)
    }

    func testExplicitDateAndDecimalAmount() {
        let draft = draft("10月29日超市126.8")
        XCTAssertEqual(draft.amount, Decimal(string: "126.8"))
        XCTAssertEqual(draft.categoryID, "shopping")
        XCTAssertEqual(draft.merchant, "超市")
        let date = components(of: draft.date)
        XCTAssertEqual(date.month, 10)
        XCTAssertEqual(date.day, 29)
    }

    func testMultipleAmountsKeepsFirst() {
        let draft = draft("午饭42，打车30")
        XCTAssertEqual(draft.amount, 42)
        XCTAssertEqual(draft.categoryID, "food")
        XCTAssertEqual(draft.warnings, [.multipleAmounts])
    }

    func testTransferIsFlagged() {
        let draft = draft("转账500")
        XCTAssertEqual(draft.type, .transfer)
        XCTAssertEqual(draft.amount, 500)
        XCTAssertNil(draft.categoryID)
        XCTAssertTrue(draft.warnings.contains(.transferUnsupported))
    }

    func testConfirmationWithoutAmount() {
        let draft = draft("确认入账")
        XCTAssertTrue(draft.confirmationRequested)
        XCTAssertNil(draft.amount)
        XCTAssertTrue(draft.warnings.contains(.missingAmount))
    }

    func testDecimalPointIsNotTime() {
        let draft = draft("三点五元")
        XCTAssertEqual(draft.amount, Decimal(string: "3.5"))
        XCTAssertTrue(draft.warnings.contains(.categoryFallback))
    }

    func testTimeWithMinutes() {
        let draft = draft("3点30分喝咖啡30")
        XCTAssertEqual(draft.amount, 30)
        XCTAssertEqual(draft.categoryID, "food")
        let date = components(of: draft.date)
        XCTAssertEqual(date.hour, 3)
        XCTAssertEqual(date.minute, 30)
    }

    func testDayOnlyDateRollsToPreviousMonth() {
        let draft = draft("31号交房租3000")
        XCTAssertEqual(draft.amount, 3_000)
        XCTAssertEqual(draft.categoryID, "housing")
        let date = components(of: draft.date)
        XCTAssertEqual(date.month, 9)
        XCTAssertEqual(date.day, 30)
    }

    func testEveningHalfPast() {
        let draft = draft("晚上8点半喝咖啡28")
        XCTAssertEqual(draft.amount, 28)
        let date = components(of: draft.date)
        XCTAssertEqual(date.hour, 20)
        XCTAssertEqual(date.minute, 30)
    }

    func testFutureExplicitDateWarns() {
        let draft = draft("12月1日买书50")
        XCTAssertEqual(draft.amount, 50)
        XCTAssertEqual(draft.categoryID, "culture")
        XCTAssertTrue(draft.warnings.contains(.dateInFuture))
    }
}
