import Foundation

enum ChineseNumberParser {
    private static let unitValues: [Character: Decimal] = [
        "十": 10, "拾": 10,
        "百": 100, "佰": 100,
        "千": 1000, "仟": 1000,
        "万": 10_000, "萬": 10_000,
        "亿": 100_000_000, "億": 100_000_000
    ]

    private static let currencyCharacters = "元块圆角毛分"

    static func normalize(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            if let scalar = character.unicodeScalars.first,
               (0xFF10...0xFF19).contains(scalar.value) {
                result.append(Character(String(scalar.value - 0xFF10)))
                continue
            }
            switch character {
            case "點": result.append("点")
            case "圓": result.append("元")
            case "塊": result.append("块")
            case "兩": result.append("两")
            case "萬": result.append("万")
            case "億": result.append("亿")
            case "拾": result.append("十")
            case "佰": result.append("百")
            case "仟": result.append("千")
            default: result.append(character)
            }
        }
        return result
    }

    static func isNumberCharacter(_ character: Character) -> Bool {
        digitValue(character) != nil
            || unitValues[character] != nil
            || character == "点"
            || character == "半"
            || character == "."
    }

    static func isCurrencyCharacter(_ character: Character) -> Bool {
        currencyCharacters.contains(character)
    }

    static func parseNumber(_ text: String) -> Decimal? {
        let normalized = normalize(text)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        if normalized == "半" { return Decimal(string: "0.5") }

        if normalized.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) {
            return Decimal(string: normalized)
        }

        var integerText = normalized
        var fractionText = ""
        if let dot = normalized.firstIndex(of: "点") {
            integerText = String(normalized[..<dot])
            fractionText = String(normalized[normalized.index(after: dot)...])
        }

        guard let integer = parseChineseInteger(integerText) else { return nil }
        var value = integer
        if !fractionText.isEmpty {
            var fraction = Decimal(0)
            var divisor = Decimal(10)
            for character in fractionText {
                guard let digit = digitValue(character) else { return nil }
                fraction += Decimal(digit) / divisor
                divisor *= 10
            }
            value += fraction
        }
        return value
    }

    static func parseAmountToken(_ text: String) -> Decimal? {
        let normalized = normalize(text)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        guard normalized.contains(where: { currencyCharacters.contains($0) }) else {
            return parseNumber(normalized)
        }

        let yuanUnits: [Character] = ["元", "块", "圆"]
        if let yuanIndex = normalized.firstIndex(where: { yuanUnits.contains($0) }) {
            let integerText = String(normalized[..<yuanIndex])
            let remainder = String(normalized[normalized.index(after: yuanIndex)...])
            let integer: Decimal
            if integerText.isEmpty {
                integer = 0
            } else if let parsed = parseNumber(integerText) {
                integer = parsed
            } else {
                return nil
            }
            guard let fraction = parseFraction(remainder) else { return nil }
            return integer + fraction
        }

        return parseFraction(normalized)
    }

    private static func parseFraction(_ text: String) -> Decimal? {
        guard !text.isEmpty else { return 0 }
        if text == "半" { return Decimal(string: "0.5") }

        if let maoIndex = text.firstIndex(where: { $0 == "角" || $0 == "毛" }) {
            let before = String(text[..<maoIndex])
            let after = String(text[text.index(after: maoIndex)...])
            let jiao = before.isEmpty ? 0 : (parseNumber(before) ?? 0)
            var fen: Decimal = 0
            if let fenIndex = after.firstIndex(of: "分") {
                let cents = String(after[..<fenIndex])
                fen = cents.isEmpty ? 0 : (parseNumber(cents) ?? 0)
            } else if !after.isEmpty, let parsed = parseNumber(after) {
                fen = parsed
            }
            return (jiao / 10) + (fen / 100)
        }

        if let fenIndex = text.firstIndex(of: "分") {
            let cents = String(text[..<fenIndex])
            guard !cents.isEmpty, let value = parseNumber(cents) else { return 0 }
            return value / 100
        }

        guard let value = parseNumber(text) else { return 0 }
        let looksLikeCents = text.hasPrefix("零") || text.count > 1
        return looksLikeCents ? value / 100 : value / 10
    }

    private static func parseChineseInteger(_ text: String) -> Decimal? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return 0 }

        var total = Decimal(0)
        var section = Decimal(0)
        var number = Decimal(0)
        var lastUnit = Decimal(1)
        var zeroSinceLastUnit = false
        var hasDigit = false

        for character in text {
            if let digit = digitValue(character) {
                hasDigit = true
                if digit == 0 {
                    number = 0
                    zeroSinceLastUnit = true
                } else {
                    number = Decimal(digit)
                }
                continue
            }

            guard let unit = unitValues[character] else { return nil }
            hasDigit = true
            if number == 0 { number = 1 }

            if unit >= 10_000 {
                section += number
                section *= unit
                total += section
                section = 0
            } else {
                section += number * unit
            }
            number = 0
            lastUnit = unit
            zeroSinceLastUnit = false
        }

        if number != 0 {
            if zeroSinceLastUnit || lastUnit < 100 {
                section += number
            } else {
                section += number * (lastUnit / 10)
            }
        }
        total += section
        return hasDigit ? total : nil
    }

    private static func digitValue(_ character: Character) -> Int? {
        switch character {
        case "零", "〇", "○": return 0
        case "一", "壹": return 1
        case "二", "贰", "两", "兩": return 2
        case "三", "叁": return 3
        case "四", "肆": return 4
        case "五", "伍": return 5
        case "六", "陆": return 6
        case "七", "柒": return 7
        case "八", "捌": return 8
        case "九", "玖": return 9
        default:
            guard character.isASCII, let value = character.wholeNumberValue, (0...9).contains(value) else {
                return nil
            }
            return value
        }
    }
}
