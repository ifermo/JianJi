#if DEBUG
import SwiftUI
import AVFoundation
import Speech
import UIKit
import os

private final class VoiceSpikeTapContext: @unchecked Sendable {
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

@MainActor
final class VoiceSpikeModel: ObservableObject {
    @Published var speechAvailable = false
    @Published var supportedLocaleCount = 0
    @Published var localeID = "—"
    @Published var localeSupported = false
    @Published var assetStatus = "—"
    @Published var micPermission = "—"
    @Published var assetsReady = false
    @Published var isPreparing = false
    @Published var prepareProgress = 0.0

    @Published var gesturePhase = "idle"
    @Published var holding = false
    @Published var cancelArmed = false
    @Published var translationY: CGFloat = 0
    @Published var gestureDuration: TimeInterval = 0
    @Published var showOverlay = true

    @Published var recognitionPhase = "idle"
    @Published var volatileText = ""
    @Published var finalText = ""
    @Published var level: Float = 0
    @Published var elapsed: TimeInterval = 0
    @Published var detectorSpeech = false
    @Published var metrics: [String] = []

    @Published var logs: [String] = []

    private let logger = Logger(subsystem: "com.jojo.JianJi", category: "VoiceSpike")
    private var locale: Locale?
    private var thresholdTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var resetTask: Task<Void, Never>?
    private var pressStartedAt: Date?
    private var startedAt: Date?
    private var releaseAt: Date?
    private var firstResultAt: Date?
    private var firstFinalAt: Date?
    private var hasSpeech = false
    private var resultCount = 0
    private var finalCount = 0

    private var transcriber: SpeechTranscriber?
    private var detector: SpeechDetector?
    private var analyzer: SpeechAnalyzer?
    private var engine: AVAudioEngine?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var transcriptionTask: Task<Void, Never>?
    private var detectionTask: Task<Void, Never>?
    private var tapInstalled = false
    private var interruptionObserver: NSObjectProtocol?

    private let minHold: TimeInterval = 0.35
    private let cancelArmDistance: CGFloat = -80
    private let cancelDisarmDistance: CGFloat = -50
    private let maxHold: TimeInterval = 30
    private let noSpeechTimeout: TimeInterval = 8

    var canRecord: Bool {
        speechAvailable && localeSupported && micPermission == "granted" && assetsReady
    }

    var isActive: Bool {
        ["starting", "capturing", "finalizing", "cancelling"].contains(recognitionPhase)
    }

    init() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.didBecomeInactiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.log("AUDIO session did become inactive")
                self?.cancelActive()
            }
        }
        log("VoiceSpike init args=\(ProcessInfo.processInfo.arguments)")
    }

    func onAppear(autoPrepare: Bool) {
        Task {
            await refreshCapabilities()
            if autoPrepare {
                await prepareAll()
            }
        }
    }

    func refreshCapabilities() async {
        speechAvailable = SpeechTranscriber.isAvailable
        let locales = await SpeechTranscriber.supportedLocales
        supportedLocaleCount = locales.count
        let zh = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "zh_CN"))
        locale = zh
        localeSupported = zh != nil
        localeID = zh?.identifier ?? "—"
        updateMicPermission()
        log("capabilities available=\(speechAvailable) locales=\(locales.count) zh=\(localeID) mic=\(micPermission)")
        if let zh {
            let probe = SpeechTranscriber(locale: zh, preset: .progressiveTranscription)
            let status = await AssetInventory.status(forModules: [probe])
            assetStatus = statusText(status)
            assetsReady = (status == .installed)
            log("asset status=\(assetStatus)")
        } else {
            assetStatus = "no-locale"
        }
    }

    func updateMicPermission() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: micPermission = "granted"
        case .denied: micPermission = "denied"
        case .undetermined: micPermission = "undetermined"
        @unknown default: micPermission = "unknown"
        }
    }

    func requestMicPermission() async {
        log("requesting mic permission")
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        updateMicPermission()
        log("mic permission granted=\(granted) status=\(micPermission)")
    }

    func prepareAll() async {
        await refreshCapabilities()
        if micPermission == "undetermined" {
            await requestMicPermission()
        }
        await prepareAssets()
        log("READY? \(canRecord)")
    }

    func prepareAssets() async {
        guard let locale else {
            log("prepare skipped: no locale")
            return
        }
        guard !isPreparing else { return }
        isPreparing = true
        prepareProgress = 0
        defer { isPreparing = false }

        let probe = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        let start = Date()
        do {
            let status = await AssetInventory.status(forModules: [probe])
            assetStatus = statusText(status)
            log("asset before=\(assetStatus)")
            if status == .installed {
                assetsReady = true
                prepareProgress = 1
                return
            }
            if status == .unsupported {
                assetsReady = false
                log("asset unsupported")
                return
            }
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
                let monitor = Task { @MainActor [weak self] in
                    while !Task.isCancelled {
                        self?.prepareProgress = request.progress.fractionCompleted
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                }
                try await request.downloadAndInstall()
                monitor.cancel()
            }
            let after = await AssetInventory.status(forModules: [probe])
            assetStatus = statusText(after)
            assetsReady = (after == .installed)
            prepareProgress = assetsReady ? 1 : prepareProgress
            let seconds = Date().timeIntervalSince(start)
            addMetric("asset prepare", seconds)
            log("asset after=\(assetStatus) in \(ms(seconds))")
        } catch {
            log("asset error=\(error)")
            assetStatus = "error"
            assetsReady = false
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func gestureChanged(_ translation: CGSize) {
        translationY = translation.height
        if pressStartedAt == nil {
            pressStartedAt = Date()
            gesturePhase = "pressing"
            log("PRESS down")
            thresholdTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, let self, self.pressStartedAt != nil, !self.holding else { return }
                self.beginHold()
            }
        }
        guard holding else { return }
        if translation.height < cancelArmDistance, !cancelArmed {
            cancelArmed = true
            log("CANCEL ARM at \(Int(translation.height))")
        } else if translation.height > cancelDisarmDistance, cancelArmed {
            cancelArmed = false
            log("CANCEL DISARM at \(Int(translation.height))")
        }
    }

    func gestureEnded() {
        thresholdTask?.cancel()
        thresholdTask = nil
        guard let start = pressStartedAt else { return }
        let duration = Date().timeIntervalSince(start)
        gestureDuration = duration
        pressStartedAt = nil

        if holding {
            holding = false
            gesturePhase = "released"
            releaseAt = Date()
            log("RELEASE after \(ms(duration)) cancelArmed=\(cancelArmed) phase=\(recognitionPhase)")
            if cancelArmed {
                Task { await cancelRecognition() }
            } else if recognitionPhase == "starting" {
                log("release during starting -> cancel start")
                Task { await cancelRecognition() }
            } else if recognitionPhase == "capturing" {
                Task { await finishRecognition(reason: "release") }
            } else {
                log("release with no active recognition=\(recognitionPhase)")
            }
        } else {
            gesturePhase = "tap"
            log("TAP \(ms(duration)) -> keyboard; no mic started")
        }
        cancelArmed = false
        scheduleGestureReset()
    }

    private func beginHold() {
        guard !holding else { return }
        holding = true
        gesturePhase = "holding"
        log("HOLD threshold reached overlay=\(showOverlay) canRecord=\(canRecord)")
        Task { await startRecognition() }
    }

    func cancelActive() {
        thresholdTask?.cancel()
        thresholdTask = nil
        pressStartedAt = nil
        holding = false
        gesturePhase = "system-cancel"
        cancelArmed = false
        log("SYSTEM CANCEL / background")
        Task { await cancelRecognition() }
    }

    private func scheduleGestureReset() {
        resetTask?.cancel()
        resetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard let self, !self.holding else { return }
            self.gesturePhase = "idle"
            self.translationY = 0
            self.gestureDuration = 0
        }
    }

    func startRecognition() async {
        guard canRecord else {
            recognitionPhase = "not-ready"
            log("START blocked mic=\(micPermission) assets=\(assetsReady) locale=\(localeID) available=\(speechAvailable)")
            return
        }
        guard !isActive else {
            log("START ignored already=\(recognitionPhase)")
            return
        }

        recognitionPhase = "starting"
        startedAt = Date()
        releaseAt = nil
        hasSpeech = false
        resultCount = 0
        finalCount = 0
        firstResultAt = nil
        firstFinalAt = nil
        volatileText = ""
        finalText = ""
        detectorSpeech = false
        level = 0
        elapsed = 0
        metrics.removeAll()
        log("START recognition")

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
            guard holding else { await cancelRecognition(); return }
            guard let locale else { throw SpikeError.noLocale }

            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            let detector = SpeechDetector(
                detectionOptions: .init(sensitivityLevel: .medium),
                reportResults: true
            )
            let analyzer = SpeechAnalyzer(modules: [transcriber, detector])
            let bestFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
            log("best format=\(bestFormat?.description ?? "nil")")
            let converter = try await AnalyzerInputConverter.converter(compatibleWith: [transcriber, detector])
            let (inputStream, inputContinuation) = AsyncStream.makeStream(of: AnalyzerInput.self)

            self.transcriber = transcriber
            self.detector = detector
            self.analyzer = analyzer
            self.inputContinuation = inputContinuation

            transcriptionTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    for try await result in transcriber.results {
                        self.handleTranscription(result)
                    }
                    self.log("transcription stream ended")
                } catch {
                    self.log("transcription error=\(error)")
                }
            }
            detectionTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    for try await result in detector.results {
                        self.handleDetection(result)
                    }
                    self.log("detector stream ended")
                } catch {
                    self.log("detector error=\(error)")
                }
            }

            try await analyzer.start(inputSequence: inputStream)
            guard holding else { await cancelRecognition(); return }

            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            log("input format=\(recordingFormat)")
            guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                throw SpikeError.noInputFormat
            }
            let tapBufferSize = AVAudioFrameCount(recordingFormat.sampleRate * 0.2)
            log("tap buffer=\(tapBufferSize) frames (200ms)")
            let tapContext = VoiceSpikeTapContext(
                converter: converter,
                continuation: inputContinuation,
                onLevel: { [weak self] level in
                    Task { @MainActor [weak self] in
                        self?.level = level
                    }
                },
                onError: { [weak self] message in
                    Task { @MainActor [weak self] in
                        self?.log(message)
                    }
                }
            )
            try inputNode.installAudioTap(onBus: 0, bufferSize: tapBufferSize, format: recordingFormat) { buffer, _ in
                let mutable = AVAudioPCMBuffer(copying: buffer)
                let rms = Self.rms(mutable)
                do {
                    let inputs = try tapContext.converter.convert(mutable, at: nil)
                    for input in inputs {
                        tapContext.continuation.yield(input)
                    }
                } catch {
                    tapContext.onError("audio convert error=\(error)")
                }
                tapContext.onLevel(min(1, max(0, rms * 8)))
            }
            tapInstalled = true
            engine.prepare()
            try engine.start()
            self.engine = engine
            guard holding else { await cancelRecognition(); return }
            recognitionPhase = "capturing"
            if let startedAt {
                addMetric("threshold→capturing", Date().timeIntervalSince(startedAt))
            }
            log("CAPTURING")
            startTimer()
        } catch {
            log("START FAILED=\(error)")
            recognitionPhase = "failed"
            stopAudio()
            await analyzer?.cancelAndFinishNow()
            cleanup()
        }
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, self.recognitionPhase == "capturing" else { return }
                if let startedAt = self.startedAt {
                    self.elapsed = Date().timeIntervalSince(startedAt)
                }
                if self.elapsed >= self.maxHold {
                    self.log("MAX HOLD \(Int(self.maxHold))s")
                    await self.finishRecognition(reason: "max-hold")
                    return
                }
                if !self.hasSpeech, self.elapsed >= self.noSpeechTimeout {
                    self.log("NO SPEECH \(Int(self.noSpeechTimeout))s")
                    await self.finishRecognition(reason: "no-speech")
                    return
                }
            }
        }
    }

    private func handleTranscription(_ result: SpeechTranscriber.Result) {
        resultCount += 1
        let text = String(result.text.characters)
        if firstResultAt == nil {
            firstResultAt = Date()
            if let startedAt {
                addMetric("threshold→first result", Date().timeIntervalSince(startedAt))
            }
        }
        if result.isFinal {
            finalCount += 1
            finalText += text
            volatileText = ""
            if firstFinalAt == nil {
                firstFinalAt = Date()
                if let startedAt {
                    addMetric("threshold→first final", Date().timeIntervalSince(startedAt))
                }
            }
            log("FINAL[\(finalCount)] \(text)")
        } else {
            volatileText = text
            log("VOLATILE[\(resultCount)] \(text)")
        }
    }

    private func handleDetection(_ result: SpeechDetector.Result) {
        if result.speechDetected {
            if !hasSpeech {
                hasSpeech = true
                log("DETECTOR speech start \(result.range)")
            }
            detectorSpeech = true
        } else if detectorSpeech {
            detectorSpeech = false
            log("DETECTOR silence \(result.range)")
        }
    }

    func finishRecognition(reason: String) async {
        guard recognitionPhase == "capturing" || recognitionPhase == "starting" else {
            log("FINISH ignored phase=\(recognitionPhase)")
            return
        }
        recognitionPhase = "finalizing"
        timerTask?.cancel()
        let finalizeStart = Date()
        stopAudio()
        inputContinuation?.finish()

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
                log("FINALIZE error=\(error)")
            }
            timeout.cancel()
        }

        try? await Task.sleep(for: .milliseconds(200))
        transcriptionTask?.cancel()
        detectionTask?.cancel()
        if let releaseAt {
            addMetric("release→finalized", Date().timeIntervalSince(releaseAt))
        } else {
            addMetric("finish→finalized", Date().timeIntervalSince(finalizeStart))
        }
        if let startedAt {
            addMetric("session total", Date().timeIntervalSince(startedAt))
        }
        let text = finalText + (volatileText.isEmpty ? "" : " [volatile: \(volatileText)]")
        log("FINALIZED reason=\(reason) final=\(text)")
        recognitionPhase = "finished"
        cleanup()
    }

    func cancelRecognition() async {
        guard isActive else {
            log("CANCEL ignored phase=\(recognitionPhase)")
            return
        }
        recognitionPhase = "cancelling"
        timerTask?.cancel()
        stopAudio()
        inputContinuation?.finish()
        await analyzer?.cancelAndFinishNow()
        transcriptionTask?.cancel()
        detectionTask?.cancel()
        log("CANCELLED")
        recognitionPhase = "cancelled"
        cleanup()
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
            log("audio session deactivate=\(error)")
        }
    }

    private func cleanup() {
        transcriber = nil
        detector = nil
        analyzer = nil
        inputContinuation = nil
        transcriptionTask = nil
        detectionTask = nil
        hasSpeech = false
        detectorSpeech = false
        timerTask = nil
    }

    func log(_ message: String) {
        let line = "[\(Self.formatter.string(from: Date()))] \(message)"
        print(line)
        logger.info("\(line, privacy: .public)")
        logs.append(line)
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
    }

    private func addMetric(_ name: String, _ seconds: TimeInterval) {
        let line = "\(name): \(ms(seconds))"
        metrics.append(line)
        log("METRIC \(line)")
    }

    private func ms(_ seconds: TimeInterval) -> String {
        "\(Int((seconds * 1000).rounded()))ms"
    }

    private func statusText(_ status: AssetInventory.Status) -> String {
        switch status {
        case .unsupported: "unsupported"
        case .downloading: "downloading"
        case .supported: "supported"
        case .installed: "installed"
        @unknown default: "unknown"
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

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

    func copyLogs() {
        UIPasteboard.general.string = logs.joined(separator: "\n")
        log("logs copied")
    }

    func clearLogs() {
        logs.removeAll()
        metrics.removeAll()
        log("logs cleared")
    }
}

private enum SpikeError: LocalizedError {
    case noLocale
    case noInputFormat

    var errorDescription: String? {
        switch self {
        case .noLocale: "zh_CN not supported"
        case .noInputFormat: "input node format invalid"
        }
    }
}

struct VoiceSpikeView: View {
    @StateObject private var model = VoiceSpikeModel()
    @Environment(\.scenePhase) private var scenePhase
    let onExit: () -> Void

    private var autoPrepare: Bool {
        ProcessInfo.processInfo.arguments.contains("-VoiceSpikeAuto")
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    capabilityCard
                    gestureCard
                    recognitionCard
                    metricsCard
                    logCard
                }
                .padding(16)
                .padding(.bottom, 200)
            }

            if model.showOverlay && (model.holding || model.isActive) {
                listeningOverlay
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .onAppear { model.log("OVERLAY appeared") }
                    .onDisappear { model.log("OVERLAY removed") }
            }

            VStack {
                Spacer()
                holdArea
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 18)
                    .frame(maxWidth: .infinity)
                    .background(Palette.background)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Palette.border)
                            .frame(height: 0.5)
                    }
            }
        }
        .onAppear { model.onAppear(autoPrepare: autoPrepare) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                model.cancelActive()
            }
        }
        .onDisappear { model.cancelActive() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Phase 0 · 语音记账验证")
                    .font(.system(size: 20, weight: .semibold))
                Text("松手即停 / 非模态浮层 / zh_CN")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondary)
            }
            Spacer()
            Button("返回 App") {
                model.cancelActive()
                onExit()
            }
            .font(.system(size: 14))
            .foregroundStyle(Palette.primary)
        }
    }

    private var capabilityCard: some View {
        card("能力检查") {
            row("SpeechTranscriber", model.speechAvailable ? "available" : "unavailable")
            row("supportedLocales", "\(model.supportedLocaleCount)")
            row("zh_CN", model.localeSupported ? "supported · \(model.localeID)" : "unsupported")
            row("模型状态", model.assetStatus)
            row("麦克风权限", model.micPermission)
            row("可以录音", model.canRecord ? "YES" : "NO")
            if model.isPreparing {
                ProgressView(value: model.prepareProgress)
                Text("准备中 \(Int(model.prepareProgress * 100))%")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondary)
            }
            HStack(spacing: 8) {
                smallButton("一键准备") { Task { await model.prepareAll() } }
                smallButton("请求权限") { Task { await model.requestMicPermission() } }
                smallButton("准备模型") { Task { await model.prepareAssets() } }
            }
            if model.micPermission == "denied" {
                smallButton("打开设置") { model.openSettings() }
            }
        }
    }

    private var gestureCard: some View {
        card("手势") {
            row("phase", model.gesturePhase)
            row("holding", model.holding ? "true" : "false")
            row("cancelArmed", model.cancelArmed ? "true" : "false")
            row("translationY", String(format: "%.1f", model.translationY))
            row("duration", String(format: "%.2fs", model.gestureDuration))
            Toggle("显示非模态浮层", isOn: $model.showOverlay)
                .font(.system(size: 14))
            HStack(spacing: 8) {
                smallButton("模拟系统取消") { model.cancelActive() }
                smallButton("清空日志") { model.clearLogs() }
                smallButton("复制日志") { model.copyLogs() }
            }
        }
    }

    private var recognitionCard: some View {
        card("识别") {
            row("phase", model.recognitionPhase)
            row("elapsed", String(format: "%.1fs", model.elapsed))
            row("level", String(format: "%.3f", model.level))
            row("detectorSpeech", model.detectorSpeech ? "true" : "false")
            VStack(alignment: .leading, spacing: 4) {
                Text("final").font(.system(size: 14)).foregroundStyle(Palette.secondary)
                Text(model.finalText.isEmpty ? "—" : model.finalText)
                    .font(.system(size: 15))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("volatile").font(.system(size: 14)).foregroundStyle(Palette.secondary)
                Text(model.volatileText.isEmpty ? "—" : model.volatileText)
                    .font(.system(size: 15))
            }
        }
    }

    private var metricsCard: some View {
        card("指标") {
            if model.metrics.isEmpty {
                Text("—").font(.system(size: 14)).foregroundStyle(Palette.secondary)
            } else {
                ForEach(Array(model.metrics.enumerated()), id: \.offset) { _, metric in
                    Text(metric)
                        .font(.system(size: 14, design: .monospaced))
                }
            }
        }
    }

    private var logCard: some View {
        card("日志（\(model.logs.count)）") {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.logs.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: 240)
        }
    }

    private var listeningOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.12).ignoresSafeArea()

            VStack(spacing: 12) {
                HStack {
                    Circle()
                        .fill(model.cancelArmed ? Color.red : Color.green)
                        .frame(width: 8, height: 8)
                    Text(overlayTitle)
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                    Text(String(format: "%.1fs", model.elapsed))
                        .font(.system(size: 14).monospacedDigit())
                        .foregroundStyle(Palette.secondary)
                }

                HStack(alignment: .center, spacing: 4) {
                    ForEach(0..<15, id: \.self) { index in
                        Capsule()
                            .fill(index.isMultiple(of: 2) ? Palette.primary : Palette.primary.opacity(0.5))
                            .frame(
                                width: 4,
                                height: max(6, CGFloat(model.level) * 42 * CGFloat((index % 5) + 1) / 5)
                            )
                    }
                }
                .frame(height: 44)

                Text(displayText)
                    .font(.system(size: 16))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(model.cancelArmed ? "松开取消" : "松开结束 · 上滑取消")
                    .font(.system(size: 14))
                    .foregroundStyle(model.cancelArmed ? Color.red : Palette.secondary)
            }
            .padding(16)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Palette.border, lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 170)
        }
    }

    private var holdArea: some View {
        VStack(spacing: 8) {
            Text(holdHint)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(model.cancelArmed ? Color.red : Palette.secondary)

            ZStack {
                Circle()
                    .fill(model.holding ? (model.cancelArmed ? Color.red : Palette.primary.opacity(0.85)) : Palette.primary)
                    .frame(width: 118, height: 118)
                    .shadow(color: Palette.primary.opacity(0.25), radius: 12, y: 6)
                Image(systemName: model.holding ? "waveform" : "mic.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { model.gestureChanged($0.translation) }
                    .onEnded { _ in model.gestureEnded() }
            )
            .accessibilityLabel("按住说话，松手结束")

            Text("按住浮层出现后继续按住，再松开；观察日志是否有 RELEASE")
                .font(.system(size: 13))
                .foregroundStyle(Palette.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
    }

    private var overlayTitle: String {
        if model.cancelArmed { return "松开取消" }
        if model.recognitionPhase == "finalizing" { return "正在生成账单…" }
        return "正在聆听 · 松开结束"
    }

    private var displayText: String {
        if !model.volatileText.isEmpty { return model.volatileText }
        if !model.finalText.isEmpty { return model.finalText }
        return model.recognitionPhase == "finalizing" ? "正在处理最后的语音…" : "等待语音…"
    }

    private var holdHint: String {
        if model.cancelArmed { return "松开取消" }
        if model.holding { return "松开结束 · 上滑取消" }
        return "按住说话 · 松手停止"
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(key)
                .font(.system(size: 14))
                .foregroundStyle(Palette.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.trailing)
        }
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 14))
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Palette.border, lineWidth: 0.5)
        )
    }
}
#endif
