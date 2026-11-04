import SwiftUI

struct TransactionDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let transactionID: UUID
    @State private var draft: LedgerTransaction?
    @State private var amountText = ""
    @State private var showsDeleteAlert = false
    @State private var error: String?

    private let accounts = ["现金", "银行卡", "支付宝", "微信"]

    var body: some View {
        Group {
            if let transaction = draft {
                editor(transaction)
            } else {
                ContentUnavailableView("账单不存在", systemImage: "doc.questionmark", description: Text("这笔账单可能已被删除"))
            }
        }
        .navigationTitle("账单详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save).disabled(draft == nil)
            }
        }
        .onAppear(perform: load)
        .alert("删除账单？", isPresented: $showsDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                store.delete(id: transactionID)
                dismiss()
            }
        } message: {
            Text("删除后将同步更新首页与统计，且无法撤销。")
        }
        .alert("无法保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func editor(_ transaction: LedgerTransaction) -> some View {
        Form {
            summarySection(transaction)
            detailsSection(transaction)
            noteSection
            Section {
                Button("删除这笔账单", role: .destructive) { showsDeleteAlert = true }
                    .frame(maxWidth: .infinity)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
    }

    private func summarySection(_ transaction: LedgerTransaction) -> some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    CategoryIcon(symbol: store.category(for: transaction)?.symbol ?? "tag", size: 46)
                    Text(transaction.type.title)
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
            }
            .listRowBackground(Palette.card)
        }
    }

    @ViewBuilder
    private func detailsSection(_ transaction: LedgerTransaction) -> some View {
        Section("账单信息") {
            Picker("类型", selection: typeBinding) {
                ForEach(TransactionType.allCases) { type in Text(type.title).tag(type) }
            }
            ValidatedAmountField(title: "金额", text: $amountText)
            TextField("商户或名称", text: textBinding(\.merchant))
            DatePicker("日期", selection: fieldBinding(\.date, fallback: Date()))
            if transaction.type != .transfer {
                categoryPicker(transaction)
            } else {
                accountPickers
            }
        }
    }

    private func categoryPicker(_ transaction: LedgerTransaction) -> some View {
        Picker("分类", selection: textBinding(\.categoryID)) {
            ForEach(store.categories(for: transaction.type)) { category in
                Label(category.name, systemImage: category.symbol).tag(category.id)
            }
        }
    }

    private var accountPickers: some View {
        Group {
            Picker("转出账户", selection: accountBinding(\.sourceAccount, fallback: "银行卡")) {
                ForEach(accounts, id: \.self) { Text($0).tag($0) }
            }
            Picker("转入账户", selection: accountBinding(\.destinationAccount, fallback: "现金")) {
                ForEach(accounts, id: \.self) { Text($0).tag($0) }
            }
        }
    }

    private var noteSection: some View {
        Section("备注") {
            TextField("添加备注（可选）", text: textBinding(\.note), axis: .vertical)
                .lineLimit(2...5)
        }
    }

    private var typeBinding: Binding<TransactionType> {
        Binding(
            get: { draft?.type ?? .expense },
            set: { newType in
                update { $0.type = newType }
                normalizeCategory(for: newType)
            }
        )
    }

    private func fieldBinding<Value>(_ keyPath: WritableKeyPath<LedgerTransaction, Value>, fallback: Value) -> Binding<Value> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? fallback },
            set: { newValue in update { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func textBinding(_ keyPath: WritableKeyPath<LedgerTransaction, String>) -> Binding<String> {
        fieldBinding(keyPath, fallback: "")
    }

    private func accountBinding(_ keyPath: WritableKeyPath<LedgerTransaction, String?>, fallback: String) -> Binding<String> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? fallback },
            set: { newValue in update { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func load() {
        guard draft == nil, let transaction = store.transactions.first(where: { $0.id == transactionID }) else { return }
        draft = transaction
        amountText = Formatters.decimal(transaction.amount)
    }

    private func update(_ change: (inout LedgerTransaction) -> Void) {
        guard var value = draft else { return }
        change(&value)
        draft = value
    }

    private func normalizeCategory(for type: TransactionType) {
        guard var value = draft else { return }
        if type == .transfer {
            value.categoryID = LedgerCategory.transferID
            value.sourceAccount = value.sourceAccount ?? "银行卡"
            value.destinationAccount = value.destinationAccount ?? "现金"
        } else {
            value.categoryID = store.categories(for: type).first?.id ?? LedgerCategory.expenseFallbackID
            value.sourceAccount = nil
            value.destinationAccount = nil
        }
        draft = value
    }

    private func save() {
        guard var value = draft, let amount = Decimal(string: amountText) else {
            error = LedgerError.invalidAmount.localizedDescription
            return
        }
        value.amount = amount
        value.merchant = value.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.merchant.isEmpty {
            value.merchant = store.category(for: value)?.name ?? "账单"
        }
        do {
            try store.update(value)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
