import SwiftUI

enum VoiceOverlayPhase: Equatable {
    case preparing(Double?)
    case starting
    case listening
    case finalizing
    case unavailable(String)
}

struct VoiceOverlayState: Equatable {
    var phase: VoiceOverlayPhase = .listening
    var transcript = ""
    var level: Float = 0
    var elapsed: TimeInterval = 0
    var cancelArmed = false
    var isHandsFree = false
}

struct VoiceCaptureOverlay: View {
    let state: VoiceOverlayState
    var bottomInset: CGFloat = 96
    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let barFactors: [CGFloat] = [
        0.35, 0.60, 0.90, 0.50, 1.00, 0.70, 0.45,
        0.80, 0.55, 0.95, 0.65, 0.40, 0.75, 0.50, 0.30
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.14)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            panel
                .padding(.horizontal, 16)
                .padding(.bottom, bottomInset)
        }
        .allowsHitTesting(state.isHandsFree)
        .accessibilityElement(children: .contain)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            phaseContent
            transcriptBox
            Text(hint)
                .font(.system(size: 14))
                .foregroundStyle(state.cancelArmed ? Palette.danger : Palette.secondary)
                .frame(maxWidth: .infinity)
            if state.isHandsFree {
                buttons
            }
        }
        .padding(16)
        .background(Palette.background)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    state.cancelArmed ? Palette.danger.opacity(0.7) : Palette.border,
                    lineWidth: state.cancelArmed ? 1.5 : 0.5
                )
        )
        .shadow(color: Color.black.opacity(0.12), radius: 18, y: 8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(state.cancelArmed ? Palette.danger : Palette.text)
            Spacer()
            Text(trailing)
                .font(.system(size: 14, weight: .medium).monospacedDigit())
                .foregroundStyle(Palette.secondary)
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch state.phase {
        case .listening:
            waveform
        case .preparing(let progress):
            Group {
                if let progress {
                    ProgressView(value: progress)
                        .tint(Palette.primary)
                } else {
                    ProgressView()
                        .tint(Palette.primary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        case .starting:
            HStack(spacing: 10) {
                ProgressView()
                    .tint(Palette.primary)
                Text("正在准备录音…")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        case .finalizing:
            HStack(spacing: 10) {
                ProgressView()
                    .tint(Palette.primary)
                Text("正在整理最后的语音…")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        case .unavailable:
            Image(systemName: "mic.slash")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Palette.danger)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
    }

    private var waveform: some View {
        let normalized = max(0.06, min(1, CGFloat(state.level)))
        return HStack(alignment: .center, spacing: 4) {
            ForEach(0..<Self.barFactors.count, id: \.self) { index in
                Capsule()
                    .fill(index.isMultiple(of: 2) ? Palette.primary : Palette.primary.opacity(0.55))
                    .frame(width: 4, height: max(6, 44 * normalized * Self.barFactors[index]))
            }
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: state.level)
        .accessibilityHidden(true)
    }

    private var transcriptBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(transcriptLabel)
                .font(.system(size: 14))
                .foregroundStyle(Palette.secondary)
            Text(transcriptText)
                .font(.system(size: 16))
                .foregroundStyle(transcriptColor)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.border, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(transcriptLabel)：\(transcriptText)")
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button("取消") { onCancel?() }
                .font(.system(size: 16))
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Palette.soft)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            Button("结束并生成") { onFinish?() }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Palette.onPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Palette.primary)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        switch state.phase {
        case .preparing:
            return "正在准备语音模型"
        case .starting:
            return "正在启动麦克风…"
        case .listening:
            return state.isHandsFree ? "正在聆听" : (state.cancelArmed ? "松开取消" : "正在聆听")
        case .finalizing:
            return "正在生成账单…"
        case .unavailable(let message):
            if message.hasPrefix("没听清") { return "没听清" }
            if message.hasPrefix("麦克风启动较慢") { return "还没开始录音" }
            return "语音暂不可用"
        }
    }

    private var trailing: String {
        switch state.phase {
        case .preparing(let progress):
            if let progress {
                return "\(Int(progress * 100))%"
            }
            return "准备中"
        case .starting:
            return "请稍候"
        case .listening:
            return String(format: "%02d:%02d", Int(state.elapsed) / 60, Int(state.elapsed) % 60)
        case .finalizing:
            return "请稍候"
        case .unavailable:
            return ""
        }
    }

    private var statusColor: Color {
        if state.cancelArmed { return Palette.danger }
        switch state.phase {
        case .unavailable: return Palette.danger
        default: return Palette.primary
        }
    }

    private var transcriptLabel: String {
        switch state.phase {
        case .preparing, .starting:
            return "准备中"
        case .listening:
            return "实时转写"
        case .finalizing:
            return "识别内容"
        case .unavailable:
            return "提示"
        }
    }

    private var transcriptText: String {
        switch state.phase {
        case .preparing:
            return "首次使用需要下载语音模型，完成后即可按住说话"
        case .starting:
            return "请稍候，正在准备录音"
        case .listening:
            return state.transcript.isEmpty ? "请说话…" : state.transcript
        case .finalizing:
            return state.transcript.isEmpty ? "正在处理最后的语音…" : state.transcript
        case .unavailable(let message):
            return message
        }
    }

    private var transcriptColor: Color {
        if case .unavailable = state.phase { return Palette.danger }
        if case .listening = state.phase, state.transcript.isEmpty { return Palette.secondary }
        if case .finalizing = state.phase, state.transcript.isEmpty { return Palette.secondary }
        return Palette.text
    }

    private var hint: String {
        switch state.phase {
        case .preparing:
            return "松开可取消 · 准备完成后请按住再说"
        case .starting:
            return "正在启动麦克风 · 松开取消"
        case .listening:
            if state.isHandsFree {
                return "点按结束"
            }
            return state.cancelArmed ? "松开取消" : "松开结束 · 上滑取消"
        case .finalizing:
            return "正在整理分类与金额"
        case .unavailable:
            return "松开后可改用键盘"
        }
    }
}

#if DEBUG
struct VoiceOverlayPreviewView: View {
    @State private var state: VoiceOverlayState

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let name: String
        if let index = arguments.firstIndex(of: "-VoiceOverlayState"), index + 1 < arguments.count {
            name = arguments[index + 1]
        } else {
            name = "listening"
        }
        _state = State(initialValue: Self.makeState(name))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            previewHome
            VoiceCaptureOverlay(state: state, bottomInset: 96, onFinish: {}, onCancel: {})
            previewTabBar
        }
        .background(Palette.background)
    }

    private var previewHome: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text(Date().fullDayTitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondary)
                Text("早上好，JOJO")
                    .font(.system(size: 20, weight: .semibold))

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("本月可用")
                        Spacer()
                        Text("日常预算")
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.primary.opacity(0.75))

                    Text("¥ 6,420.00")
                        .font(.system(size: 32, weight: .medium))
                        .tracking(-1)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.primary.opacity(0.2))
                            Capsule().fill(Palette.primary).frame(width: geometry.size.width * 0.57)
                        }
                    }
                    .frame(height: 5)

                    HStack {
                        Text("已使用 57%")
                        Spacer()
                        Text("剩余 1 天")
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.primary.opacity(0.75))
                }
                .padding(18)
                .background(Palette.hero)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack(spacing: 10) {
                    previewStat("本月支出", "¥ 8,580.00")
                    previewStat("本月收入", "¥ 18,000.00")
                }

                Text("最近账单")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.top, 2)

                previewRow("超市采购", "今天 18:24 · 购物", "−¥ 126.80")
                previewRow("一乐拉面", "今天 12:16 · 餐饮", "−¥ 42.00")

                Spacer()
            }
            .padding(20)
            .padding(.bottom, 100)
        }
    }

    private func previewStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(Palette.secondary)
            Text(value)
                .font(.system(size: 18, weight: .medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.border, lineWidth: 0.5)
        )
    }

    private func previewRow(_ title: String, _ meta: String, _ amount: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bag")
                .font(.system(size: 16))
                .frame(width: 36, height: 36)
                .background(Palette.soft)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .medium))
                Text(meta).font(.system(size: 14)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            Text(amount).font(.system(size: 15, weight: .medium))
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.border).frame(height: 0.5)
        }
    }

    private var previewTabBar: some View {
        HStack(alignment: .top, spacing: 0) {
            tab("首页")
            tab("统计")
            Color.clear.frame(maxWidth: .infinity)
            tab("账单")
            tab("我的")
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
            Image(systemName: "mic.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Palette.onPrimary)
                .frame(width: 56, height: 56)
                .background(Palette.primary)
                .clipShape(Circle())
                .overlay(Circle().stroke(Palette.background, lineWidth: 4.6))
                .offset(y: -26.5)
        }
    }

    private func tab(_ title: String) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Palette.tertiary.opacity(0.35))
                .frame(width: 20, height: 20)
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(Palette.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private static func makeState(_ name: String) -> VoiceOverlayState {
        switch name {
        case "preparing":
            return VoiceOverlayState(phase: .preparing(0.42))
        case "cancel":
            return VoiceOverlayState(
                phase: .listening,
                transcript: "昨天午饭花了四十二元，用微信支付…",
                level: 0.60,
                elapsed: 3.4,
                cancelArmed: true
            )
        case "finalizing":
            return VoiceOverlayState(
                phase: .finalizing,
                transcript: "昨天午饭花了四十二元，用微信支付",
                level: 0,
                elapsed: 4.1
            )
        case "unavailable":
            return VoiceOverlayState(
                phase: .unavailable("麦克风权限未开启，请到设置中允许"),
                transcript: "",
                level: 0,
                elapsed: 0
            )
        case "handsfree":
            return VoiceOverlayState(
                phase: .listening,
                transcript: "昨天午饭花了四十二元",
                level: 0.50,
                elapsed: 2.6,
                isHandsFree: true
            )
        default:
            return VoiceOverlayState(
                phase: .listening,
                transcript: "昨天午饭花了四十二元，用微信支付…",
                level: 0.55,
                elapsed: 3.2
            )
        }
    }
}
#endif
