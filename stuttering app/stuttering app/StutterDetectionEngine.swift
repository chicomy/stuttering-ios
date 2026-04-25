//
//  StutterDetectionEngine.swift
//  stuttering app
//
//  Created by Codex on 4/3/26.
//

import Foundation

struct StutterDetectionReport: Sendable {
    let likelyContainsStuttering: Bool
    let confidence: Double
    let analyzedDuration: TimeInterval
    let speechDuration: TimeInterval
    let silenceDuration: TimeInterval
    let longestSpeechRun: TimeInterval
    let rapidRestartCount: Int
    let elevatedTensionMoments: Int
    let summary: String
    let events: [DisfluencyEvent]

    nonisolated init(
        likelyContainsStuttering: Bool,
        confidence: Double,
        analyzedDuration: TimeInterval,
        speechDuration: TimeInterval,
        silenceDuration: TimeInterval,
        longestSpeechRun: TimeInterval,
        rapidRestartCount: Int,
        elevatedTensionMoments: Int,
        summary: String,
        events: [DisfluencyEvent] = []
    ) {
        self.likelyContainsStuttering = likelyContainsStuttering
        self.confidence = confidence
        self.analyzedDuration = analyzedDuration
        self.speechDuration = speechDuration
        self.silenceDuration = silenceDuration
        self.longestSpeechRun = longestSpeechRun
        self.rapidRestartCount = rapidRestartCount
        self.elevatedTensionMoments = elevatedTensionMoments
        self.summary = summary
        self.events = events
    }

    /// Non-mutating helper used when the acoustic path finishes first and
    /// the text-layer events arrive later.
    nonisolated func with(events: [DisfluencyEvent]) -> StutterDetectionReport {
        StutterDetectionReport(
            likelyContainsStuttering: likelyContainsStuttering,
            confidence: confidence,
            analyzedDuration: analyzedDuration,
            speechDuration: speechDuration,
            silenceDuration: silenceDuration,
            longestSpeechRun: longestSpeechRun,
            rapidRestartCount: rapidRestartCount,
            elevatedTensionMoments: elevatedTensionMoments,
            summary: summary,
            events: events
        )
    }

    var eventCountsByKind: [DisfluencyKind: Int] {
        var counts: [DisfluencyKind: Int] = [:]
        for e in events { counts[e.kind, default: 0] += 1 }
        return counts
    }

    static let empty = StutterDetectionReport(
        likelyContainsStuttering: false,
        confidence: 0,
        analyzedDuration: 0,
        speechDuration: 0,
        silenceDuration: 0,
        longestSpeechRun: 0,
        rapidRestartCount: 0,
        elevatedTensionMoments: 0,
        summary: "No audio analyzed yet.",
        events: []
    )
}

struct StutterDetectionEngine: Sendable {
    private let speechThreshold: Float = 0.015
    private let softSpeechThreshold: Float = 0.009
    private let elevatedZeroCrossingRate: Float = 0.16
    private let sustainedSpeechLimit: TimeInterval = 2.8
    private let shortBurstLimit: TimeInterval = 0.38
    private let shortPauseLimit: TimeInterval = 0.24
    private let recoverySilenceLimit: TimeInterval = 0.85

    private var speakingDuration: TimeInterval = 0
    private var silenceDuration: TimeInterval = 0
    private var previousSpeechDuration: TimeInterval = 0
    private var previousSilenceDuration: TimeInterval = 0
    private var longestSpeechRun: TimeInterval = 0
    private var rapidRestartCount = 0
    private var elevatedTensionMoments = 0
    private var totalDuration: TimeInterval = 0
    private var totalSpeechDuration: TimeInterval = 0
    private var totalSilenceDuration: TimeInterval = 0
    private var latestConfidence: Double = 0
    private var wasSpeechDetected = false

    nonisolated init() {}

    nonisolated mutating func reset() {
        speakingDuration = 0
        silenceDuration = 0
        previousSpeechDuration = 0
        previousSilenceDuration = 0
        longestSpeechRun = 0
        rapidRestartCount = 0
        elevatedTensionMoments = 0
        totalDuration = 0
        totalSpeechDuration = 0
        totalSilenceDuration = 0
        latestConfidence = 0
        wasSpeechDetected = false
    }

    nonisolated mutating func process(_ frame: AudioFrameFeatures) -> StutterDetectionReport {
        totalDuration += frame.duration

        let isSpeechDetected = frame.rms > speechThreshold || (frame.rms > softSpeechThreshold && frame.zeroCrossingRate > elevatedZeroCrossingRate)

        if isSpeechDetected {
            speakingDuration += frame.duration
            totalSpeechDuration += frame.duration

            if !wasSpeechDetected,
               previousSpeechDuration > 0,
               previousSpeechDuration < shortBurstLimit,
               previousSilenceDuration < shortPauseLimit {
                rapidRestartCount += 1
            }

            silenceDuration = 0
            longestSpeechRun = max(longestSpeechRun, speakingDuration)
        } else {
            silenceDuration += frame.duration
            totalSilenceDuration += frame.duration

            if wasSpeechDetected {
                previousSpeechDuration = speakingDuration
                speakingDuration = 0
            }
            previousSilenceDuration = silenceDuration
        }

        wasSpeechDetected = isSpeechDetected

        let sustainedComponent = normalized(value: speakingDuration, start: 1.6, end: sustainedSpeechLimit)
        let restartComponent = normalized(value: Double(rapidRestartCount), start: 1, end: 4)
        let agitationComponent = normalized(value: Double(frame.zeroCrossingRate), start: 0.10, end: Double(elevatedZeroCrossingRate))
        let weakRecoveryPenalty = normalized(value: recoverySilenceLimit - min(silenceDuration, recoverySilenceLimit), start: 0.15, end: recoverySilenceLimit)
        let confidence = min(1.0, sustainedComponent * 0.45 + restartComponent * 0.30 + agitationComponent * 0.15 + weakRecoveryPenalty * 0.10)

        if confidence >= 0.62 && isSpeechDetected {
            elevatedTensionMoments += 1
        }

        latestConfidence = confidence
        return makeReport()
    }

    nonisolated func finalReport() -> StutterDetectionReport {
        makeReport()
    }

    private nonisolated func makeReport() -> StutterDetectionReport {
        let containsSignal = longestSpeechRun >= sustainedSpeechLimit || rapidRestartCount >= 3 || elevatedTensionMoments >= 4
        let summary: String

        if totalDuration < 1 {
            summary = "The sample is too short to judge. Record a little longer for a more stable estimate."
        } else if containsSignal {
            summary = "Possible stuttering-like disfluency detected from repeated restarts, extended speech runs, or sustained tension. This is a lightweight estimate, not a diagnosis."
        } else {
            summary = "No strong stuttering-like pattern was detected in this sample. This is a lightweight estimate, not a diagnosis."
        }

        return StutterDetectionReport(
            likelyContainsStuttering: containsSignal,
            confidence: latestConfidence,
            analyzedDuration: totalDuration,
            speechDuration: totalSpeechDuration,
            silenceDuration: totalSilenceDuration,
            longestSpeechRun: longestSpeechRun,
            rapidRestartCount: rapidRestartCount,
            elevatedTensionMoments: elevatedTensionMoments,
            summary: summary
        )
    }

    private nonisolated func normalized(value: Double, start: Double, end: Double) -> Double {
        guard end > start else { return 0 }
        return min(max((value - start) / (end - start), 0), 1)
    }
}
