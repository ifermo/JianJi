import SwiftUI

struct VoiceConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss

    let draft: VoiceDraft
    let categories: [LedgerCategory]
    let accounts: [String]
    let defaultAccount: String?
    let onSave: (LedgerTransaction) throws -> Void
    let onRetry: () -> Void
    let onUseKeyboard: () -> Void

    @State private var type: TransactionType
    @State private var amountText: String
    @State private var categoryID: String
    @State private var date: Date
    @State private var account: String
    @State private var merchant: String
    @State private var note: String
    @State private var error: String?
    @State private var isSaving = false
    @FocusState private var amountFocused: Bool

    init(
        draft: VoiceDraft,
        categories: [LedgerCategory],
        accounts: [String],
        defaultAccount: String?,
        onSave: @escaping (LedgerTransaction) throws -> Void,
        onRetry: @escaping () -> Void,
        onUseKeyboard: @escaping () -> Void
    ) {
        self.draft = draft
        self.categories = categories
        self.accounts = accounts
        self.defaultAccount = defaultAccount
        self.onSave = onSave
        self.onRetry = onRetry
        self.onUseKeyboard = onUseKeyboard

        let initialType: TransactionType = draft.type == .income ? .income : .expense
        let options = categories.filter { $0.kind == (initialType == .income ? .income : .expense) }
        let initialCategory = draft.categoryID.flatMap { id in
            options.contains(where: { $0.id == id }) ? id : nil
        } ?? options.first?.id ?? ""

        _type = State(initialValue: initialType)
        _amountText = State(initialValue: draft.amount.map(Formatters.number) ?? "")
        _categoryID = State(initialValue: initialCategory)
        _date = State(initialValue: draft.date)
        let suggestedAccount = draft.account ?? defaultAccount ?? ""
        _account = State(initialValue: accounts.contains(suggestedAccount) ? suggestedAccount : "")
        _merchant = State(initialValue: draft.merchant)
        _note = State(initialValue: draft.note)
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Palette.secondary.opacity(0.35))
                .frame(width: 36, height: 4)
                .padding(.top, 9)
                .padding(.bottom, 8)

            header

            if draft.type == .transfer {
                transferContent
            } else {
                formContent
            }
        }
        .background(Palette.background)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Palette.background)
        .onAppear {
            if draft.amount == nil {
                amountFocused = true
            }
        }
    }

    private var header: some View {
        HStack {
            Button("取消") { dismiss() }
                .font(.system(size: 15))
                .foregroundStyle(Palette.text)
            Spacer()
            Text("账单确认")
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            Button("改用键盘") { useKeyboard() }
                .font(.system(size: 15))
                .foregroundStyle(Palette.primary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var transferContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Palette.tertiary)
            Text("语音转账暂不支持")
                .font(.system(size: 18, weight: .semibold))
            Text("请使用键盘输入转账信息")
                .font(.system(size: 15))
                .foregroundStyle(Palette.secondary)
            HStack(spacing: 10) {
                secondaryButton("重新说", action: retry)
                primaryButton("改用键盘", action: useKeyboard)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var formContent: some View {
        ScrollView {
            VStack(spacing: 14) {
                transcriptCard
                billCard
                warnings
                actions
                if let error {
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("识别内容")
                .font(.system(size: 14))
                .foregroundStyle(Palette.secondary)
            Text(draft.note)
                .font(.system(size: 15))
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.border, lineWidth: 0.5)
        )
    }

    private var billCard: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Picker("类型", selection: $type) {
                    Text("支出").tag(TransactionType.expense)
                    Text("收入").tag(TransactionType.income)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 2)

                HStack(alignment: .center, spacing: 6) {
                    Text("¥")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                    TextField("0.00", text: $amountText)
                        .font(.system(size: 32, weight: .medium))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .focused($amountFocused)
                        .onChange(of: amountText) { _, newValue in
                            let filtered = Self.filterAmount(newValue)
                            if filtered != newValue { amountText = filtered }
                        }
                }
            }
            .padding(.bottom, 10)

            infoRow("分类") {
                Menu {
                    ForEach(availableCategories) { category in
                        Button(category.name) { categoryID = category.id }
                    }
                } label: {
                    menuValue(availableCategories.first(where: { $0.id == categoryID })?.name ?? "未选择")
                }
            }

            infoRow("日期") {
                DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "zh_CN"))
            }

            infoRow("账户") {
                Menu {
                    Button("未指定") { account = "" }
                    ForEach(accounts, id: \.self) { name in
                        Button(name) { account = name }
                    }
                } label: {
                    menuValue(account.isEmpty ? "未指定" : account)
                }
            }

            infoRow("商户") {
                TextField("商户", text: $merchant)
                    .font(.system(size: 15))
                    .multilineTextAlignment(.trailing)
            }

            infoRow("备注") {
                TextField("备注", text: $note, axis: .vertical)
                    .font(.system(size: 15))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1...3)
            }
        }
        .padding(14)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Palette.border, lineWidth: 0.5)
        )
        .onChange(of: type) { _, newType in
            let options = categories.filter { $0.kind == (newType == .income ? .income : .expense) }
            if !options.contains(where: { $0.id == categoryID }) {
                categoryID = options.first?.id ?? ""
            }
        }
    }

    @ViewBuilder
    private var warnings: some View {
        if !draft.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(draft.warnings, id: \.rawValue) { warning in
                    Label(warning.message, systemImage: "exclamationmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.danger)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            secondaryButton("重新说", action: retry)
            primaryButton("确认入账", action: save)
        }
        .padding(.top, 2)
    }

    private func infoRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(Palette.secondary)
            Spacer(minLength: 12)
            content()
        }
        .frame(minHeight: 39)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.border).frame(height: 0.5)
        }
    }

    private func menuValue(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Palette.text)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11))
                .foregroundStyle(Palette.tertiary)
        }
    }

    private var availableCategories: [LedgerCategory] {
        let kind: CategoryKind = type == .income ? .income : .expense
        return categories.filter { $0.kind == kind }
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Palette.soft)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Palette.onPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Palette.primary)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    private func save() {
        guard !isSaving else { return }
        let normalizedAmount = amountText.replacingOccurrences(of: ",", with: "")
        guard let amount = Decimal(string: normalizedAmount), amount > 0 else {
            error = "请输入大于 0 的有效金额"
            return
        }
        guard !categoryID.isEmpty else {
            error = "请选择分类"
            return
        }

        isSaving = true
        error = nil
        let merchantName = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let transaction = LedgerTransaction(
            type: type,
            amount: Formatters.rounded(amount),
            categoryID: categoryID,
            merchant: merchantName.isEmpty ? (availableCategories.first(where: { $0.id == categoryID })?.name ?? "账单") : merchantName,
            note: note,
            date: date,
            sourceAccount: account.isEmpty ? nil : account
        )
        do {
            try onSave(transaction)
            dismiss()
        } catch {
            isSaving = false
            self.error = error.localizedDescription
        }
    }

    private func retry() {
        onRetry()
        dismiss()
    }

    private func useKeyboard() {
        onUseKeyboard()
        dismiss()
    }

    private static func filterAmount(_ text: String) -> String {
        var result = ""
        var hasDot = false
        var decimals = 0
        for character in text {
            if character == "." {
                if hasDot { continue }
                hasDot = true
                result.append(character)
            } else if character.isNumber {
                if hasDot {
                    decimals += 1
                    if decimals > 2 { continue }
                }
                result.append(character)
            }
        }
        return result
    }
}

#if DEBUG
struct VoiceConfirmPreviewView: View {
    @State private var show = true

    private let draft = VoiceDraft(
        type: .expense,
        amount: 42,
        categoryID: "food",
        date: Date(),
        account: "微信",
        merchant: "午饭",
        note: "昨天午饭花了四十二元，用微信支付",
        warnings: [],
        highlights: ["四十二元", "昨天", "午饭", "微信支付"],
        confirmationRequested: false
    )

    var body: some View {
        Palette.background.ignoresSafeArea()
            .sheet(isPresented: $show) {
                VoiceConfirmSheet(
                    draft: draft,
                    categories: LedgerCategory.defaults,
                    accounts: LedgerAccounts.all,
                    defaultAccount: "微信",
                    onSave: { _ in },
                    onRetry: {},
                    onUseKeyboard: {}
                )
            }
    }
}
#endif
