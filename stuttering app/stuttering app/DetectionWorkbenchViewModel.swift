//
//  DetectionWorkbenchViewModel.swift
//  stuttering app
//
//  Created by Codex on 4/3/26.
//

import Foundation
import Combine
import os

enum DetectionInputMode: String, CaseIterable, Identifiable {
    case live = "Live"
    case file = "Audio File"

    var id: String { rawValue }
}

/// User-facing status for the on-device Whisper pipeline. Drives the
/// loading strip in File mode so the user sees *something* during the
/// first-run model download (~40MB) and the multi-second transcription.
enum WhisperStatus: Equatable {
    case idle
    case preparingModel      // downloading + loading CoreML weights
    case transcribing        // Whisper is running on the audio
    case detecting           // rule-based disfluency pass
    case ready
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .preparingModel, .transcribing, .detecting: return true
        default: return false
        }
    }

    var message: String? {
        switch self {
        case .idle, .ready: return nil
        case .preparingModel: return "Preparing on-device model… (first run downloads ~40MB)"
        case .transcribing:   return "Transcribing audio…"
        case .detecting:      return "Analyzing speech patterns…"
        case .failed(let m):  return "Model error: \(m)"
        }
    }
}

@MainActor
final class DetectionWorkbenchViewModel: ObservableObject {
    @Published var selectedMode: DetectionInputMode = .live
    @Published private(set) var liveMonitoringState: AudioMonitoringState = .idle
    @Published private(set) var liveReport: StutterDetectionReport = .empty
    @Published private(set) var liveAudioLevel: Double = 0
    @Published private(set) var fileReport: StutterDetectionReport = .empty
    @Published private(set) var selectedFileName: String?
    @Published private(set) var isAnalyzingFile = false
    @Published private(set) var whisperStatus: WhisperStatus = .idle

    /// Phase 3: rolling transcript for Live mode. Most recent tokens are
    /// at the tail. The view renders silence gaps implicitly from token
    /// timestamps.
    @Published private(set) var liveTranscript: [LiveTranscriptToken] = []

    /// Phase 4: full tokenized transcript for File mode, colored with the
    /// same kind palette as the live strip.
    @Published private(set) var fileTranscript: [LiveTranscriptToken] = []

    private let liveMonitor = PracticeAudioMonitor()
    private let fileAnalyzer = AudioFileAnalyzer()
    private var liveEngine = StutterDetectionEngine()

    // Phase 1: text-layer transcription side-channel. Runs alongside the
    // existing acoustic analysis; results are currently logged to Console
    // for rule-tuning, not yet fed back into the report.
    private let transcriber = WhisperTranscriber()
    private lazy var streamer = LiveWhisperStreamer(transcriber: transcriber)

    /// Cap on how many tokens we keep in `liveTranscript`; oldest roll
    /// off so the strip stays snappy.
    private let maxLiveTranscriptTokens = 48
    private static let whisperLog = Logger(
        subsystem: "appolio.stuttering-app",
        category: "whisper.viewmodel"
    )

    init() {
        // Kick off model warmup immediately so the first file import
        // doesn't eat the ~40MB download cost in the foreground.
        Task { [weak self, transcriber] in
            await MainActor.run { self?.whisperStatus = .preparingModel }
            do {
                try await transcriber.warmup()
                await MainActor.run {
                    if self?.whisperStatus == .preparingModel {
                        self?.whisperStatus = .ready
                    }
                }
            } catch {
                await MainActor.run {
                    self?.whisperStatus = .failed(error.localizedDescription)
                }
            }
        }
    }

    func startLiveAnalysis() {
        liveEngine.reset()
        liveReport = .empty
        liveAudioLevel = 0
        liveTranscript = []

        // Phase 3: start the streaming transcript alongside the acoustic
        // path. `streamer` handles the resampling + rolling window; the
        // mic tap below feeds it PCM from the shared AVAudioEngine.
        streamer.start(
            onToken: { [weak self] token in
                guard let self else { return }
                self.liveTranscript.append(token)
                if self.liveTranscript.count > self.maxLiveTranscriptTokens {
                    self.liveTranscript.removeFirst(
                        self.liveTranscript.count - self.maxLiveTranscriptTokens
                    )
                }
            },
            onSilence: { _ in
                // Silence is already reconstructable from token gaps in
                // the view; we don't store it separately.
            }
        )

        liveMonitor.start(
            onFrame: { [weak self] frame in
                guard let self else { return }
                let normalizedLevel = min(max((Double(frame.rms) - 0.003) / 0.05, 0), 1)
                self.liveAudioLevel = self.liveAudioLevel * 0.58 + normalizedLevel * 0.42
                self.liveReport = self.liveEngine.process(frame)
            },
            onStateChange: { [weak self] state in
                guard let self else { return }
                self.liveMonitoringState = state
            },
            onPCM: { [streamer] buffer, format in
                streamer.feed(buffer: buffer, format: format)
            }
        )
    }

    func stopLiveAnalysis() {
        liveMonitor.stop()
        streamer.stop()
        liveReport = liveEngine.finalReport()
        liveAudioLevel = 0
        liveMonitoringState = .idle
    }

    func finishLiveAnalysis() -> StutterDetectionReport {
        liveMonitor.stop()
        streamer.stop()
        let report = liveEngine.finalReport()
        liveReport = report
        liveAudioLevel = 0
        liveMonitoringState = .idle
        return report
    }

    func resetLiveSession() {
        liveMonitor.stop()
        streamer.stop()
        liveEngine.reset()
        liveReport = .empty
        liveAudioLevel = 0
        liveMonitoringState = .idle
        liveTranscript = []
    }

    func triggerDemoPulse() {
        liveEngine.reset()
        liveAudioLevel = 0.72
        liveReport = liveEngine.process(AudioFrameFeatures(rms: 0.046, zeroCrossingRate: 0.19, duration: 0.24))
        liveReport = liveEngine.process(AudioFrameFeatures(rms: 0.041, zeroCrossingRate: 0.18, duration: 0.27))
        liveReport = liveEngine.process(AudioFrameFeatures(rms: 0.043, zeroCrossingRate: 0.20, duration: 0.22))
    }

    #if DEBUG
    /// Phase 1 dev shortcut: run the bundled `sample.mp3` through the same
    /// pipeline as the file picker, so you can iterate on Whisper rules
    /// without touching the Files app.
    func analyzeBundledSample(named name: String = "sample", ext: String = "mp3") {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            Self.whisperLog.error("Bundled sample \(name, privacy: .public).\(ext, privacy: .public) not found")
            return
        }
        analyzeFile(at: url)
    }
    #endif

    /// Map Whisper words + detector events into classified transcript tokens.
    /// Used by File mode to render the same color-coded transcript as the
    /// live streaming strip. `allEvents` is the unfiltered detector output
    /// so even soft signals can color a word — the pill summary card
    /// continues to use the confidence-filtered set.
    nonisolated private static func buildTokens(
        words: [TranscribedWord],
        events: [DisfluencyEvent]
    ) -> [LiveTranscriptToken] {
        words.map { w in
            var kind: LiveTokenKind = .normal
            for e in events where e.start < w.end + 0.05 && e.end > w.start - 0.05 {
                switch e.kind {
                case .prolongation:     kind = .prolongation
                case .interjection:     kind = .interjection
                case .wordRepetition,
                     .soundRepetition:  kind = .wordRepetition
                case .block:            kind = .block
                }
                break
            }
            return LiveTranscriptToken(
                id: UUID(),
                text: w.text,
                start: w.start,
                end: w.end,
                kind: kind,
                confidence: w.probability
            )
        }
    }

    func analyzeFile(at url: URL) {
        selectedFileName = url.lastPathComponent
        isAnalyzingFile = true
        fileTranscript = []
        let analyzer = fileAnalyzer

        Task {
            let accessedResource = url.startAccessingSecurityScopedResource()
            defer {
                if accessedResource {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let report = try await Task.detached(priority: .userInitiated) {
                    try analyzer.analyze(url: url)
                }.value

                await MainActor.run {
                    self.fileReport = report
                    self.isAnalyzingFile = false
                }
            } catch {
                await MainActor.run {
                    self.fileReport = StutterDetectionReport(
                        likelyContainsStuttering: false,
                        confidence: 0,
                        analyzedDuration: 0,
                        speechDuration: 0,
                        silenceDuration: 0,
                        longestSpeechRun: 0,
                        rapidRestartCount: 0,
                        elevatedTensionMoments: 0,
                        summary: error.localizedDescription
                    )
                    self.isAnalyzingFile = false
                }
            }
        }

        // Phase 1 validation side-channel: kick off Whisper transcription
        // in parallel and dump word-level timings to Console. Failure here
        // is non-fatal — the acoustic path above still produces a report.
        Task { [weak self, transcriber] in
            let accessedResource = url.startAccessingSecurityScopedResource()
            defer {
                if accessedResource {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            // Step 1: ensure model is loaded (may be a no-op if warmup
            // from init already finished). Surface the download phase
            // to the UI so first-run users see progress.
            await MainActor.run {
                if self?.whisperStatus != .ready {
                    self?.whisperStatus = .preparingModel
                }
            }

            do {
                await MainActor.run { self?.whisperStatus = .transcribing }
                let words = try await transcriber.transcribeFile(url: url)
                await MainActor.run { self?.whisperStatus = .detecting }
                let filename = url.lastPathComponent
                Self.whisperLog.info(
                    "🎤 Whisper returned \(words.count, privacy: .public) words for \(filename, privacy: .public)"
                )
                for w in words.prefix(80) {
                    let line = String(
                        format: "   [%6.2fs → %6.2fs]  %@  (p=%.2f, dur=%.2fs)",
                        w.start, w.end, w.text, w.probability, w.duration
                    )
                    Self.whisperLog.info("\(line, privacy: .public)")
                }
                if words.count > 80 {
                    Self.whisperLog.info("   … (\(words.count - 80, privacy: .public) more words truncated)")
                }

                // Phase 2: run rule-based detector and log events. Filter
                // out low-confidence noise (e.g. stressed one-letter words
                // just over the 0.40s floor). Phase 4: merge the surviving
                // events into the existing fileReport so the UI can render
                // them.
                let detector = DisfluencyDetector()
                let allEvents = detector.detect(in: words)
                let events = allEvents.filter { $0.confidence >= 0.15 }
                Self.whisperLog.info(
                    "🚨 Detected \(events.count, privacy: .public) disfluency events (filtered from \(allEvents.count, privacy: .public))"
                )
                let tokens = Self.buildTokens(words: words, events: allEvents)
                await MainActor.run {
                    guard let self else { return }
                    self.fileReport = self.fileReport.with(events: events)
                    self.fileTranscript = tokens
                    self.whisperStatus = .ready
                }
                for e in events {
                    let note = e.note ?? "-"
                    let line = String(
                        format: "   [%6.2fs → %6.2fs]  %-15@  \"%@\"  (conf=%.2f, %@)",
                        e.start, e.end, e.kind.rawValue as NSString, e.text, e.confidence, note
                    )
                    Self.whisperLog.info("\(line, privacy: .public)")
                }
            } catch {
                Self.whisperLog.error(
                    "Whisper transcription failed: \(error.localizedDescription, privacy: .public)"
                )
                await MainActor.run {
                    self?.whisperStatus = .failed(error.localizedDescription)
                }
            }
        }
    }
}
