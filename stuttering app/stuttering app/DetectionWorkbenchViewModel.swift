//
//  DetectionWorkbenchViewModel.swift
//  stuttering app
//
//  Created by Codex on 4/3/26.
//

import Foundation
import Combine

enum DetectionInputMode: String, CaseIterable, Identifiable {
    case live = "Live"
    case file = "Audio File"

    var id: String { rawValue }
}

@MainActor
final class DetectionWorkbenchViewModel: ObservableObject {
    @Published var selectedMode: DetectionInputMode = .live
    @Published private(set) var liveMonitoringState: AudioMonitoringState = .idle
    @Published private(set) var liveReport: StutterDetectionReport = .empty
    @Published private(set) var fileReport: StutterDetectionReport = .empty
    @Published private(set) var selectedFileName: String?
    @Published private(set) var isAnalyzingFile = false

    private let liveMonitor = PracticeAudioMonitor()
    private let fileAnalyzer = AudioFileAnalyzer()
    private var liveEngine = StutterDetectionEngine()

    func startLiveAnalysis() {
        liveEngine.reset()
        liveReport = .empty
        liveMonitor.start { [weak self] frame in
            guard let self else { return }
            self.liveReport = self.liveEngine.process(frame)
        } onStateChange: { [weak self] state in
            guard let self else { return }
            self.liveMonitoringState = state
        }
    }

    func stopLiveAnalysis() {
        liveMonitor.stop()
        liveReport = liveEngine.finalReport()
        liveMonitoringState = .idle
    }

    func triggerDemoPulse() {
        liveEngine.reset()
        liveReport = liveEngine.process(AudioFrameFeatures(rms: 0.046, zeroCrossingRate: 0.19, duration: 0.24))
        liveReport = liveEngine.process(AudioFrameFeatures(rms: 0.041, zeroCrossingRate: 0.18, duration: 0.27))
        liveReport = liveEngine.process(AudioFrameFeatures(rms: 0.043, zeroCrossingRate: 0.20, duration: 0.22))
    }

    func analyzeFile(at url: URL) {
        selectedFileName = url.lastPathComponent
        isAnalyzingFile = true
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
    }
}
