import SwiftUI

enum AppTab: Hashable {
    case home
    case statistics
    case bills
    case profile
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedTab: AppTab = .home
    @State private var isAdding = false
    @StateObject private var voice = VoiceEntryModel()
    #if DEBUG
    @State private var isDemoOverlay = false
    @State private var isDemoConfirm = false
    #endif

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.background.ignoresSafeArea()
            TabView(selection: $selectedTab) {
                HomeView(showAllBills: { selectedTab = .bills }).tag(AppTab.home)
                StatisticsView().tag(AppTab.statistics)
                BillsView().tag(AppTab.bills)
                ProfileView().tag(AppTab.profile)
            }
            .toolbar(.hidden, for: .tabBar)
            .background(Palette.background)

            CustomTabBar(selection: $selectedTab, voice: voice)
        }
        .tint(Palette.primary)
        .onAppear(perform: prepareVoiceEntry)
        .onChange(of: store.categories) { _, categories in
            voice.configure(categories: categories, accounts: LedgerAccounts.all)
        }
        .sheet(isPresented: $isAdding) {
            AddTransactionView()
                .environmentObject(store)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Palette.background)
        }
        .sheet(isPresented: reviewPresented) {
            reviewContent
        }
        .overlay {
            #if DEBUG
            if isDemoOverlay {
                VoiceCaptureOverlay(state: Self.demoOverlayState)
            } else if voice.overlayVisible {
                liveVoiceOverlay
            }
            #else
            if voice.overlayVisible {
                liveVoiceOverlay
            }
            #endif
        }
        .animation(.easeOut(duration: 0.18), value: voice.overlayVisible)
        .overlay(alignment: .bottom) {
            if let message = store.toastMessage {
                Text(message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(hex: 0x20231F))
                    .clipShape(Capsule())
                    .padding(.bottom, 94)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityLabel(message)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.toastMessage)
        .alert("提示", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private func prepareVoiceEntry() {
        voice.onManual = { isAdding = true }
        voice.configure(categories: store.categories, accounts: LedgerAccounts.all)
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        isDemoOverlay = arguments.contains("-VoiceDemoOverlay")
        isDemoConfirm = arguments.contains("-VoiceDemoConfirm")
        #endif
    }

    // MARK: - 语音确认单

    private var liveVoiceOverlay: some View {
        VoiceCaptureOverlay(
            state: voice.overlayState,
            onFinish: { voice.pressEnded() },
            onCancel: { voice.cancel() }
        )
    }

    private var reviewPresented: Binding<Bool> {
        Binding(
            get: {
                #if DEBUG
                if isDemoConfirm { return true }
                #endif
                return voice.phase == .reviewing && voice.draft != nil
            },
            set: { presented in
                guard !presented else { return }
                #if DEBUG
                isDemoConfirm = false
                #endif
                voice.reset()
            }
        )
    }

    @ViewBuilder private var reviewContent: some View {
        #if DEBUG
        if isDemoConfirm {
            VoiceConfirmSheet(
                draft: Self.demoDraft,
                categories: store.categories,
                accounts: LedgerAccounts.all,
                defaultAccount: "微信",
                onSave: { _ in isDemoConfirm = false },
                onRetry: { isDemoConfirm = false },
                onUseKeyboard: { isDemoConfirm = false }
            )
        } else {
            liveReviewContent
        }
        #else
        liveReviewContent
        #endif
    }

    @ViewBuilder private var liveReviewContent: some View {
        if let draft = voice.draft {
            VoiceConfirmSheet(
                draft: draft,
                categories: store.categories,
                accounts: LedgerAccounts.all,
                defaultAccount: draft.account,
                onSave: { transaction in
                    try store.add(transaction)
                    voice.reset()
                },
                onRetry: { voice.reset() },
                onUseKeyboard: {
                    voice.reset()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        isAdding = true
                    }
                }
            )
        }
    }

    #if DEBUG
    /// UI 测试截图夹具:不经过麦克风直接呈现语音链路的关键界面。
    private static let demoOverlayState = VoiceOverlayState(
        phase: .listening,
        transcript: "昨天午饭花了四十二元,用微信支付的",
        level: 0.72,
        elapsed: 4.2,
        cancelArmed: false,
        isHandsFree: false
    )

    private static let demoDraft = VoiceDraft(
        type: .expense,
        amount: 42,
        categoryID: "food",
        date: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(),
        account: "微信",
        merchant: "午饭",
        note: "昨天午饭花了四十二元,用微信支付的",
        warnings: [],
        highlights: ["四十二元", "昨天", "午饭", "微信支付"],
        confirmationRequested: false
    )
    #endif
}

private struct CustomTabBar: View {
    @Binding var selection: AppTab
    @ObservedObject var voice: VoiceEntryModel
    @State private var isEntryDown = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            tabButton(.home, title: "首页", symbol: "house")
            tabButton(.statistics, title: "统计", symbol: "chart.bar")
            Color.clear.frame(maxWidth: .infinity)
            tabButton(.bills, title: "账单", symbol: "doc.plaintext")
            tabButton(.profile, title: "我的", symbol: "person")
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .frame(height: 74, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(Palette.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.border).frame(height: 0.5)
        }
        .overlay(alignment: .top) {
            entryButton
        }
    }

    /// 中央入口:点按 → 键盘记账;按住 → 语音记账(上滑取消)。
    private var entryButton: some View {
        Image(systemName: "plus")
            .font(.system(size: 27, weight: .light))
            .foregroundStyle(Palette.onPrimary)
            .frame(width: 56, height: 56)
            .background(Palette.primary)
            .clipShape(Circle())
            .overlay(Circle().stroke(Palette.background, lineWidth: 4.6))
            .scaleEffect(voice.isPressing ? 0.92 : 1)
            .animation(.easeOut(duration: 0.15), value: voice.isPressing)
            .offset(y: -26.5)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isEntryDown {
                            isEntryDown = true
                            voice.pressBegan()
                        }
                        voice.pressMoved(value.translation)
                    }
                    .onEnded { _ in
                        isEntryDown = false
                        voice.pressEnded()
                    }
            )
            .accessibilityLabel("记一笔")
            .accessibilityHint("点按使用键盘记账,按住说话进行语音记账")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default) {
                // VoiceOver 双击:立即松手,走键盘记账路径
                voice.pressBegan()
                voice.pressEnded()
            }
    }

    private func tabButton(_ tab: AppTab, title: String, symbol: String) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .symbolVariant(selection == tab ? .fill : .none)
                    .font(.system(size: 18, weight: .regular))
                    .frame(height: 20)
                Text(title)
                    .font(.system(size: 14))
            }
            .foregroundStyle(selection == tab ? Palette.primary : Palette.tertiary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}
