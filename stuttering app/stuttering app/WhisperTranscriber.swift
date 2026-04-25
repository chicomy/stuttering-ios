//
//  WhisperTranscriber.swift
//  stuttering app
//
//  Created by Codex on 4/17/26.
//
//  Thin wrapper around WhisperKit that produces word-level timestamps
//  for downstream disfluency detection (Phase 1: file-mode transcription
//  only — streaming comes in Phase 3).
//

import Foundation
import WhisperKit
import os

/// Word-level timing produced by the on-device ASR. Decoupled from
/// WhisperKit's own `WordTiming` so callers don't have to import the
/// package transitively.
struct TranscribedWord: Sendable, Equatable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
    let probability: Double

    var duration: TimeInterval { max(0, end - start) }
}

enum WhisperTranscriberError: LocalizedError {
    case pipelineUnavailable
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .pipelineUnavailable:
            return "The on-device transcription model is not ready yet."
        case .transcriptionFailed(let message):
            return message
        }
    }
}

/// Model variant. `tinyEn` (~40MB) is the default — fast enough for
/// iterative rule tuning in Phase 1/2 and good enough for word boundaries
/// on English samples. Swap to `base` (~150MB) once we start benchmarking
/// against real recordings, or to `baseMultilingual` if Mandarin support
/// is needed.
enum WhisperModelVariant: String, Sendable {
    case tinyEn = "openai_whisper-tiny.en"
    case base   = "openai_whisper-base"

    static let `default`: WhisperModelVariant = .tinyEn
}

/// Actor-isolated wrapper around a `WhisperKit` pipeline. Safe to share
/// across the app; warmup is idempotent.
actor WhisperTranscriber {
    private static let logger = Logger(
        subsystem: "appolio.stuttering-app",
        category: "whisper"
    )

    private let variant: WhisperModelVariant
    private var pipeline: WhisperKit?
    private var warmupTask: Task<Void, Error>?

    init(variant: WhisperModelVariant = .default) {
        self.variant = variant
    }

    /// Load (and download on first run) the on-device model. Concurrent
    /// callers coalesce onto a single in-flight warmup.
    func warmup() async throws {
        if pipeline != nil { return }

        if let existing = warmupTask {
            try await existing.value
            return
        }

        let variant = self.variant
        let task = Task { [weak self] in
            Self.logger.info("Warming up WhisperKit (variant=\(variant.rawValue, privacy: .public))")

            // Prefer the model folder bundled inside the .app — this lets the
            // app run on devices that can't reach huggingface.co (mainland
            // China without a VPN, locked-down corporate networks, etc.).
            //
            // Two layouts are supported:
            //   1. Proper folder reference — files live under a sub-folder
            //      `App.app/openai_whisper-tiny.en/AudioEncoder.mlmodelc/…`
            //   2. Xcode auto-synced group — Xcode flattens the wrapper
            //      directory but keeps the .mlmodelc bundles, so files end up
            //      directly at `App.app/AudioEncoder.mlmodelc/…`. In that
            //      case `Bundle.main.bundleURL` itself IS the model folder.
            //
            // Falls back to a network download if neither layout is present.
            let bundledModelFolder = Self.findBundledModelFolder(variant: variant)
            if let bundledModelFolder {
                Self.logger.info(
                    "Using bundled model folder at \(bundledModelFolder.path, privacy: .public)"
                )
            } else {
                Self.logger.info("No bundled model found — will download from HuggingFace")
            }

            let config = WhisperKitConfig(
                model: variant.rawValue,
                modelFolder: bundledModelFolder?.path,
                tokenizerFolder: bundledModelFolder, // tokenizer files live alongside the model
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: bundledModelFolder == nil
            )
            do {
                let pipe = try await WhisperKit(config)
                await self?.assign(pipeline: pipe)
                Self.logger.info("WhisperKit ready")
            } catch {
                Self.logger.error("WhisperKit load failed: \(error.localizedDescription, privacy: .public)")
                throw WhisperTranscriberError.transcriptionFailed(error.localizedDescription)
            }
        }
        warmupTask = task

        do {
            try await task.value
        } catch {
            warmupTask = nil
            throw error
        }
        warmupTask = nil
    }

    /// One-shot transcription for File mode. Returns word-level timings in
    /// chronological order. Throws if the model can't be loaded or the
    /// audio can't be decoded.
    func transcribeFile(url: URL) async throws -> [TranscribedWord] {
        try await warmup()
        guard let pipeline else { throw WhisperTranscriberError.pipelineUnavailable }

        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            withoutTimestamps: false,
            wordTimestamps: true
        )

        let results: [TranscriptionResult]
        do {
            results = try await pipeline.transcribe(
                audioPath: url.path(percentEncoded: false),
                decodeOptions: options
            )
        } catch {
            throw WhisperTranscriberError.transcriptionFailed(error.localizedDescription)
        }

        let words = Self.flattenWords(from: results)
        Self.logger.info(
            "Transcribed \(words.count, privacy: .public) words from \(url.lastPathComponent, privacy: .public)"
        )
        return words
    }

    /// Streaming-friendly variant: transcribe a raw 16kHz mono float32 buffer.
    /// The caller is responsible for windowing (typical: last 4–6 seconds of
    /// audio) and for deduplicating words across successive calls.
    func transcribeSamples(_ samples: [Float]) async throws -> [TranscribedWord] {
        try await warmup()
        guard let pipeline else { throw WhisperTranscriberError.pipelineUnavailable }
        guard samples.count > 1600 else { return [] } // <0.1s isn't useful

        // Whisper expects 30s chunks and pads the tail with zeros. On a
        // short streaming window that silent padding trips the default
        // noSpeechThreshold (0.6) and returns nothing at all — hence
        // we loosen it here. `skipSpecialTokens` drops <|blank|>-style
        // markers before they reach the transcript.
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: "en",
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: true,
            suppressBlank: true,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.5,
            noSpeechThreshold: 0.3
        )

        let results: [TranscriptionResult]
        do {
            results = try await pipeline.transcribe(
                audioArray: samples,
                decodeOptions: options
            )
        } catch {
            throw WhisperTranscriberError.transcriptionFailed(error.localizedDescription)
        }

        return Self.flattenWords(from: results)
    }

    // MARK: - Internal

    private func assign(pipeline: WhisperKit) {
        self.pipeline = pipeline
    }

    /// Locate the bundled CoreML model. Sentinel for "is this a model
    /// folder?" is the presence of `AudioEncoder.mlmodelc`, which all
    /// WhisperKit variants ship.
    private static func findBundledModelFolder(variant: WhisperModelVariant) -> URL? {
        let fm = FileManager.default
        let sentinel = "AudioEncoder.mlmodelc"

        // Layout 1: proper folder reference — bundle has a sub-folder
        // named after the variant.
        if let nested = Bundle.main.url(forResource: variant.rawValue, withExtension: nil),
           fm.fileExists(atPath: nested.appendingPathComponent(sentinel).path) {
            return nested
        }

        // Layout 2: Xcode auto-synced group flattened the wrapper, but
        // the .mlmodelc bundles survived at the .app root.
        let bundleRoot = Bundle.main.bundleURL
        if fm.fileExists(atPath: bundleRoot.appendingPathComponent(sentinel).path) {
            return bundleRoot
        }

        return nil
    }

    /// Whisper decoders occasionally emit internal markers like
    /// `[BLANK_AUDIO]`, `[MUSIC]`, `[NOISE]`, `(silence)`, or raw
    /// special tokens (`<|nospeech|>`). Whisper's BPE tokenizer can
    /// also split these across multiple word-timings (e.g. `[BLANK`,
    /// `_AUDIO]`), so we also match on keyword substrings and any
    /// fragment that contains bracket punctuation — none of which ever
    /// appears in real speech.
    private static let nonSpeechKeywords: [String] = [
        "BLANK_AUDIO", "BLANK AUDIO", "NO_SPEECH", "NOSPEECH",
        "MUSIC", "NOISE", "SILENCE", "INAUDIBLE", "APPLAUSE",
        "LAUGHTER", "CROSSTALK", "BACKGROUND"
    ]

    private static func isNonSpeechMarker(_ text: String) -> Bool {
        let t = text.uppercased()
        // Whole bracketed markers.
        if t.hasPrefix("<|") && t.hasSuffix("|>") { return true }
        // Fragments that contain bracket punctuation — real speech
        // doesn't include `[`, `]`, or `|` characters.
        if t.contains("[") || t.contains("]") || t.contains("|") { return true }
        // Keyword match — catches BPE-split fragments like "BLANK" +
        // "_AUDIO" where the brackets landed on a neighbor.
        for kw in nonSpeechKeywords where t.contains(kw) { return true }
        return false
    }

    private static func flattenWords(from results: [TranscriptionResult]) -> [TranscribedWord] {
        var out: [TranscribedWord] = []
        for result in results {
            for segment in result.segments {
                guard let wordTimings = segment.words else { continue }
                for w in wordTimings {
                    let trimmed = w.word.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { continue }
                    guard !isNonSpeechMarker(trimmed) else { continue }
                    out.append(TranscribedWord(
                        text: trimmed,
                        start: TimeInterval(w.start),
                        end: TimeInterval(w.end),
                        probability: Double(w.probability)
                    ))
                }
            }
        }
        return out.sorted { $0.start < $1.start }
    }
}
