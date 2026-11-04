import Foundation
import SwiftUI
import Combine
import UIKit

@MainActor
final class VoiceEntryModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case listening
        case finalizing
        case reviewing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var overlayVisible = false
    @Published private(set) var isPressing = false
    @Published private(set) var cancelArmed = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var level: Float = 0
    @Published private(set) var transcript = ""
    @Published private(set) var draft: VoiceDraft?
    @Published private(set) var serviceState: VoiceRecognitionService.State = .idle

    let service = VoiceRecognitionService()

    var categories: [LedgerCategory] = LedgerCategory.defaults
    var accounts: [String] = LedgerAccounts.all
    var onManual: (() -> Void)?

    func configure(categories: [LedgerCategory], accounts: [String]) {
        self.categories = categories
        self.accounts = accounts
    }

    private var hold = HoldToTalkStateMachine()
    private var startTask: Task<Bool, Never>?
    private var thresholdTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var startedAt: Date?
    private var captureID = UUID()
    private var cancellables = Set<AnyCancellable>()

    init() {
        service.$state
            .assign(to: &$serviceState)
        service.$level
            .assign(to: &$level)
        service.$volatileText
            .combineLatest(service.$finalText)
            .sink { [weak self] volatile, final in
                MainActor.assumeIsolated {
                    self?.transcript = final + volatile
                }
            }
            .store(in: &cancellables)
    }

    var isActive: Bool {
        overlayVisible || isPressing
    }

    var overlayState: VoiceOverlayState {
        if case .failed(let message) = phase {
            return VoiceOverlayState(
                phase: .unavailable(message),
                transcript: transcript,
                level: 0,
                elapsed: elapsed,
                cancelArmed: false,
                isHandsFree: false
            )
        }

        let overlayPhase: VoiceOverlayPhase
        if phase == .finalizing {
            overlayPhase = .finalizing
        } else {
            switch serviceState {
            case .preparing(let progress):
                overlayPhase = .preparing(progress)
            case .starting:
                overlayPhase = .starting
            case .capturing, .idle:
                overlayPhase = .listening
            case .finalizing:
                overlayPhase = .finalizing
            case .unavailable(let message):
                overlayPhase = .unavailable(message)
            }
        }

        return VoiceOverlayState(
            phase: overlayPhase,
            transcript: transcript,
            level: level,
            elapsed: elapsed,
            cancelArmed: cancelArmed,
            isHandsFree: false
        )
    }

    func pressBegan() {
        hideTask?.cancel()
        guard phase == .idle, !overlayVisible else { return }
        _ = hold.handle(.pressBegan)
        isPressing = true
        cancelArmed = false
        if service.canPrestart {
            startTask?.cancel()
            startTask = Task { await service.start() }
        }
        thresholdTask?.cancel()
        thresholdTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self, self.hold.phase == .pressing else { return }
            self.thresholdReached()
        }
    }

    func pressMoved(_ translation: CGSize) {
        guard isPressing else { return }
        _ = hold.handle(.moved(translation.height))
        guard hold.isCancelArmed != cancelArmed else { return }
        cancelArmed = hold.isCancelArmed
        UIImpactFeedbackGenerator(style: cancelArmed ? .rigid : .light).impactOccurred()
    }

    func pressEnded() {
        thresholdTask?.cancel()
        thresholdTask = nil
        isPressing = false

        let action = hold.handle(.released)
        cancelArmed = hold.isCancelArmed
        switch action {
        case .openManual:
            startTask?.cancel()
            startTask = nil
            captureID = UUID()
            Task { await service.cancel() }
            onManual?()
        case .stopCapture:
            Task { await finish() }
        case .cancelCapture:
            cancel()
        case .beginCapture, .none:
            break
        }
    }

    func cancel() {
        thresholdTask?.cancel()
        timerTask?.cancel()
        hideTask?.cancel()
        startTask?.cancel()
        thresholdTask = nil
        timerTask = nil
        hideTask = nil
        startTask = nil
        captureID = UUID()
        _ = hold.handle(.cancelled)
        _ = hold.handle(.reset)
        isPressing = false
        cancelArmed = false
        overlayVisible = false
        phase = .idle
        elapsed = 0
        transcript = ""
        Task { await service.cancel() }
    }

    func reset() {
        thresholdTask?.cancel()
        timerTask?.cancel()
        hideTask?.cancel()
        startTask?.cancel()
        thresholdTask = nil
        timerTask = nil
        hideTask = nil
        startTask = nil
        captureID = UUID()
        _ = hold.handle(.reset)
        isPressing = false
        cancelArmed = false
        overlayVisible = false
        phase = .idle
        draft = nil
        elapsed = 0
        transcript = ""
        Task { await service.cancel() }
    }

    private func thresholdReached() {
        let action = hold.handle(.thresholdReached)
        guard action == .beginCapture else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await begin() }
    }

    private func begin() async {
        hideTask?.cancel()
        overlayVisible = true
        phase = .listening
        elapsed = 0
        startedAt = Date()
        transcript = ""

        let id = UUID()
        captureID = id
        let task = startTask
        startTask = nil
        let started: Bool
        if let task {
            started = await task.value
        } else {
            started = await service.start()
        }

        guard captureID == id, overlayVisible else {
            await service.cancel()
            return
        }

        guard started else {
            phase = .failed(serviceErrorMessage)
            showErrorBriefly()
            return
        }

        phase = .listening
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        startTimer()
    }

    private func finish() async {
        guard phase == .listening else { return }
        captureID = UUID()
        timerTask?.cancel()
        timerTask = nil
        phase = .finalizing
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let stateBeforeStop = service.state
        let text = await service.stop()
        _ = hold.handle(.reset)
        cancelArmed = false

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if case .starting = stateBeforeStop {
                phase = .failed("麦克风启动较慢，请按住久一点再说")
                showErrorBriefly()
            } else if case .preparing = stateBeforeStop {
                phase = .failed("语音还在准备，请稍后再按住说")
                showErrorBriefly()
            } else {
                phase = .failed("没听清，请按住再说一次")
                showErrorBriefly(seconds: 1.5)
            }
            return
        }

        let parser = VoiceTransactionParser(categories: categories)
        let draft = parser.parse(trimmed, now: Date(), calendar: .current)
        self.draft = draft
        overlayVisible = false
        phase = .reviewing
    }

    private func startTimer() {
        timerTask?.cancel()
        startedAt = Date()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, self.phase == .listening, self.overlayVisible else { return }
                if let startedAt = self.startedAt {
                    self.elapsed = Date().timeIntervalSince(startedAt)
                }
                if self.elapsed >= 30 {
                    let action = self.hold.handle(.maxDurationReached)
                    self.cancelArmed = self.hold.isCancelArmed
                    if action == .cancelCapture {
                        self.cancel()
                    } else {
                        await self.finish()
                    }
                    return
                }
                if !self.service.hasSpeech, self.elapsed >= 8 {
                    await self.finish()
                    return
                }
            }
        }
    }

    private func showErrorBriefly(seconds: TimeInterval = 4) {
        overlayVisible = true
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.overlayVisible = false
            self.phase = .idle
            self.elapsed = 0
            self.transcript = ""
        }
    }

    private var serviceErrorMessage: String {
        if case .unavailable(let message) = service.state {
            return message
        }
        if case .idle = service.state {
            return "语音启动被中断，请重试"
        }
        return "语音启动失败，请重试"
    }
}
