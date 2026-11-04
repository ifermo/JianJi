import SwiftUI

struct BudgetSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                ValidatedAmountField(title: "每月预算", text: $amount)
                    .font(.system(size: 24, weight: .medium))
            } header: {
                Text("日常预算")
            } footer: {
                Text("首页会根据本月支出计算可用金额与预算使用进度。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("预算管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
        }
        .onAppear { amount = Formatters.decimal(store.settings.monthlyBudget) }
        .alert("无法保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func save() {
        guard let value = Decimal(string: amount) else {
            error = LedgerError.invalidBudget.localizedDescription
            return
        }
        do {
            try store.updateBudget(value)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct CategoryManagementView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isAdding = false
    @State private var editing: LedgerCategory?
    @State private var deleting: LedgerCategory?
    @State private var error: String?

    var body: some View {
        List {
            ForEach(CategoryKind.allCases, id: \.self) { kind in
                Section(kind.title) {
                    ForEach(store.categories.filter { $0.kind == kind }) { category in
                        Button { editing = category } label: {
                            HStack(spacing: 12) {
                                CategoryIcon(symbol: category.symbol, size: 32)
                                Text(category.name).foregroundStyle(Palette.text)
                                Spacer()
                                if category.id == LedgerCategory.expenseFallbackID || category.id == LedgerCategory.incomeFallbackID {
                                    Text("默认").font(.system(size: 14)).foregroundStyle(Palette.tertiary)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if category.id != LedgerCategory.expenseFallbackID && category.id != LedgerCategory.incomeFallbackID {
                                Button("删除", role: .destructive) { deleting = category }
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("分类管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("新增") { isAdding = true } } }
        .sheet(isPresented: $isAdding) {
            CategoryEditorView(category: nil)
                .presentationDetents([.medium])
                .presentationBackground(Palette.background)
        }
        .sheet(item: $editing) { category in
            CategoryEditorView(category: category)
                .presentationDetents([.medium])
                .presentationBackground(Palette.background)
        }
        .alert("删除分类？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("删除", role: .destructive) {
                guard let category = deleting else { return }
                do { try store.deleteCategory(id: category.id) } catch { self.error = error.localizedDescription }
                deleting = nil
            }
        } message: {
            Text("该分类下的账单会移入“其他”分类。")
        }
        .alert("无法删除", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: { Text(error ?? "") }
    }
}

private struct CategoryEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let category: LedgerCategory?
    @State private var name = ""
    @State private var kind: CategoryKind = .expense
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("分类信息") {
                    TextField("分类名称（最多 8 字）", text: $name)
                    if category == nil {
                        Picker("类型", selection: $kind) {
                            Text("支出").tag(CategoryKind.expense)
                            Text("收入").tag(CategoryKind.income)
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle(category == nil ? "新增分类" : "重命名分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .onAppear {
                name = category?.name ?? ""
                kind = category?.kind ?? .expense
            }
            .alert("无法保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("知道了", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private func save() {
        do {
            if let category {
                try store.renameCategory(id: category.id, to: name)
            } else {
                _ = try store.addCategory(name: name, kind: kind)
            }
            dismiss()
        } catch {
            self.error = "请输入 1–8 个字符，且同类型下名称不能重复"
        }
    }
}

struct ExportSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var format: ExportFormat = .csv
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var fileURL: URL?
    @State private var error: String?

    var body: some View {
        Form {
            Section("导出范围") {
                DatePicker("开始日期", selection: $startDate, in: ...endDate, displayedComponents: .date)
                DatePicker("结束日期", selection: $endDate, in: startDate..., displayedComponents: .date)
                Picker("文件格式", selection: $format) {
                    ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button("生成导出文件", action: generate)
                    .frame(maxWidth: .infinity)
                if let fileURL {
                    ShareLink(item: fileURL) {
                        Label("分享导出文件", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                }
            } footer: {
                Text("CSV 带 UTF-8 标记，Excel XML 可直接用 Excel 或 Numbers 打开。金额按正数导出，收支方向见“类型”列。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("账单导出")
        .navigationBarTitleDisplayMode(.inline)
        .alert("导出失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func generate() {
        do {
            let transactions = store.filteredTransactions(startDate: startDate, endDate: endDate)
            fileURL = try ExportService().makeFile(transactions: transactions, categories: store.categories, format: format)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct FaceIDSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isAuthenticating = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Toggle("面容 ID 解锁", isOn: Binding(
                    get: { store.settings.faceIDEnabled },
                    set: { enabled in authenticate(enabled: enabled) }
                ))
                .disabled(isAuthenticating)
            } footer: {
                Text("开启后，简记进入后台再回到前台时会要求验证。生物信息由系统管理，简记无法读取。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("面容 ID")
        .navigationBarTitleDisplayMode(.inline)
        .alert("面容 ID 设置失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func authenticate(enabled: Bool) {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        Task {
            let success = await BiometricAuthService().authenticate(reason: enabled ? "开启简记面容 ID 解锁" : "关闭简记面容 ID 解锁")
            await MainActor.run {
                isAuthenticating = false
                if success {
                    store.updateFaceID(enabled)
                } else {
                    error = "请确认设备支持并已设置面容 ID，且未取消系统验证。"
                }
            }
        }
    }
}

struct SyncSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isSyncing = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Toggle("iCloud 同步", isOn: Binding(
                    get: { store.settings.iCloudSyncEnabled },
                    set: { enabled in
                        if enabled {
                            store.updateICloud(true)
                            sync()
                        } else {
                            store.updateICloud(false)
                        }
                    }
                ))
                .disabled(isSyncing)
                Button(action: sync) {
                    HStack {
                        Text(isSyncing ? "正在同步…" : "立即同步")
                        if isSyncing { ProgressView() }
                    }
                }
                .disabled(isSyncing || !store.settings.iCloudSyncEnabled)
            } footer: {
                Text("账单仅上传到你的 iCloud 私有数据库。同步会合并各设备的修改与删除记录；本地账单始终保留。")
            }

            if let date = store.settings.lastSyncDate {
                Section("状态") {
                    LabeledContent("上次同步", value: date.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("iCloud 同步")
        .navigationBarTitleDisplayMode(.inline)
        .alert("同步失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func sync() {
        guard !isSyncing else { return }
        isSyncing = true
        Task {
            do {
                let merged = try await CloudKitSyncService().sync(local: store.snapshot)
                await MainActor.run {
                    store.replaceForSync(merged)
                    isSyncing = false
                    store.toast("iCloud 同步完成")
                }
            } catch {
                await MainActor.run {
                    isSyncing = false
                    self.error = "\(error.localizedDescription)\n请确认已登录 iCloud，并在开发者账号中配置 iCloud 容器。"
                }
            }
        }
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        List {
            ForEach(AppearanceOption.allCases) { appearance in
                Button { store.updateAppearance(appearance) } label: {
                    HStack {
                        Text(appearance.title).foregroundStyle(Palette.text)
                        Spacer()
                        if store.settings.appearance == appearance {
                            Image(systemName: "checkmark").foregroundStyle(Palette.primary)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(Palette.primary)
                            .frame(width: 72, height: 72)
                            .background(Palette.hero)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        Text("简记").font(.system(size: 20, weight: .medium))
                        Text("版本 1.0.0").font(.system(size: 15)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 20)
            }
            Section("说明") {
                LabeledContent("数据存储", value: "本地优先")
                LabeledContent("隐私", value: "不收集个人信息")
                LabeledContent("技术", value: "原生 SwiftUI")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("关于简记")
        .navigationBarTitleDisplayMode(.inline)
    }
}
