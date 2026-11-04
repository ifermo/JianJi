import Foundation
import AVFoundation
import Speech
import os

enum VoiceReadiness: Equatable {
    case unknown
    case ready
    case needsPermission
    case permissionDenied
    case needsAssets
    case unsupported
}

private final class VoiceTapContext: @unchecked Sendable {
    let converter: AnalyzerInputConverter
    let continuation: AsyncStream<AnalyzerInput>.Continuation
    let onLevel: @Sendable (Float) -> Void
    let onError: @Sendable (String) -> Void

    init(
        converter: AnalyzerInputConverter,
        continuation: AsyncStream<AnalyzerInput>.Continuation,
        onLevel: @escaping @Sendable (Float) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) {
        self.converter = converter
        self.continuation = continuation
        self.onLevel = onLevel
        self.onError = onError
    }
}

private struct PrewarmedSpeech {
    let transcriber: SpeechTranscriber
    let detector: SpeechDetector
    let analyzer: SpeechAnalyzer
    let converter: AnalyzerInputConverter
}

@MainActor
final class VoiceRecognitionService: ObservableObject {
    enum State: Equatable {
        case idle
        case preparing(Double?)
        case starting
        case capturing
        case finalizing
        case unavailable(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var readiness: VoiceReadiness = .unknown
    @Published private(set) var volatileText = ""
    @Published private(set) var finalText = ""
    @Published private(set) var level: Float = 0
    @Published private(set) var hasSpeech = false

    var combinedText: String {
        (finalText + volatileText).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canPrestart: Bool {
        readiness == .ready
    }

    private let logger = Logger(subsystem: "com.jojo.JianJi", category: "Voice")
    private var locale: Locale?
    private var transcriber: SpeechTranscriber?
    private var detector: SpeechDetector?
    private var analyzer: SpeechAnalyzer?
    private var engine: AVAudioEngine?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var transcriptionTask: Task<Void, Never>?
    private var detectionTask: Task<Void, Never>?
    private var analyzerStartTask: Task<Void, Never>?
    private var tapInstalled = false
    private var sessionID = UUID()
    private var isPreparing = false
    private var prewarmed: PrewarmedSpeech?
    private var prewarmTask: Task<Void, Never>?

    init() {
        Task {
            await checkReadiness()
            prewarm()
        }
    }

    func prewarm() {
        guard readiness == .ready, locale != nil, prewarmed == nil, prewarmTask == nil else { return }
        switch state {
        case .starting, .capturing, .finalizing:
            return
        case .idle, .preparing, .unavailable:
            break
        }

        prewarmTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.makePrewarmed()
            self.prewarmed = result
            self.prewarmTask = nil
        }
    }

    private func makePrewarmed() async -> PrewarmedSpeech? {
        guard let locale else { return nil }
        do {
            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            let detector = SpeechDetector(
                detectionOptions: .init(sensitivityLevel: .medium),
                reportResults: true
            )
            let analyzer = SpeechAnalyzer(modules: [transcriber, detector])
            let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
            try await analyzer.prepareToAnalyze(in: format)
            let converter = try await AnalyzerInputConverter.converter(compatibleWith: [transcriber, detector])
            return PrewarmedSpeech(
                transcriber: transcriber,
                detector: detector,
                analyzer: analyzer,
                converter: converter
            )
        } catch {
            logger.error("prewarm failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func takePrewarmed() async -> PrewarmedSpeech? {
        if let prewarmTask {
            await prewarmTask.value
        }
        let value = prewarmed
        prewarmed = nil
        prewarmTask = nil
        return value
    }

    @discardableResult
    func checkReadiness() async -> VoiceReadiness {
        guard SpeechTranscriber.isAvailable else {
            readiness = .unsupported
            return .unsupported
        }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "zh_CN")) else {
            readiness = .unsupported
            return .unsupported
        }
        locale = supported

        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            break
        case .denied:
            readiness = .permissionDenied
            return .permissionDenied
        case .undetermined:
            readiness = .needsPermission
            return .needsPermission
        @unknown default:
            readiness = .unsupported
            return .unsupported
        }

        let probe = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        let status = await AssetInventory.status(forModules: [probe])
        switch status {
        case .installed:
            readiness = .ready
            return .ready
        case .unsupported:
            readiness = .unsupported
            return .unsupported
        case .downloading, .supported:
            readiness = .needsAssets
            return .needsAssets
        @unknown default:
            readiness = .needsAssets
            return .needsAssets
        }
    }

    func prepare() async -> Bool {
        if isPreparing { return false }
        if readiness == .ready, locale != nil {
            state = .idle
            return true
        }
        isPreparing = true
        defer { isPreparing = false }

        var current = await checkReadiness()
        print("[VoiceService] prepare readiness=\(current) locale=\(locale?.identifier ?? "nil")")
        if current == .unsupported {
            state = .unavailable("此设备不支持语音识别，请改用键盘记账")
            return false
        }
        if current == .permissionDenied {
            state = .unavailable("麦克风权限未开启，请到设置中允许")
            return false
        }
        if current == .needsPermission {
            let granted = await requestMicrophonePermission()
            guard granted else {
                state = .unavailable("麦克风权限未开启，请到设置中允许")
                return false
            }
            current = await checkReadiness()
        }

        guard let locale else {
            state = .unavailable("当前语言不支持语音识别")
            return false
        }
        guard current != .unsupported else {
            state = .unavailable("此设备不支持语音识别，请改用键盘记账")
            return false
        }

        let probe = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        let status = await AssetInventory.status(forModules: [probe])
        if status != .installed {
            state = .preparing(0)
            do {
                guard let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) else {
                    if await AssetInventory.status(forModules: [probe]) == .installed {
                        state = .idle
                        readiness = .ready
                        return true
                    }
                    state = .unavailable("语音模型不可用，请改用键盘记账")
                    return false
                }
                let monitor = Task { @MainActor [weak self] in
                    while !Task.isCancelled {
                        self?.state = .preparing(request.progress.fractionCompleted)
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                }
                try await request.downloadAndInstall()
                monitor.cancel()
            } catch {
                logger.error("asset install failed: \(error.localizedDescription)")
                state = .unavailable("语音模型下载失败，请重试")
                return false
            }
        }

        let finalStatus = await checkReadiness()
        guard finalStatus == .ready else {
            state = .unavailable("语音准备未完成，请重试")
            return false
        }
        state = .idle
        return true
    }

    func start() async -> Bool {
        switch state {
        case .starting, .capturing, .finalizing:
            return false
        case .idle, .preparing, .unavailable:
            break
        }

        let id = UUID()
        sessionID = id
        guard await prepare() else {
            if sessionID != id {
                await cancel()
            }
            return false
        }
        guard sessionID == id else {
            await cancel()
            return false
        }
        state = .starting
        volatileText = ""
        finalText = ""
        level = 0
        hasSpeech = false
        logger.info("start capture")

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
            guard sessionID == id else { await cancel(); return false }
            guard let locale else {
                throw VoiceRecognitionFailure.localeUnavailable
            }

            let prewarmed = await takePrewarmed()
            let transcriber: SpeechTranscriber
            let detector: SpeechDetector
            let analyzer: SpeechAnalyzer
            let converter: AnalyzerInputConverter
            if let prewarmed {
                transcriber = prewarmed.transcriber
                detector = prewarmed.detector
                analyzer = prewarmed.analyzer
                converter = prewarmed.converter
            } else {
                transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
                detector = SpeechDetector(
                    detectionOptions: .init(sensitivityLevel: .medium),
                    reportResults: true
                )
                analyzer = SpeechAnalyzer(modules: [transcriber, detector])
                converter = try await AnalyzerInputConverter.converter(compatibleWith: [transcriber, detector])
            }
            let (inputStream, inputContinuation) = AsyncStream.makeStream(of: AnalyzerInput.self)

            self.transcriber = transcriber
            self.detector = detector
            self.analyzer = analyzer
            self.inputContinuation = inputContinuation

            guard sessionID == id else { await cancel(); return false }

            transcriptionTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        if result.isFinal {
                            self.finalText += text
                            self.volatileText = ""
                        } else {
                            self.volatileText = text
                        }
                    }
                } catch {
                    self.logger.error("transcription failed: \(error.localizedDescription)")
                }
            }

            detectionTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    for try await result in detector.results where result.speechDetected {
                        self.hasSpeech = true
                    }
                } catch {
                    self.logger.error("detection failed: \(error.localizedDescription)")
                }
            }

            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                throw VoiceRecognitionFailure.invalidInputFormat
            }

            let tapContext = VoiceTapContext(
                converter: converter,
                continuation: inputContinuation,
                onLevel: { [weak self] value in
                    Task { @MainActor [weak self] in
                        self?.level = value
                    }
                },
                onError: { [weak self] message in
                    Task { @MainActor [weak self] in
                        self?.logger.error("\(message, privacy: .public)")
                    }
                }
            )

            let tapBufferSize = AVAudioFrameCount(recordingFormat.sampleRate * 0.2)
            try inputNode.installAudioTap(onBus: 0, bufferSize: tapBufferSize, format: recordingFormat) { buffer, _ in
                let mutable = AVAudioPCMBuffer(copying: buffer)
                let rms = Self.rms(mutable)
                do {
                    let inputs = try tapContext.converter.convert(mutable, at: nil)
                    for input in inputs {
                        tapContext.continuation.yield(input)
                    }
                } catch {
                    tapContext.onError("audio convert failed: \(error.localizedDescription)")
                }
                tapContext.onLevel(min(1, max(0, rms * 8)))
            }
            tapInstalled = true
            engine.prepare()
            try engine.start()
            self.engine = engine

            guard sessionID == id else { await cancel(); return false }
            state = .capturing
            logger.info("capturing")

            analyzerStartTask = Task { [weak self] in
                do {
                    try await analyzer.start(inputSequence: inputStream)
                } catch {
                    await self?.handleAnalyzerStartFailure(error, sessionID: id)
                }
            }
            return true
        } catch {
            if sessionID == id {
                logger.error("start failed: \(error.localizedDescription)")
                await cleanupAfterFailure()
                state = .unavailable(error.localizedDescription)
            } else {
                await cancel()
            }
            return false
        }
    }

    func stop() async -> String {
        guard state == .capturing || state == .starting else {
            return combinedText
        }
        if state == .starting {
            await cancel()
            return ""
        }

        state = .finalizing
        stopAudio()
        inputContinuation?.finish()

        if let analyzerStartTask {
            _ = await analyzerStartTask.value
        }

        if let analyzer {
            let finalize = Task { try await analyzer.finalizeAndFinishThroughEndOfInput() }
            let timeout = Task {
                try? await Task.sleep(for: .seconds(1.5))
                finalize.cancel()
                await analyzer.cancelAndFinishNow()
            }
            do {
                try await finalize.value
            } catch {
                logger.error("finalize failed: \(error.localizedDescription)")
            }
            timeout.cancel()
        }

        if let transcriptionTask {
            let drain = Task { await transcriptionTask.value }
            let drainTimeout = Task {
                try? await Task.sleep(for: .seconds(1))
                drain.cancel()
            }
            _ = await drain.value
            drainTimeout.cancel()
        } else {
            try? await Task.sleep(for: .milliseconds(200))
        }
        transcriptionTask?.cancel()
        detectionTask?.cancel()
        let text = combinedText
        state = .idle
        cleanupReferences()
        logger.info("stopped, characters=\(text.count)")
        prewarm()
        return text
    }

    func cancel() async {
        sessionID = UUID()
        state = .idle
        stopAudio()
        inputContinuation?.finish()
        analyzerStartTask?.cancel()
        analyzerStartTask = nil
        await analyzer?.cancelAndFinishNow()
        transcriptionTask?.cancel()
        detectionTask?.cancel()
        cleanupReferences()
        volatileText = ""
        finalText = ""
        level = 0
        hasSpeech = false
        logger.info("cancelled")
        prewarm()
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func cleanupAfterFailure() async {
        stopAudio()
        inputContinuation?.finish()
        analyzerStartTask?.cancel()
        analyzerStartTask = nil
        await analyzer?.cancelAndFinishNow()
        transcriptionTask?.cancel()
        detectionTask?.cancel()
        cleanupReferences()
    }

    private func handleAnalyzerStartFailure(_ error: Error, sessionID: UUID) async {
        guard self.sessionID == sessionID else { return }
        logger.error("analyzer start failed: \(error.localizedDescription)")
        await cleanupAfterFailure()
        state = .unavailable(error.localizedDescription)
    }

    private func stopAudio() {
        if tapInstalled, let engine {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine?.stop()
        engine = nil
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.error("audio session deactivate failed: \(error.localizedDescription)")
        }
    }

    private func cleanupReferences() {
        transcriber = nil
        detector = nil
        analyzer = nil
        inputContinuation = nil
        transcriptionTask = nil
        detectionTask = nil
        analyzerStartTask = nil
        tapInstalled = false
        hasSpeech = false
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<count {
            let value = data[index]
            sum += value * value
        }
        return sqrt(sum / Float(count))
    }
}

private enum VoiceRecognitionFailure: LocalizedError {
    case localeUnavailable
    case invalidInputFormat

    var errorDescription: String? {
        switch self {
        case .localeUnavailable: "当前语言不支持语音识别"
        case .invalidInputFormat: "麦克风输入不可用"
        }
    }
}
