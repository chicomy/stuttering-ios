//
//  LiveWhisperStreamer.swift
//  stuttering app
//
//  Created by Codex on 4/17/26.
//
//  Phase 3: streaming ASR. Resamples mic audio to 16kHz mono float, holds
//  a rolling window, and periodically re-transcribes it via WhisperKit.
//  New words are diffed against the prior pass and pushed back to the
//  caller as they appear, so the UI can render a live transcript.
//

import Foundation
import AVFoundation
import os

/// Live-only classification for a transcribed token. Mirrors the file-mode
/// DisfluencyKind but adds `normal` for plain speech so the UI can color
/// every token on the transcript strip.
enum LiveTokenKind: Sendable {
    case normal
    case prolongation
    case interjection
    case wordRepetition
    case block          // preceded by a long silence gap
}

struct LiveTranscriptToken: Sendable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let start: TimeInterval
    let end: TimeInterval
    let kind: LiveTokenKind
    let confidence: Double
}

/// Owns the resampling + rolling buffer. Fed PCM from a mic tap; emits
/// newly-recognized tokens via `onToken` on the MainActor.
@MainActor
final class LiveWhisperStreamer {
    private static let logger = Logger(
        subsystem: "appolio.stuttering-app",
        category: "whisper.stream"
    )

    private let transcriber: WhisperTranscriber
    private let detector = DisfluencyDetector()

    /// 16kHz mono float samples. We keep up to `windowSeconds` of audio
    /// and feed it to Whisper each tick; Whisper re-transcribes the whole
    /// window and we dedupe via `committedEndTime`.
    private var sampleBuffer: [Float] = []
    private let targetSampleRate: Double = 16_000
    /// Whisper is built around 30s context; anything shorter causes the
    /// decoder to see heavy zero-padding and spuriously classify the
    /// whole frame as non-speech. 15s is a reasonable trade-off between
    /// latency and recognition stability on tinyEn.
    private let windowSeconds: Double = 15.0
    private let tickInterval: TimeInterval = 2.0

    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    /// Monotonic wall-clock offset at which `sampleBuffer[0]` begins. We
    /// map Whisper's per-call timestamps (which restart from 0 each tick)
    /// onto this so tokens stay in a single timeline.
    private var bufferStartTime: TimeInterval = 0
    private var totalSamplesAccepted: Int = 0

    /// End timestamp (within the rolling window) of the last token we've
    /// already emitted — anything earlier is suppressed as a re-emission.
    private var committedEndTime: TimeInterval = 0

    private var tickTask: Task<Void, Never>?
    private var isTranscribing = false

    private var onToken: ((LiveTranscriptToken) -> Void)?
    private var onSilence: ((TimeInterval) -> Void)?

    init(transcriber: WhisperTranscriber) {
        self.transcriber = transcriber
    }

    func start(
        onToken: @escaping (LiveTranscriptToken) -> Void,
        onSilence: @escaping (TimeInterval) -> Void
    ) {
        stop()
        self.onToken = onToken
        self.onSilence = onSilence
        sampleBuffer.removeAll(keepingCapacity: true)
        bufferStartTime = 0
        totalSamplesAccepted = 0
        committedEndTime = 0

        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(2_000_000_000)) // 2.0s
                await self?.tick()
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        onToken = nil
        onSilence = nil
        sampleBuffer.removeAll(keepingCapacity: false)
    }

    /// Called from the mic tap (audio thread). Resamples the buffer to
    /// 16kHz mono float32 and appends to the rolling window.
    nonisolated func feed(buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        guard let samples = Self.resample(buffer: buffer, sourceFormat: format, target: 16_000) else { return }
        Task { @MainActor [weak self] in
            self?.append(samples: samples)
        }
    }

    private func append(samples: [Float]) {
        sampleBuffer.append(contentsOf: samples)
        totalSamplesAccepted += samples.count

        let maxSamples = Int(windowSeconds * targetSampleRate)
        if sampleBuffer.count > maxSamples {
            let drop = sampleBuffer.count - maxSamples
            sampleBuffer.removeFirst(drop)
            // Advance the origin so downstream timestamps stay on one timeline.
            bufferStartTime += Double(drop) / targetSampleRate
            committedEndTime = max(0, committedEndTime - Double(drop) / targetSampleRate)
        }
    }

    private func tick() async {
        guard !isTranscribing else { return }
        let snapshot = sampleBuffer
        // Need at least ~2s of audio before asking Whisper — shorter
        // windows are mostly zero-padding and return noise.
        guard snapshot.count >= Int(targetSampleRate * 2) else { return }

        // Silence gate: if the whole window is below this RMS, skip the
        // Whisper call. Prevents the model from hallucinating words out
        // of room tone.
        let rms = Self.rms(of: snapshot)
        guard rms > 0.005 else {
            Self.logger.debug("Skipping tick — window is silent (rms=\(rms, privacy: .public))")
            return
        }

        let snapshotStart = bufferStartTime
        isTranscribing = true
        defer { isTranscribing = false }

        do {
            let words = try await transcriber.transcribeSamples(snapshot)
            guard !words.isEmpty else { return }

            // Keep only words whose END is past what we already emitted.
            // Whisper re-transcribes the full window each tick, so this
            // is how we avoid double-printing.
            let fresh = words.filter { $0.end > committedEndTime + 0.05 }
            guard !fresh.isEmpty else { return }

            // Classify via the same rule engine used in File mode — the
            // live window gives it enough context to flag prolongations
            // and repetitions; blocks get detected from gaps below.
            let detectorEvents = detector.detect(in: words)

            var lastEnd = committedEndTime
            for w in fresh {
                if let silence = silenceBefore(word: w, lastEnd: lastEnd), silence >= 0.4 {
                    onSilence?(silence)
                }
                lastEnd = w.end

                let kind = classify(word: w, events: detectorEvents)
                let token = LiveTranscriptToken(
                    id: UUID(),
                    text: w.text,
                    start: snapshotStart + w.start,
                    end: snapshotStart + w.end,
                    kind: kind,
                    confidence: w.probability
                )
                onToken?(token)
            }
            committedEndTime = fresh.last?.end ?? committedEndTime
        } catch {
            Self.logger.error("Stream tick failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func silenceBefore(word: TranscribedWord, lastEnd: TimeInterval) -> TimeInterval? {
        guard lastEnd > 0 else { return nil }
        let gap = word.start - lastEnd
        return gap > 0 ? gap : nil
    }

    private func classify(word: TranscribedWord, events: [DisfluencyEvent]) -> LiveTokenKind {
        // An event is "about" this word if their spans overlap.
        for e in events where e.start < word.end + 0.05 && e.end > word.start - 0.05 {
            switch e.kind {
            case .prolongation:     return .prolongation
            case .interjection:     return .interjection
            case .wordRepetition,
                 .soundRepetition:  return .wordRepetition
            case .block:            return .block
            }
        }
        return .normal
    }

    nonisolated private static func rms(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }

    // MARK: - Resampling

    nonisolated private static func resample(
        buffer: AVAudioPCMBuffer,
        sourceFormat: AVAudioFormat,
        target sampleRate: Double
    ) -> [Float]? {
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            return nil
        }
        // Default is `.normal`; `.max` uses a longer anti-aliasing
        // filter that matters when down-sampling 48kHz→16kHz for ASR.
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue

        let ratio = sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 16)
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inStatus in
            if supplied {
                inStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil else { return nil }
        guard let channelData = output.floatChannelData?.pointee else { return nil }
        let count = Int(output.frameLength)
        return Array(UnsafeBufferPointer(start: channelData, count: count))
    }
}
