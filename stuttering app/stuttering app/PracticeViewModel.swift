//
//  PracticeViewModel.swift
//  stuttering app
//
//  Created by Codex on 4/2/26.
//

import Foundation
import Combine

enum PracticeMode {
    case listening
    case slowDownSupport
}

@MainActor
final class PracticeViewModel: ObservableObject {
    @Published private(set) var mode: PracticeMode = .listening
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var prompt: String = "Listening to your rhythm"
    @Published private(set) var helperText: String = "Steady, quiet support."
    @Published private(set) var monitoringState: AudioMonitoringState = .idle
    @Published private(set) var latestSnapshot = RhythmAnalysisSnapshot.idle

    private let audioMonitor = PracticeAudioMonitor()
    private var analyzer = RhythmAnalyzer()
    private var elapsedTimer: AnyCancellable?

    func startSession() {
        elapsedSeconds = 0
        analyzer.reset()
        latestSnapshot = .idle
        setMode(.listening)
        startElapsedTimer()
        audioMonitor.start { [weak self] frame in
            Task { @MainActor in
                self?.handle(frame: frame)
            }
        } onStateChange: { [weak self] state in
            Task { @MainActor in
                self?.monitoringState = state
            }
        }
    }

    func simulateTensionDetected() {
        handle(frame: AudioFrameFeatures(rms: 0.042, zeroCrossingRate: 0.19, duration: 0.24))
    }

    func resumeListening() {
        handle(frame: AudioFrameFeatures(rms: 0.0005, zeroCrossingRate: 0.01, duration: 1.2))
    }

    func resetSession() {
        elapsedTimer?.cancel()
        elapsedTimer = nil
        audioMonitor.stop()
        elapsedSeconds = 0
        latestSnapshot = .idle
        monitoringState = .idle
        analyzer.reset()
        setMode(.listening)
    }

    func buildReflectionSummary() -> ReflectionSummary {
        let durationText = formattedDuration(from: max(elapsedSeconds, 74))
        return ReflectionSummary(
            title: "You showed up. That's what matters.",
            duration: durationText,
            steadyMoment: "Around the middle of the session, your pace felt more open and even.",
            slowDownMoment: "When tension appeared, you paused instead of pushing through it.",
            nextStep: "If a word feels tighter next time, leave one breath of space before it."
        )
    }

    func endSession() -> ReflectionSummary {
        let summary = buildReflectionSummary()
        elapsedTimer?.cancel()
        elapsedTimer = nil
        audioMonitor.stop()
        monitoringState = .idle
        return summary
    }

    private func setMode(_ mode: PracticeMode) {
        self.mode = mode
        switch mode {
        case .listening:
            prompt = "Listening to your rhythm"
            helperText = "Steady, quiet support."
        case .slowDownSupport:
            prompt = "Let's slow down"
            helperText = "Take one breath. Continue when ready."
        }
    }

    private func handle(frame: AudioFrameFeatures) {
        let snapshot = analyzer.process(frame: frame, currentMode: mode)
        latestSnapshot = snapshot

        if snapshot.recommendedMode != mode {
            setMode(snapshot.recommendedMode)
        }
    }

    private func startElapsedTimer() {
        elapsedTimer?.cancel()
        elapsedTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.elapsedSeconds += 1
            }
    }

    private func formattedDuration(from totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes) min \(seconds) sec"
    }
}
