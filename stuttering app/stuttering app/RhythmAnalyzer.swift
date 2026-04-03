//
//  RhythmAnalyzer.swift
//  stuttering app
//
//  Created by Codex on 4/3/26.
//

import Foundation

struct AudioFrameFeatures: Sendable {
    let rms: Float
    let zeroCrossingRate: Float
    let duration: TimeInterval

    nonisolated init(rms: Float, zeroCrossingRate: Float, duration: TimeInterval) {
        self.rms = rms
        self.zeroCrossingRate = zeroCrossingRate
        self.duration = duration
    }
}

struct RhythmAnalysisSnapshot {
    let isSpeechDetected: Bool
    let speakingDuration: TimeInterval
    let silenceDuration: TimeInterval
    let tensionScore: Double
    let rapidRestartCount: Int
    let recommendedMode: PracticeMode

    static let idle = RhythmAnalysisSnapshot(
        isSpeechDetected: false,
        speakingDuration: 0,
        silenceDuration: 0,
        tensionScore: 0,
        rapidRestartCount: 0,
        recommendedMode: .listening
    )
}

struct RhythmAnalyzer {
    private let speechThreshold: Float = 0.015
    private let softSpeechThreshold: Float = 0.009
    private let elevatedZeroCrossingRate: Float = 0.16
    private let sustainedSpeechLimit: TimeInterval = 2.8
    private let recoverySilenceLimit: TimeInterval = 0.85
    private let shortBurstLimit: TimeInterval = 0.38
    private let shortPauseLimit: TimeInterval = 0.24
    private let rapidRestartLimit = 3

    private var speakingDuration: TimeInterval = 0
    private var silenceDuration: TimeInterval = 0
    private var previousSilenceDuration: TimeInterval = 0
    private var previousSpeechDuration: TimeInterval = 0
    private var rapidRestartCount = 0
    private var wasSpeechDetected = false

    mutating func reset() {
        speakingDuration = 0
        silenceDuration = 0
        previousSilenceDuration = 0
        previousSpeechDuration = 0
        rapidRestartCount = 0
        wasSpeechDetected = false
    }

    mutating func process(frame: AudioFrameFeatures, currentMode: PracticeMode) -> RhythmAnalysisSnapshot {
        let isSpeechDetected = frame.rms > speechThreshold || (frame.rms > softSpeechThreshold && frame.zeroCrossingRate > elevatedZeroCrossingRate)

        if isSpeechDetected {
            speakingDuration += frame.duration
            if !wasSpeechDetected {
                if previousSpeechDuration > 0,
                   previousSpeechDuration < shortBurstLimit,
                   previousSilenceDuration < shortPauseLimit {
                    rapidRestartCount += 1
                } else if previousSilenceDuration >= recoverySilenceLimit {
                    rapidRestartCount = 0
                }
            }
            silenceDuration = 0
        } else {
            silenceDuration += frame.duration
            if wasSpeechDetected {
                previousSpeechDuration = speakingDuration
                speakingDuration = 0
            }
            previousSilenceDuration = silenceDuration

            if silenceDuration >= recoverySilenceLimit {
                rapidRestartCount = 0
            }
        }

        wasSpeechDetected = isSpeechDetected

        let sustainedComponent = normalized(value: speakingDuration, start: 1.6, end: sustainedSpeechLimit)
        let restartComponent = min(Double(rapidRestartCount) / Double(rapidRestartLimit), 1.0)
        let agitationComponent = normalized(value: Double(frame.zeroCrossingRate), start: 0.10, end: Double(elevatedZeroCrossingRate))
        let tensionScore = min(1.0, sustainedComponent * 0.55 + restartComponent * 0.30 + agitationComponent * 0.15)

        let recommendedMode: PracticeMode
        if currentMode == .listening &&
            (speakingDuration >= sustainedSpeechLimit || rapidRestartCount >= rapidRestartLimit || tensionScore >= 0.72) {
            recommendedMode = .slowDownSupport
        } else if currentMode == .slowDownSupport && silenceDuration >= recoverySilenceLimit {
            recommendedMode = .listening
        } else {
            recommendedMode = currentMode
        }

        return RhythmAnalysisSnapshot(
            isSpeechDetected: isSpeechDetected,
            speakingDuration: speakingDuration,
            silenceDuration: silenceDuration,
            tensionScore: tensionScore,
            rapidRestartCount: rapidRestartCount,
            recommendedMode: recommendedMode
        )
    }

    private func normalized(value: Double, start: Double, end: Double) -> Double {
        guard end > start else { return 0 }
        return min(max((value - start) / (end - start), 0), 1)
    }
}
