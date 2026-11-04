import CoreGraphics

enum HoldPhase: Equatable {
    case idle
    case pressing
    case recording
    case finalizing
}

enum HoldEvent: Equatable {
    case pressBegan
    case thresholdReached
    case moved(CGFloat)
    case released
    case cancelled
    case maxDurationReached
    case reset
}

enum HoldAction: Equatable {
    case none
    case openManual
    case beginCapture
    case stopCapture
    case cancelCapture
}

struct HoldToTalkStateMachine {
    private(set) var phase: HoldPhase = .idle
    private(set) var isCancelArmed = false
    private(set) var translationY: CGFloat = 0

    let cancelArmDistance: CGFloat
    let cancelDisarmDistance: CGFloat

    init(cancelArmDistance: CGFloat = -80, cancelDisarmDistance: CGFloat = -50) {
        self.cancelArmDistance = cancelArmDistance
        self.cancelDisarmDistance = cancelDisarmDistance
    }

    mutating func handle(_ event: HoldEvent) -> HoldAction {
        switch event {
        case .pressBegan:
            guard phase == .idle else { return .none }
            phase = .pressing
            isCancelArmed = false
            translationY = 0
            return .none

        case .thresholdReached:
            guard phase == .pressing else { return .none }
            phase = .recording
            return .beginCapture

        case .moved(let y):
            translationY = y
            guard phase == .recording else { return .none }
            if y < cancelArmDistance, !isCancelArmed {
                isCancelArmed = true
            } else if y > cancelDisarmDistance, isCancelArmed {
                isCancelArmed = false
            }
            return .none

        case .released:
            switch phase {
            case .pressing:
                phase = .idle
                isCancelArmed = false
                return .openManual
            case .recording:
                let cancelled = isCancelArmed
                isCancelArmed = false
                if cancelled {
                    phase = .idle
                    return .cancelCapture
                }
                phase = .finalizing
                return .stopCapture
            case .idle, .finalizing:
                return .none
            }

        case .cancelled:
            switch phase {
            case .pressing:
                phase = .idle
                isCancelArmed = false
                return .none
            case .recording:
                phase = .idle
                isCancelArmed = false
                return .cancelCapture
            case .idle, .finalizing:
                return .none
            }

        case .maxDurationReached:
            guard phase == .recording else { return .none }
            let cancelled = isCancelArmed
            isCancelArmed = false
            if cancelled {
                phase = .idle
                return .cancelCapture
            }
            phase = .finalizing
            return .stopCapture

        case .reset:
            phase = .idle
            isCancelArmed = false
            translationY = 0
            return .none
        }
    }
}
