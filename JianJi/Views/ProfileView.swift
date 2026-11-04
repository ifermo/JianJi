import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editsProfile = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("我的").font(.system(size: 20, weight: .medium))
                        Spacer()
                    }
                    .frame(height: 42)

                    Button { editsProfile = true } label: {
                        HStack(spacing: 14) {
                            Text(String(store.settings.userName.prefix(1)).uppercased())
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(Palette.primary)
                                .frame(width: 48, height: 48)
                                .background(Palette.mint)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.settings.userName)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(Palette.text)
                                Text("已坚持记账 \(store.recordingDays) 天")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Palette.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundStyle(Palette.tertiary)
                        }
                        .cardStyle()
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)

                    HStack(spacing: 10) {
                        ProfileStat(title: "累计账单", value: "\(store.transactions.count) 笔")
                        ProfileStat(title: "本月记账", value: "\(store.monthlyCount) 笔")
                    }
                    .padding(.vertical, 12)

                    SectionHeading(title: "偏好与管理").padding(.top, 8).padding(.bottom, 10)
                    SettingsGroup {
                        SettingsLink(title: "预算管理", value: "¥ \(Formatters.integer(store.settings.monthlyBudget)) / 月") {
                            BudgetSettingsView()
                        }
                        SettingsLink(title: "分类管理", value: "\(store.categories.count) 个分类") {
                            CategoryManagementView()
                        }
                        SettingsLink(title: "账单导出", value: "CSV、Excel") {
                            ExportSettingsView()
                        }
                        SettingsLink(title: "面容 ID 解锁", value: store.settings.faceIDEnabled ? "已开启" : "未开启") {
                            FaceIDSettingsView()
                        }
                    }

                    SectionHeading(title: "通用").padding(.top, 20).padding(.bottom, 10)
                    SettingsGroup {
                        SettingsLink(title: "iCloud 同步", value: syncStatus) {
                            SyncSettingsView()
                        }
                        SettingsLink(title: "外观", value: store.settings.appearance.title) {
                            AppearanceSettingsView()
                        }
                        SettingsLink(title: "关于简记", value: "版本 1.0") {
                            AboutView()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 102)
            }
            .background(Palette.background)
            .navigationBarHidden(true)
            .sheet(isPresented: $editsProfile) {
                ProfileEditorView()
                    .presentationDetents([.medium])
                    .presentationBackground(Palette.background)
            }
        }
    }

    private var syncStatus: String {
        if let date = store.settings.lastSyncDate {
            return Calendar.current.isDateInToday(date) ? "今日已同步" : "已同步"
        }
        return store.settings.iCloudSyncEnabled ? "待同步" : "未开启"
    }
}

private struct ProfileStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 15)).foregroundStyle(Palette.secondary)
            Text(value).font(.system(size: 19, weight: .medium)).foregroundStyle(Palette.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 14)
    }
}

struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 16)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.border, lineWidth: 0.5))
    }
}

struct SettingsLink<Destination: View>: View {
    let title: String
    let value: String
    @ViewBuilder let destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 12) {
                Text(title).font(.system(size: 16)).foregroundStyle(Palette.text)
                Spacer()
                Text(value).font(.system(size: 15)).foregroundStyle(Palette.tertiary).lineLimit(1)
            }
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 0.5) }
    }
}

private struct ProfileEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("个人资料") {
                    TextField("称呼", text: $name)
                        .textInputAutocapitalization(.never)
                    Text("称呼会显示在首页和个人资料卡中。")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("编辑资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            try store.updateUserName(name)
                            dismiss()
                        } catch {
                            self.error = "请输入 1–20 个字符的称呼"
                        }
                    }
                }
            }
            .onAppear { name = store.settings.userName }
            .alert("无法保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("知道了", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
}
