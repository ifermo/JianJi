import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light))
        })
    }
}

enum Palette {
    static let background = Color.adaptive(light: 0xF7F8F5, dark: 0x151714)
    static let card = Color.adaptive(light: 0xFFFFFF, dark: 0x20231F)
    static let primary = Color.adaptive(light: 0x245B49, dark: 0x9FC7AF)
    static let hero = Color.adaptive(light: 0xE8F0EA, dark: 0x24352C)
    static let text = Color.adaptive(light: 0x20231F, dark: 0xF0F2ED)
    static let secondary = Color.adaptive(light: 0x777D75, dark: 0xA5ACA2)
    static let tertiary = Color.adaptive(light: 0x92978F, dark: 0x858C82)
    static let border = Color.adaptive(light: 0xE2E5DF, dark: 0x373C35)
    static let soft = Color.adaptive(light: 0xEDEFEA, dark: 0x2C302B)
    static let field = Color.adaptive(light: 0xEBEDE8, dark: 0x292D27)
    static let mint = Color.adaptive(light: 0xDDE6DE, dark: 0x385044)
    static let income = Color.adaptive(light: 0x245B49, dark: 0x9FC7AF)
    static let onPrimary = Color.adaptive(light: 0xFFFFFF, dark: 0x15231C)
    static let danger = Color.adaptive(light: 0xA5433D, dark: 0xF09B94)
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Palette.border, lineWidth: 0.5)
            )
    }
}

extension View {
    func cardStyle(padding: CGFloat = 16) -> some View {
        modifier(CardStyle(padding: padding))
    }
}

struct CategoryIcon: View {
    let symbol: String
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(Palette.text)
            .frame(width: size, height: size)
            .background(Palette.soft)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.315, style: .continuous))
    }
}

struct SectionHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Palette.text)
    }
}

struct TransactionRow: View {
    let transaction: LedgerTransaction
    let category: LedgerCategory?
    var showsDate = false

    private var meta: String {
        var date = ""
        if showsDate {
            if Calendar.current.isDateInToday(transaction.date) {
                date = "今天 "
            } else if Calendar.current.isDateInYesterday(transaction.date) {
                date = "昨天 "
            } else {
                date = "\(transaction.date.shortDayTitle) "
            }
        }
        if transaction.type == .transfer {
            return "\(date)\(transaction.date.timeTitle) · \(transaction.sourceAccount ?? "账户") → \(transaction.destinationAccount ?? "账户")"
        }
        return "\(date)\(transaction.date.timeTitle) · \(category?.name ?? "未分类")"
    }

    private var amountPrefix: String {
        switch transaction.type {
        case .expense: "−"
        case .income: "+"
        case .transfer: ""
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(symbol: category?.symbol ?? "arrow.left.arrow.right")
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.merchant)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text(meta)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(Formatters.money(transaction.amount, sign: amountPrefix))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(transaction.type == .income ? Palette.income : Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}

struct EmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
            Text(title)
                .font(.system(size: 17, weight: .medium))
            Text(message)
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Palette.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

struct ValidatedAmountField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(.decimalPad)
            .onChange(of: text) { _, newValue in
                let filtered = newValue.filter { "0123456789.".contains($0) }
                var result = ""
                var hasDot = false
                var decimals = 0
                for character in filtered {
                    if character == "." {
                        if hasDot { continue }
                        hasDot = true
                        result.append(character)
                    } else {
                        if hasDot { decimals += 1 }
                        if decimals <= 2 { result.append(character) }
                    }
                }
                if result != newValue { text = result }
            }
    }
}
