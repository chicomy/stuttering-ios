//
//  ContentView.swift
//  stuttering app
//
//  Created by Chongming Wang on 3/25/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = DetectionWorkbenchViewModel()
    @State private var isImportingAudio = false

    var body: some View {
        NavigationStack {
            ZStack {
                EasePalette.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header

                        Picker("Detection mode", selection: $viewModel.selectedMode) {
                            ForEach(DetectionInputMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        switch viewModel.selectedMode {
                        case .live:
                            liveSection
                        case .file:
                            fileSection
                        }
                    }
                    .padding(24)
                }
            }
            .navigationBarHidden(true)
        }
        .fileImporter(
            isPresented: $isImportingAudio,
            allowedContentTypes: supportedAudioTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.analyzeFile(at: url)
            }
        }
        .onDisappear {
            viewModel.stopLiveAnalysis()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ease")
                .font(.custom("Georgia", size: 24))
                .foregroundStyle(EasePalette.primaryText)

            Text("Stuttering signal detection")
                .font(.custom("Georgia-Bold", size: 30))
                .foregroundStyle(EasePalette.primaryText)

            Text("Phase one focuses on a single job: analyze incoming audio and estimate whether it contains stuttering-like disfluency.")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(EasePalette.secondaryText)
        }
    }

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            EaseCard {
                Text("LIVE MICROPHONE")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(EasePalette.secondaryText)

                Text(liveStatusTitle)
                    .font(.custom("Georgia", size: 22))
                    .foregroundStyle(EasePalette.primaryText)

                Text(liveStatusBody)
                    .font(.system(size: 15))
                    .foregroundStyle(EasePalette.secondaryText)

                HStack(spacing: 12) {
                    EaseActionButton(title: "Start live analysis", fill: EasePalette.sage) {
                        viewModel.startLiveAnalysis()
                    }

                    EaseActionButton(title: "Stop", fill: EasePalette.surface, foreground: EasePalette.primaryText) {
                        viewModel.stopLiveAnalysis()
                    }
                }

                if case .unavailable = viewModel.liveMonitoringState {
                    EaseActionButton(title: "Run demo pulse", fill: EasePalette.mistBlue, foreground: EasePalette.primaryText) {
                        viewModel.triggerDemoPulse()
                    }
                }
            }

            DetectionReportCard(
                title: "Live detection result",
                report: viewModel.liveReport
            )
        }
    }

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            EaseCard {
                Text("AUDIO FILE")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(EasePalette.secondaryText)

                Text("Import a recording")
                    .font(.custom("Georgia", size: 22))
                    .foregroundStyle(EasePalette.primaryText)

                Text(viewModel.selectedFileName ?? "Choose a local audio file to run the same lightweight detector offline.")
                    .font(.system(size: 15))
                    .foregroundStyle(EasePalette.secondaryText)

                EaseActionButton(title: viewModel.isAnalyzingFile ? "Analyzing..." : "Choose audio file", fill: EasePalette.sage) {
                    guard !viewModel.isAnalyzingFile else { return }
                    isImportingAudio = true
                }
            }

            DetectionReportCard(
                title: "File analysis result",
                report: viewModel.fileReport
            )
        }
    }

    private var liveStatusTitle: String {
        switch viewModel.liveMonitoringState {
        case .idle:
            return "Ready to listen"
        case .requestingPermission:
            return "Checking microphone"
        case .monitoring:
            return "Analyzing speech in real time"
        case .unavailable:
            return "Microphone unavailable"
        }
    }

    private var liveStatusBody: String {
        switch viewModel.liveMonitoringState {
        case .idle:
            return "The detector listens for repeated restarts, sustained tense runs, and weak pause recovery."
        case .requestingPermission:
            return "Grant microphone access so the detector can analyze incoming speech frames."
        case .monitoring:
            return "The detector is evaluating energy, zero-crossing rate, speaking runs, and pause patterns."
        case .unavailable(let message):
            return message
        }
    }

    private var supportedAudioTypes: [UTType] {
        [.audio, .wav, .mpeg4Audio, .mp3]
    }
}

private struct DetectionReportCard: View {
    let title: String
    let report: StutterDetectionReport

    var body: some View {
        EaseCard {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(EasePalette.secondaryText)

            Text(report.likelyContainsStuttering ? "Possible stuttering-like disfluency detected" : "No strong stuttering signal detected")
                .font(.custom("Georgia", size: 22))
                .foregroundStyle(EasePalette.primaryText)

            Text(report.summary)
                .font(.system(size: 15))
                .foregroundStyle(EasePalette.secondaryText)

            VStack(spacing: 10) {
                MetricRow(label: "Confidence", value: percentage(report.confidence))
                MetricRow(label: "Analyzed duration", value: seconds(report.analyzedDuration))
                MetricRow(label: "Speech duration", value: seconds(report.speechDuration))
                MetricRow(label: "Longest speech run", value: seconds(report.longestSpeechRun))
                MetricRow(label: "Rapid restarts", value: "\(report.rapidRestartCount)")
                MetricRow(label: "Elevated tension moments", value: "\(report.elevatedTensionMoments)")
            }
        }
    }

    private func percentage(_ value: Double) -> String {
        "\(Int(value * 100))%"
    }

    private func seconds(_ value: TimeInterval) -> String {
        String(format: "%.1fs", value)
    }
}

private struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(EasePalette.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(EasePalette.primaryText)
        }
    }
}

private struct EaseActionButton: View {
    let title: String
    let fill: Color
    var foreground: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(fill)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
