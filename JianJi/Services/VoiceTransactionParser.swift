import Foundation

enum VoiceWarning: String, Equatable {
    case missingAmount
    case multipleAmounts
    case categoryFallback
    case dateInFuture
    case transferUnsupported

    var message: String {
        switch self {
        case .missingAmount: "未识别到金额，请补充"
        case .multipleAmounts: "检测到多笔金额，仅记录第一笔"
        case .categoryFallback: "分类未识别，已归入“其他”"
        case .dateInFuture: "日期在未来，请确认"
        case .transferUnsupported: "语音转账暂不支持，请用键盘输入"
        }
    }
}

struct VoiceDraft: Equatable {
    var type: TransactionType
    var amount: Decimal?
    var categoryID: String?
    var date: Date
    var account: String?
    var merchant: String
    var note: String
    var warnings: [VoiceWarning]
    var highlights: [String]
    var confirmationRequested: Bool
}

struct VoiceTransactionParser {
    let categories: [LedgerCategory]

    init(categories: [LedgerCategory]) {
        self.categories = categories
    }

    func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> VoiceDraft {
        let normalized = ChineseNumberParser.normalize(text)
        let note = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = detectType(in: normalized)
        let dateInfo = parseDate(in: normalized, now: now, calendar: calendar)

        var amountSearchText = normalized
        let phrases = Set(dateInfo.phrases).sorted { $0.count > $1.count }
        for phrase in phrases {
            amountSearchText = replacingAll(phrase, in: amountSearchText)
        }

        let amountInfo = parseAmount(in: amountSearchText)
        let accountInfo = detectAccount(in: normalized)
        let categoryInfo = detectCategory(in: normalized, type: type)
        let confirmation = detectConfirmation(in: normalized)

        var warnings: [VoiceWarning] = []
        if amountInfo.value == nil {
            warnings.append(.missingAmount)
        }
        if amountInfo.count > 1 {
            warnings.append(.multipleAmounts)
        }
        if type == .transfer {
            warnings.append(.transferUnsupported)
        }
        if categoryInfo.isFallback, type != .transfer {
            warnings.append(.categoryFallback)
        }
        if dateInfo.isFutureDay {
            warnings.append(.dateInFuture)
        }

        let merchant = makeMerchant(
            normalized: normalized,
            datePhrases: dateInfo.phrases,
            amountTexts: amountInfo.allTexts,
            accountPhrase: accountInfo.phrase,
            confirmation: confirmation
        )
        let categoryName = categoryInfo.id.flatMap { id in categories.first { $0.id == id }?.name }
        let fallbackName = type == .transfer ? "转账" : "账单"
        let finalMerchant = merchant.isEmpty ? (categoryName ?? fallbackName) : merchant

        var highlights: [String] = []
        for value in [amountInfo.selectedText, dateInfo.highlight, categoryInfo.keyword, accountInfo.phrase] {
            if let value, !value.isEmpty, !highlights.contains(value) {
                highlights.append(value)
            }
        }

        return VoiceDraft(
            type: type,
            amount: amountInfo.value,
            categoryID: type == .transfer ? nil : categoryInfo.id,
            date: dateInfo.date,
            account: accountInfo.account,
            merchant: finalMerchant,
            note: note,
            warnings: warnings,
            highlights: highlights,
            confirmationRequested: confirmation
        )
    }

    // MARK: - Type

    private func detectType(in text: String) -> TransactionType {
        let transferKeywords = ["转账", "转给", "转到", "转入", "转出", "汇款"]
        if transferKeywords.contains(where: { text.contains($0) }) {
            return .transfer
        }
        let incomeKeywords = [
            "工资", "薪水", "薪资", "奖金", "年终奖", "提成", "到账", "收到",
            "进账", "报销", "退款", "收入", "利息", "分红", "红包", "兼职",
            "外快", "副业", "理财收益"
        ]
        if incomeKeywords.contains(where: { text.contains($0) }) {
            return .income
        }
        return .expense
    }

    // MARK: - Date / time

    private struct DateInfo {
        var date: Date
        var phrases: [String]
        var highlight: String?
        var isFutureDay: Bool
    }

    private func parseDate(in text: String, now: Date, calendar: Calendar) -> DateInfo {
        var base = now
        var phrases: [String] = []
        var highlight: String?
        var futureWord = false

        if let match = firstMatch(#"(大前天|前天|昨天|昨日|昨儿|今天|今日|刚才|刚刚|明天|明日|后天)"#, in: text) {
            phrases.append(match.full)
            if highlight == nil { highlight = match.full }
            switch match.full {
            case "大前天":
                base = calendar.date(byAdding: .day, value: -3, to: now) ?? now
            case "前天":
                base = calendar.date(byAdding: .day, value: -2, to: now) ?? now
            case "昨天", "昨日", "昨儿":
                base = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            case "明天", "明日":
                base = calendar.date(byAdding: .day, value: 1, to: now) ?? now
                futureWord = true
            case "后天":
                base = calendar.date(byAdding: .day, value: 2, to: now) ?? now
                futureWord = true
            default:
                base = now
            }
        }

        if let match = firstMatch(#"(上|下)?(?:个)?(?:周|星期|礼拜)([一二三四五六日天])"#, in: text) {
            phrases.append(match.full)
            if highlight == nil { highlight = match.full }
            let prefix = match.groups[0]
            let weekday = match.groups[1]
            if let target = weekdayValue(weekday) {
                let current = calendar.component(.weekday, from: now)
                switch prefix {
                case "上":
                    var back = (current - target + 7) % 7
                    if back == 0 { back = 7 }
                    base = calendar.date(byAdding: .day, value: -back, to: now) ?? now
                case "下":
                    var forward = (target - current + 7) % 7
                    if forward == 0 { forward = 7 }
                    base = calendar.date(byAdding: .day, value: forward, to: now) ?? now
                    futureWord = true
                default:
                    let back = (current - target + 7) % 7
                    base = calendar.date(byAdding: .day, value: -back, to: now) ?? now
                }
            }
        }

        if let match = firstMatch(#"(上个?月|上月|这个月|本月|下个?月|下月)"#, in: text) {
            phrases.append(match.full)
            if highlight == nil { highlight = match.full }
            if match.full.contains("上") {
                base = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            } else if match.full.contains("下") {
                base = calendar.date(byAdding: .month, value: 1, to: now) ?? now
                futureWord = true
            } else {
                base = now
            }
        }

        if let match = firstMatch(#"(\d{4})年(\d{1,2})月(\d{1,2})[日号]"#, in: text) {
            phrases.append(match.full)
            if highlight == nil { highlight = match.full }
            if let year = Int(match.groups[0]), let month = Int(match.groups[1]), let day = Int(match.groups[2]) {
                base = makeDate(year: year, month: month, day: day, calendar: calendar, now: now)
            }
        } else if let match = firstMatch(#"(\d{1,2})月(\d{1,2})[日号]"#, in: text) {
            phrases.append(match.full)
            if highlight == nil { highlight = match.full }
            if let month = Int(match.groups[0]), let day = Int(match.groups[1]) {
                let year = calendar.component(.year, from: now)
                base = makeDate(year: year, month: month, day: day, calendar: calendar, now: now)
            }
        } else if let match = firstMatch(#"([零〇一二两三四五六七八九十百]+)月([零〇一二两三四五六七八九十百]+)[日号]"#, in: text) {
            phrases.append(match.full)
            if highlight == nil { highlight = match.full }
            if let month = parseInteger(match.groups[0]), let day = parseInteger(match.groups[1]) {
                let year = calendar.component(.year, from: now)
                base = makeDate(year: year, month: month, day: day, calendar: calendar, now: now)
            }
        } else if let match = firstMatch(#"(\d{1,2})[日号]"#, in: text) {
            phrases.append(match.full)
            if highlight == nil { highlight = match.full }
            if let day = Int(match.groups[0]) {
                base = makeDayOnly(day: day, calendar: calendar, now: now)
            }
        }

        var period: (name: String, hour: Int)?
        let periods: [(String, Int)] = [
            ("凌晨", 1), ("早上", 8), ("早晨", 8), ("上午", 8), ("中午", 12),
            ("下午", 15), ("傍晚", 18), ("晚上", 20), ("夜里", 21), ("夜间", 21)
        ]
        if let found = periods.first(where: { text.contains($0.0) }) {
            phrases.append(found.0)
            if highlight == nil { highlight = found.0 }
            period = (found.0, found.1)
        }

        var explicitTime: (hour: Int, minute: Int)?
        if let match = firstMatch(
            #"(凌晨|早上|早晨|上午|中午|下午|傍晚|晚上|夜里|夜间)?(\d{1,2}|[零〇一二两三四五六七八九十]+)(?:点|时)(?:(\d{1,2}|[零〇一二两三四五六七八九十]+)分|(半))?"#,
            in: text
        ) {
            let periodGroup = match.groups[0]
            let minuteGroup = match.groups[2]
            let halfGroup = match.groups[3]
            let hasPeriod = !periodGroup.isEmpty
            let hasMinute = !minuteGroup.isEmpty || !halfGroup.isEmpty
            if hasPeriod || hasMinute, let hour = parseInteger(match.groups[1]) {
                phrases.append(match.full)
                if highlight == nil { highlight = match.full }
                let effectivePeriod = hasPeriod ? periodGroup : period?.name
                let adjusted = adjustHour(hour, period: effectivePeriod)
                let minute = halfGroup.isEmpty ? (parseInteger(minuteGroup) ?? 0) : 30
                explicitTime = (min(23, max(0, adjusted)), min(59, max(0, minute)))
            }
        }

        if explicitTime == nil,
           let match = firstMatch(#"(\d{1,2})[:：](\d{2})"#, in: text),
           let hour = Int(match.groups[0]),
           let minute = Int(match.groups[1]) {
            phrases.append(match.full)
            if highlight == nil { highlight = match.full }
            explicitTime = (hour, minute)
        }

        var resolved = base
        let isToday = calendar.isDate(resolved, inSameDayAs: now)
        if let explicitTime {
            resolved = calendar.date(bySettingHour: explicitTime.hour, minute: explicitTime.minute, second: 0, of: resolved) ?? resolved
        } else if let period {
            resolved = calendar.date(bySettingHour: period.hour, minute: 0, second: 0, of: resolved) ?? resolved
        } else if !isToday {
            resolved = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: resolved) ?? resolved
        }

        let isFutureDay = calendar.startOfDay(for: resolved) > calendar.startOfDay(for: now) && !futureWord
        return DateInfo(date: resolved, phrases: phrases, highlight: highlight, isFutureDay: isFutureDay)
    }

    private func makeDate(year: Int, month: Int, day: Int, calendar: Calendar, now: Date) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        let days = calendar.range(of: .day, in: .month, for: calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? now)?.count ?? 30
        components.day = min(max(1, day), days)
        return calendar.date(from: components) ?? now
    }

    private func makeDayOnly(day: Int, calendar: Calendar, now: Date) -> Date {
        let nowDay = calendar.component(.day, from: now)
        if day > nowDay {
            var components = calendar.dateComponents([.year, .month], from: now)
            components.month = (components.month ?? 1) - 1
            if components.month == 0 {
                components.month = 12
                components.year = (components.year ?? 2026) - 1
            }
            let monthStart = calendar.date(from: components) ?? now
            let days = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
            components.day = min(day, days)
            return calendar.date(from: components) ?? now
        }
        var components = calendar.dateComponents([.year, .month], from: now)
        let days = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        components.day = min(max(1, day), days)
        return calendar.date(from: components) ?? now
    }

    private func adjustHour(_ hour: Int, period: String?) -> Int {
        guard let period else { return hour }
        switch period {
        case "下午", "傍晚":
            return hour < 12 ? hour + 12 : hour
        case "晚上", "夜里", "夜间":
            if hour == 12 { return 0 }
            return hour < 12 ? hour + 12 : hour
        case "中午":
            return hour < 11 ? hour + 12 : hour
        case "凌晨":
            return hour == 12 ? 0 : hour
        default:
            return hour
        }
    }

    private func weekdayValue(_ text: String) -> Int? {
        switch text {
        case "日", "天": 1
        case "一": 2
        case "二": 3
        case "三": 4
        case "四": 5
        case "五": 6
        case "六": 7
        default: nil
        }
    }

    private func parseInteger(_ text: String) -> Int? {
        guard !text.isEmpty, let value = ChineseNumberParser.parseNumber(text) else { return nil }
        return NSDecimalNumber(decimal: value).intValue
    }

    // MARK: - Amount

    private struct AmountInfo {
        var value: Decimal?
        var selectedText: String?
        var allTexts: [String]
        var count: Int
    }

    private static let classifierCharacters = "点号日个杯人份张件瓶盒包斤岁天周月次公里小时分钟秒钟"

    private func parseAmount(in text: String) -> AmountInfo {
        let characters = Array(text)
        var candidates: [(text: String, value: Decimal)] = []
        var index = 0

        while index < characters.count {
            let character = characters[index]
            guard ChineseNumberParser.isNumberCharacter(character) || ChineseNumberParser.isCurrencyCharacter(character) else {
                index += 1
                continue
            }

            let start = index
            var end = index
            while end < characters.count {
                let current = characters[end]
                if current == "." {
                    let previous = end > start ? characters[end - 1] : nil
                    let next = end + 1 < characters.count ? characters[end + 1] : nil
                    if previous?.wholeNumberValue != nil, next?.wholeNumberValue != nil {
                        end += 1
                        continue
                    }
                    break
                }
                if ChineseNumberParser.isNumberCharacter(current) || ChineseNumberParser.isCurrencyCharacter(current) {
                    end += 1
                } else {
                    break
                }
            }

            let rawSpan = String(characters[start..<end])
            let span = String(rawSpan.drop(while: { ChineseNumberParser.isCurrencyCharacter($0) }))
            let nextCharacter = end < characters.count ? characters[end] : nil
            if !span.isEmpty,
               let value = ChineseNumberParser.parseAmountToken(span),
               value > 0,
               value <= CalculatorEngine.maximumAmount {
                let hasCurrency = span.contains(where: { ChineseNumberParser.isCurrencyCharacter($0) })
                let endsWithPoint = span.last == "点"
                let followedByClassifier = nextCharacter.map { Self.classifierCharacters.contains($0) } ?? false
                let minutePhrase = nextCharacter == "钟" && !span.contains(where: { "元块圆角毛".contains($0) })
                if !(!hasCurrency && followedByClassifier) && !(!hasCurrency && endsWithPoint) && !minutePhrase {
                    candidates.append((span, value))
                }
            }
            index = max(end, index + 1)
        }

        let first = candidates.first
        let rounded = first.map { Formatters.rounded($0.value) }
        return AmountInfo(
            value: rounded,
            selectedText: first?.text,
            allTexts: candidates.map(\.text),
            count: candidates.count
        )
    }

    // MARK: - Category / account

    private struct CategoryMatch {
        var id: String?
        var keyword: String?
        var isFallback: Bool
    }

    private static let expenseRules: [(String, [String])] = [
        ("food", ["早餐", "早饭", "午餐", "午饭", "中饭", "晚饭", "晚餐", "夜宵", "宵夜", "外卖", "咖啡", "奶茶", "饮料", "火锅", "烧烤", "拉面", "面馆", "食堂", "餐厅", "饭店", "零食", "水果", "买菜", "菜市场", "蛋糕", "面包", "聚餐", "酒"]),
        ("shopping", ["超市", "便利店", "淘宝", "京东", "拼多多", "网购", "衣服", "鞋", "化妆品", "日用品", "家具", "家电", "数码", "购物", "商店"]),
        ("transport", ["打车", "滴滴", "出租车", "地铁", "公交", "高铁", "火车", "飞机", "机票", "加油", "停车", "共享单车", "单车", "充电", "过路费", "高速"]),
        ("housing", ["房租", "租金", "水电", "电费", "水费", "燃气", "物业", "宽带", "房贷"]),
        ("culture", ["书店", "电影", "演出", "展览", "课程", "学习", "文具", "音乐会", "书"]),
        ("medical", ["医院", "看病", "挂号", "药店", "药", "体检", "牙医", "医疗"]),
        ("entertainment", ["游戏", "KTV", "唱歌", "会员", "娱乐", "剧本杀", "桌游", "景点", "门票"]),
        ("other", ["其他", "日常", "杂项"])
    ]

    private static let incomeRules: [(String, [String])] = [
        ("salary", ["工资", "薪水", "薪资"]),
        ("bonus", ["奖金", "年终奖", "提成"]),
        ("parttime", ["兼职", "外快", "副业"]),
        ("investment", ["理财", "利息", "分红", "基金", "股票", "投资"])
    ]

    private func detectCategory(in text: String, type: TransactionType) -> CategoryMatch {
        guard type != .transfer else { return CategoryMatch(id: nil, keyword: nil, isFallback: false) }
        let kind: CategoryKind = type == .income ? .income : .expense
        let allowed = Set(categories.filter { $0.kind == kind }.map(\.id))
        var rules: [(String, String)] = []

        let builtIns = type == .income ? Self.incomeRules : Self.expenseRules
        for (id, keywords) in builtIns where allowed.contains(id) {
            for keyword in keywords { rules.append((id, keyword)) }
        }
        let builtInIDs = Set(LedgerCategory.defaults.map(\.id))
        for category in categories where category.kind == kind && !builtInIDs.contains(category.id) {
            rules.append((category.id, category.name))
        }

        let ns = text as NSString
        var best: (id: String, keyword: String, location: Int)?
        for rule in rules {
            let range = ns.range(of: rule.1)
            guard range.location != NSNotFound else { continue }
            if best == nil
                || range.location < best!.location
                || (range.location == best!.location && rule.1.count > best!.keyword.count) {
                best = (rule.0, rule.1, range.location)
            }
        }

        if let best {
            return CategoryMatch(id: best.id, keyword: best.keyword, isFallback: false)
        }
        let fallbackID = type == .income ? LedgerCategory.incomeFallbackID : LedgerCategory.expenseFallbackID
        let id = allowed.contains(fallbackID) ? fallbackID : allowed.first
        return CategoryMatch(id: id, keyword: nil, isFallback: true)
    }

    private static let accountRules: [(String, [String])] = [
        ("微信", ["微信支付", "微信零钱", "微信", "零钱"]),
        ("支付宝", ["支付宝", "花呗", "余额宝"]),
        ("银行卡", ["银行卡", "储蓄卡", "借记卡", "信用卡", "刷卡"]),
        ("现金", ["现金"])
    ]

    private func detectAccount(in text: String) -> (account: String?, phrase: String?) {
        let ns = text as NSString
        var best: (account: String, phrase: String, location: Int)?
        for (account, phrases) in Self.accountRules {
            for phrase in phrases {
                let range = ns.range(of: phrase)
                guard range.location != NSNotFound else { continue }
                if best == nil
                    || range.location < best!.location
                    || (range.location == best!.location && phrase.count > best!.phrase.count) {
                    best = (account, phrase, range.location)
                }
            }
        }
        return (best?.account, best?.phrase)
    }

    // MARK: - Merchant / command

    private func detectConfirmation(in text: String) -> Bool {
        ["确认入账", "确认记账", "确认保存", "保存账单"].contains { text.contains($0) }
    }

    private func makeMerchant(
        normalized: String,
        datePhrases: [String],
        amountTexts: [String],
        accountPhrase: String?,
        confirmation: Bool
    ) -> String {
        var text = normalized
        let removals = Set(datePhrases + amountTexts).sorted { $0.count > $1.count }
        for phrase in removals {
            text = text.replacingOccurrences(of: phrase, with: " ")
        }

        if let accountPhrase {
            text = text.replacingOccurrences(of: "用\(accountPhrase)", with: " ")
            text = text.replacingOccurrences(of: accountPhrase, with: " ")
        }

        text = text.replacingOccurrences(
            of: #"[0-9零〇一二两三四五六七八九十百千万亿点]+(?:个|杯|斤|次|人|份|张|件|瓶|盒|包|公斤|公里|岁|天|周|小时|分钟|秒钟)"#,
            with: " ",
            options: .regularExpression
        )

        if confirmation {
            for phrase in ["确认入账", "确认记账", "确认保存", "保存账单"] {
                text = text.replacingOccurrences(of: phrase, with: " ")
            }
        }

        text = text.replacingOccurrences(
            of: #"[，。！？、；：,.!?;:（）()【】\[\]"“”‘’]"#,
            with: " ",
            options: .regularExpression
        )

        let fillers = [
            "帮我", "记一笔", "记账", "花了", "用了", "支付", "付了", "付款",
            "消费了", "消费", "买了", "收到", "到账", "进账", "转给", "转了",
            "请", "一共", "总共", "大概", "差不多", "的", "了", "是", "在", "给", "我"
        ]
        for filler in fillers.sorted(by: { $0.count > $1.count }) {
            text = text.replacingOccurrences(of: filler, with: "")
        }

        text = text.replacingOccurrences(of: #"[元块圆角毛分]"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["交", "充", "还"] where text.hasPrefix(prefix) {
            text.removeFirst()
        }
        if text.count > 16 {
            text = String(text.prefix(16))
        }
        return text
    }

    // MARK: - Utilities

    private func replacingAll(_ phrase: String, in text: String) -> String {
        guard !phrase.isEmpty else { return text }
        return text.replacingOccurrences(of: phrase, with: String(repeating: " ", count: phrase.count))
    }

    private func firstMatch(_ pattern: String, in text: String) -> (full: String, groups: [String])? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        var groups: [String] = []
        if match.numberOfRanges > 1 {
            for index in 1..<match.numberOfRanges {
                let range = match.range(at: index)
                groups.append(range.location == NSNotFound ? "" : ns.substring(with: range))
            }
        }
        return (ns.substring(with: match.range), groups)
    }
}
