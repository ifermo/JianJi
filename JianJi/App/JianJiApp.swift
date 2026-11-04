import SwiftUI

@main
struct JianJiApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLocked = false
    @State private var isAuthenticating = false

    private let biometrics = BiometricAuthService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(colorScheme)
                .overlay {
                    if isLocked {
                        LockView(isAuthenticating: isAuthenticating, unlock: unlock)
                            .transition(.opacity)
                    }
                }
                .onAppear {
                    isLocked = store.settings.faceIDEnabled
                    if isLocked { unlock(allowsPasscode: false) }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background, store.settings.faceIDEnabled {
                        isLocked = true
                    } else if phase == .active, isLocked {
                        unlock(allowsPasscode: false)
                    }
                }
        }
    }

    private var colorScheme: ColorScheme? {
        switch store.settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private func unlock(allowsPasscode: Bool = false) {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        Task {
            let success = await biometrics.authenticate(
                reason: allowsPasscode ? "使用设备密码解锁简记" : "解锁简记，查看你的账单",
                allowsDevicePasscode: allowsPasscode
            )
            await MainActor.run {
                isAuthenticating = false
                if success { isLocked = false }
            }
        }
    }
}

private struct LockView: View {
    let isAuthenticating: Bool
    let unlock: (Bool) -> Void

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Palette.primary)
                Text("简记已锁定")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Palette.text)
                Button(isAuthenticating ? "正在验证…" : "使用面容 ID 解锁") { unlock(false) }
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Palette.onPrimary)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Palette.primary)
                    .clipShape(Capsule())
                    .disabled(isAuthenticating)

                Button("使用设备密码") { unlock(true) }
                    .font(.system(size: 16))
                    .foregroundStyle(Palette.primary)
                    .disabled(isAuthenticating)
            }
        }
        .zIndex(100)
    }
}
