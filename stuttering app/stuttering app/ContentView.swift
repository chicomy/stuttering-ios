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
    @State private var showsReport = false

    var body: some View {
        NavigationStack {
            ZStack {
                EasePalette.background.ignoresSafeArea()

                Group {
                    switch viewModel.selectedMode {
                    case .live:
                        liveScreen
                    case .file:
                        fileScreen
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $showsReport) {
                LiveSessionReportView(
                    report: viewModel.liveReport,
                    onDone: {
                        showsReport = false
                    }
                )
            }
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

    private var liveScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            liveHeader

            modePicker
                .padding(.top, 18)

            Spacer(minLength: 12)

            VStack(spacing: 30) {
                Button {
                    if isLiveActive {
                        let _ = viewModel.finishLiveAnalysis()
                        showsReport = true
                    } else {
                        viewModel.startLiveAnalysis()
                    }
                } label: {
                    LiveSeverityOrb(
                        severity: liveSeverity,
                        color: liveSeverityColor,
                        isInteractive: true,
                        isActive: isLiveActive
                    )
                }
                .buttonStyle(.plain)

                WaveformStrip(
                    color: liveSeverityColor,
                    bars: waveformBars,
                    level: viewModel.liveAudioLevel,
                    isActive: isLiveActive
                )
                .frame(height: 62)

                Text(liveStatusCaption)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(EasePalette.secondaryText)
                    .frame(height: 28, alignment: .center)

                Text(summaryCaption)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(EasePalette.secondaryText.opacity(0.55))
                    .frame(height: 20, alignment: .center)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 24)

            liveActionArea
        }
    }

    private var liveHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("With you")
                .font(.custom("Georgia-Bold", size: 34))
                .foregroundStyle(EasePalette.primaryText)

            Text(liveDurationText)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(EasePalette.secondaryText)
        }
    }

    private var modePicker: some View {
        Picker("Detection mode", selection: $viewModel.selectedMode) {
            ForEach(DetectionInputMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var liveActionArea: some View {
        VStack(spacing: 18) {
            Text(statusDotLine)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(liveSeverityColor.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }

    private var fileScreen: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Audio file")
                    .font(.custom("Georgia-Bold", size: 34))
                    .foregroundStyle(EasePalette.primaryText)

                Text("Import a sample and generate a quiet report.")
                    .font(.system(size: 16))
                    .foregroundStyle(EasePalette.secondaryText)
            }

            modePicker

            Spacer(minLength: 12)

            EaseCard {
                Text(viewModel.selectedFileName ?? "Choose a recording")
                    .font(.custom("Georgia", size: 24))
                    .foregroundStyle(EasePalette.primaryText)

                Text(viewModel.fileReport.summary)
                    .font(.system(size: 15))
                    .foregroundStyle(EasePalette.secondaryText)

                EaseActionButton(
                    title: viewModel.isAnalyzingFile ? "Analyzing..." : "Choose audio file",
                    fill: EasePalette.sage
                ) {
                    guard !viewModel.isAnalyzingFile else { return }
                    isImportingAudio = true
                }
            }

            LiveSessionReportSummary(report: viewModel.fileReport)

            Spacer()
        }
    }

    private var liveDurationText: String {
        secondsText(viewModel.liveReport.analyzedDuration)
    }

    private var liveSeverity: Double {
        if viewModel.liveMonitoringState == .idle && viewModel.liveReport.analyzedDuration == 0 {
            return 0.08
        }
        return min(max(viewModel.liveReport.confidence, 0), 1)
    }

    private var liveSeverityColor: Color {
        EasePalette.severityColor(for: liveSeverity)
    }

    private var isLiveActive: Bool {
        switch viewModel.liveMonitoringState {
        case .monitoring, .requestingPermission:
            return true
        case .idle, .unavailable:
            return false
        }
    }

    private var liveStatusCaption: String {
        switch viewModel.liveMonitoringState {
        case .idle:
            return "Listening to your rhythm"
        case .requestingPermission:
            return "Preparing to listen"
        case .monitoring:
            return viewModel.liveReport.likelyContainsStuttering ? "Tension is rising" : "Listening to your rhythm"
        case .unavailable:
            return "Microphone unavailable"
        }
    }

    private var summaryCaption: String {
        if viewModel.liveReport.analyzedDuration < 1 {
            return "Tap the orb to begin"
        }
        return liveSeverity > 0.58 ? "ease is slowing down with you" : "ease is with you"
    }

    private var statusDotLine: String {
        if case .unavailable(let message) = viewModel.liveMonitoringState {
            return message
        }
        return "• ease is with you"
    }

    private var waveformBars: [CGFloat] {
        let base = max(liveSeverity, 0.08)
        let pattern: [CGFloat] = [0.42, 0.5, 0.47, 0.18, 0.38, 0.16, 0.29, 0.33, 0.4, 0.37, 0.31, 0.46, 0.24, 0.41, 0.55, 0.28]
        return pattern.map { value in
            let scaled = 0.14 + value * (0.48 + base * 0.52)
            return min(max(scaled, 0.12), 0.92)
        }
    }

    private var supportedAudioTypes: [UTType] {
        [.audio, .wav, .mpeg4Audio, .mp3]
    }

    private func secondsText(_ value: TimeInterval) -> String {
        let total = Int(value.rounded(.down))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct LiveSeverityOrb: View {
    let severity: Double
    let color: Color
    let isInteractive: Bool
    var isActive: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.10), lineWidth: 2)
                .frame(width: 372, height: 372)
                .opacity(isActive ? 0.88 : 1)

            Circle()
                .stroke(color.opacity(0.22), lineWidth: 3)
                .frame(width: 286, height: 286)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            color.opacity(0.86),
                            color.opacity(0.78)
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 160
                    )
                )
                .frame(width: 196 + severity * 20, height: 196 + severity * 20)
                .shadow(color: color.opacity(0.18), radius: 24, x: 0, y: 8)
                .overlay(
                    Circle()
                        .stroke(EasePalette.surface.opacity(isActive ? 0.18 : 0), lineWidth: 1.2)
                        .padding(22)
                        .scaleEffect(isActive ? 1 : 0.96)
                        .opacity(isActive ? 1 : 0)
                )

            if isInteractive {
                Image(systemName: isActive ? "stop.fill" : "play.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(EasePalette.surface.opacity(0.88))
                    .offset(x: isActive ? 0 : 3)
            }
        }
        .frame(maxWidth: .infinity)
        .scaleEffect(isInteractive ? 1 : 1.02)
        .animation(.easeInOut(duration: 0.2), value: isInteractive)
    }
}

private struct WaveformStrip: View {
    let color: Color
    let bars: [CGFloat]
    let level: Double
    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: isActive ? 1.0 / 18.0 : 1.0 / 8.0, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            ZStack {
                Color.clear

                HStack(alignment: .center, spacing: 10) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { index, height in
                        let barIndex = Double(index)
                        let halfCount = Double(max(bars.count / 2, 1))
                        let midpoint = Double(bars.count - 1) / 2
                        let centerDistance = abs(barIndex - midpoint)
                        let centerBias = 1 - centerDistance / halfCount
                        let idleHeight = Double(height) * 0.2
                        let liveBase = Double(height) * (0.28 + level * (0.42 + centerBias * 0.16))
                        let waveSpeedA = 4.8 + level * 4.2
                        let waveSpeedB = 8.6 + level * 5.4
                        let phaseA = time * waveSpeedA + barIndex * 0.42
                        let phaseB = time * waveSpeedB + barIndex * 0.83 + 0.7
                        let waveA = sin(phaseA)
                        let waveB = sin(phaseB)
                        let shimmer = max(0.0, waveA * 0.65 + waveB * 0.35)
                        let animatedLift = isActive ? shimmer * (0.2 + level * (0.55 + centerBias * 0.2)) : 0
                        let response = max(0.12, isActive ? liveBase + animatedLift : idleHeight)

                        Capsule()
                            .fill(color.opacity(index.isMultiple(of: 3) ? 0.88 : 0.52))
                            .frame(width: 4, height: 14 + response * 46)
                    }
                }
            }
            .frame(height: 62, alignment: .center)
        }
    }
}

private struct LiveSessionReportSummary: View {
    let report: StutterDetectionReport

    var body: some View {
        EaseCard {
            Text(report.likelyContainsStuttering ? "Signal detected" : "Gentle signal")
                .font(.custom("Georgia", size: 24))
                .foregroundStyle(EasePalette.primaryText)

            Text(report.summary)
                .font(.system(size: 15))
                .foregroundStyle(EasePalette.secondaryText)

            HStack {
                MetricPill(label: "Confidence", value: "\(Int(report.confidence * 100))%")
                MetricPill(label: "Restarts", value: "\(report.rapidRestartCount)")
                MetricPill(label: "Run", value: String(format: "%.1fs", report.longestSpeechRun))
            }
        }
    }
}

private struct LiveSessionReportView: View {
    let report: StutterDetectionReport
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            EasePalette.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Session report")
                            .font(.custom("Georgia-Bold", size: 34))
                            .foregroundStyle(EasePalette.primaryText)

                        Text(reportHeadline)
                            .font(.system(size: 18))
                            .foregroundStyle(EasePalette.secondaryText)
                    }

                    LiveSeverityOrb(
                        severity: min(max(report.confidence, 0.08), 1),
                        color: EasePalette.severityColor(for: report.confidence),
                        isInteractive: false
                    )
                    .frame(height: 300)

                    LiveSessionReportSummary(report: report)

                    VStack(alignment: .leading, spacing: 14) {
                        ReportRow(label: "Duration", value: durationText)
                        ReportRow(label: "Speech", value: String(format: "%.1fs", report.speechDuration))
                        ReportRow(label: "Longest run", value: String(format: "%.1fs", report.longestSpeechRun))
                        ReportRow(label: "Rapid restarts", value: "\(report.rapidRestartCount)")
                        ReportRow(label: "Tension moments", value: "\(report.elevatedTensionMoments)")
                    }

                    EaseMinimalButton(
                        title: "Done",
                        isPrimary: true,
                        action: {
                            onDone()
                            dismiss()
                        }
                    )
                }
                .padding(.horizontal, 28)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private var reportHeadline: String {
        report.likelyContainsStuttering ? "A stronger stuttering signal appeared." : "The sample stayed relatively settled."
    }

    private var durationText: String {
        let total = Int(report.analyzedDuration.rounded(.down))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct ReportRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(EasePalette.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(EasePalette.primaryText)
        }
    }
}

private struct MetricPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(EasePalette.primaryText)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(EasePalette.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(EasePalette.surface.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(EasePalette.outline, lineWidth: 1)
        )
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

private struct EaseMinimalButton: View {
    let title: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(EasePalette.primaryText.opacity(isPrimary ? 0.88 : 0.72))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
    }
}
