import SwiftUI

struct AddTransactionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var type: TransactionType = .expense
    @State private var categoryID = "food"
    @State private var calculator = CalculatorEngine()
    @State private var error: String?
    @State private var sourceAccount = "银行卡"
    @State private var destinationAccount = "现金"

    private let accounts = ["现金", "银行卡", "支付宝", "微信"]

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Palette.secondary.opacity(0.35))
                .frame(width: 36, height: 4)
                .padding(.top, 9)
                .padding(.bottom, 9)

            HStack {
                Text("记一笔").font(.system(size: 19, weight: .medium))
                Spacer()
                Button("完成") { dismiss() }
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.primary)
            }

            Picker("账单类型", selection: $type) {
                ForEach(TransactionType.allCases) { type in Text(type.title).tag(type) }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 9)
            .onChange(of: type) { _, newType in
                categoryID = store.categories(for: newType).first?.id ?? LedgerCategory.transferID
                error = nil
            }

            Text(error ?? calculator.formula)
                .font(.system(size: 14))
                .foregroundStyle(error == nil ? Palette.secondary : Palette.danger)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 18)
                .frame(maxWidth: .infinity)

            Text("¥ \(calculator.display)")
                .font(.system(size: 32, weight: .medium))
                .tracking(-1)
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.categories(for: type)) { category in
                        Button {
                            categoryID = category.id
                        } label: {
                            Text(category.name)
                                .font(.system(size: 15))
                                .foregroundStyle(categoryID == category.id ? Palette.onPrimary : Palette.secondary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(categoryID == category.id ? Palette.primary : Palette.soft)
                                .clipShape(Capsule())
                        }
                        .accessibilityAddTraits(categoryID == category.id ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }

            if type == .transfer {
                HStack(spacing: 10) {
                    accountPicker(title: "转出", selection: $sourceAccount)
                    Image(systemName: "arrow.right").foregroundStyle(Palette.secondary)
                    accountPicker(title: "转入", selection: $destinationAccount)
                }
                .padding(.top, 9)
            }

            Spacer(minLength: 8)
            keypad
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .background(Palette.background)
    }

    private var keypad: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                key("AC", style: .utility) { calculator.clear(); error = nil }
                key("<-", style: .utility) { calculator.backspace(); error = nil }
                operatorKey("÷", .divide)
                operatorKey("×", .multiply)
            }
            HStack(spacing: 7) {
                numberKey("1"); numberKey("2"); numberKey("3")
                operatorKey("−", .subtract)
            }
            HStack(spacing: 7) {
                numberKey("4"); numberKey("5"); numberKey("6")
                operatorKey("+", .add)
            }
            GeometryReader { geometry in
                let keyWidth = (geometry.size.width - 21) / 4
                HStack(spacing: 7) {
                    VStack(spacing: 7) {
                        HStack(spacing: 7) { numberKey("7"); numberKey("8"); numberKey("9") }
                        HStack(spacing: 7) { numberKey("."); numberKey("0"); equalsKey }
                    }
                    .frame(width: keyWidth * 3 + 14)
                    Button(action: save) {
                        Text("保存账单")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Palette.onPrimary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Palette.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .frame(width: keyWidth, height: 95)
                }
            }
            .frame(height: 95)
        }
    }

    private var equalsKey: some View {
        Button {
            calculate()
        } label: {
            Text("=")
                .font(.system(size: 20))
                .foregroundStyle(Palette.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Palette.mint)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }

    private func numberKey(_ value: String) -> some View {
        key(value) {
            calculator.input(value)
            error = nil
        }
    }

    private func operatorKey(_ symbol: String, _ operation: CalculatorEngine.Operator) -> some View {
        key(symbol, style: .operation) {
            calculator.append(operation)
            error = nil
        }
    }

    private enum KeyStyle { case normal, operation, utility }

    private func key(_ title: String, style: KeyStyle = .normal, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: style == .operation ? 20 : (style == .utility ? 12 : 16)))
                .foregroundStyle(style == .normal ? Palette.text : Palette.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(style == .normal ? Palette.card : (style == .operation ? Palette.mint : Palette.soft))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func accountPicker(title: String, selection: Binding<String>) -> some View {
        Menu {
            ForEach(accounts, id: \.self) { account in
                Button(account) { selection.wrappedValue = account }
            }
        } label: {
            HStack {
                Text(title).font(.system(size: 14)).foregroundStyle(Palette.secondary)
                Text(selection.wrappedValue).font(.system(size: 15, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 13))
            }
            .foregroundStyle(Palette.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func calculate() {
        do {
            _ = try calculator.evaluate()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() {
        do {
            let amount = try calculator.evaluate()
            guard amount > 0 else { throw LedgerError.invalidAmount }
            let category = store.category(id: categoryID)
            let merchant: String
            switch type {
            case .expense: merchant = "\(category?.name ?? "其他")消费"
            case .income: merchant = "\(category?.name ?? "其他")收入"
            case .transfer: merchant = "账户转账"
            }
            let transaction = LedgerTransaction(
                type: type,
                amount: amount,
                categoryID: type == .transfer ? LedgerCategory.transferID : categoryID,
                merchant: merchant,
                sourceAccount: type == .transfer ? sourceAccount : nil,
                destinationAccount: type == .transfer ? destinationAccount : nil
            )
            try store.add(transaction)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
