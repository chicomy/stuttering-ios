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

            VStack(spacing: 20) {
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
                .frame(height: 48)

                Text(liveStatusCaption)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(EasePalette.secondaryText)
                    .frame(height: 22, alignment: .center)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 16)

            liveActionArea
                .frame(maxHeight: .infinity, alignment: .top)
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
        VStack(spacing: 10) {
            if case .unavailable(let message) = viewModel.liveMonitoringState {
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(EasePalette.secondaryText.opacity(0.7))
                    .multilineTextAlignment(.center)
            } else {
                LiveTranscriptStrip(
                    tokens: viewModel.liveTranscript,
                    isActive: isLiveActive
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var fileScreen: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Audio file")
                    .font(.custom("Georgia-Bold", size: 34))
                    .foregroundStyle(EasePalette.primaryText)

                Text("Import a sample and generate a quiet report.")
                    .font(.system(size: 16))
                    .foregroundStyle(EasePalette.secondaryText)
            }

            modePicker

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
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

                        #if DEBUG
                        Button {
                            guard !viewModel.isAnalyzingFile else { return }
                            viewModel.analyzeBundledSample()
                        } label: {
                            Text("Run bundled sample (DEBUG)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(EasePalette.secondaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(EasePalette.outline, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        #endif

                        if let message = viewModel.whisperStatus.message {
                            WhisperStatusStrip(
                                message: message,
                                isBusy: viewModel.whisperStatus.isBusy
                            )
                        }
                    }

                    if !viewModel.fileReport.events.isEmpty {
                        DisfluencyBreakdownCard(report: viewModel.fileReport)
                    }

                    if !viewModel.fileTranscript.isEmpty {
                        FileTranscriptCard(tokens: viewModel.fileTranscript)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
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

                    if !report.events.isEmpty {
                        DisfluencyBreakdownCard(report: report)
                        DisfluencyEventsCard(events: report.events)
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

// MARK: - Disfluency UI (Phase 4)

private enum DisfluencyStyle {
    static func color(for kind: DisfluencyKind) -> Color {
        switch kind {
        case .prolongation:    return EasePalette.mutedRose
        case .block:           return EasePalette.mutedBrick
        case .wordRepetition:  return EasePalette.sage
        case .soundRepetition: return EasePalette.sage
        case .interjection:    return EasePalette.mistBlue
        }
    }

    static func label(for kind: DisfluencyKind) -> String {
        switch kind {
        case .prolongation:    return "Prolongation"
        case .block:           return "Block"
        case .wordRepetition:  return "Word repeat"
        case .soundRepetition: return "Sound repeat"
        case .interjection:    return "Filler"
        }
    }

    static let displayOrder: [DisfluencyKind] = [
        .prolongation, .block, .wordRepetition, .soundRepetition, .interjection
    ]
}

private struct WhisperStatusStrip: View {
    let message: String
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isBusy {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
                    .tint(EasePalette.secondaryText)
            } else {
                Circle()
                    .fill(EasePalette.secondaryText.opacity(0.4))
                    .frame(width: 6, height: 6)
            }

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(EasePalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(EasePalette.secondaryText.opacity(0.06))
        )
    }
}

/// Phase 3: streaming live transcript. Each token is colored by its
/// classification (normal speech / prolongation / block / repetition /
/// filler), and long silence gaps render as muted ellipses. Uses
/// AttributedString so text wraps naturally — lets us show many more
/// words than a single-line horizontal chip strip.
private struct LiveTranscriptStrip: View {
    let tokens: [LiveTranscriptToken]
    let isActive: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    if tokens.isEmpty {
                        HStack {
                            Text(placeholder)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(EasePalette.secondaryText.opacity(0.55))
                            Spacer()
                        }
                    } else {
                        Text(attributed)
                            .font(.custom("Georgia", size: 18))
                            .foregroundStyle(EasePalette.primaryText)
                            .lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Anchor for auto-scroll.
                    Color.clear.frame(height: 1).id("tail")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(EasePalette.secondaryText.opacity(0.05))
            )
            .onChange(of: tokens.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("tail", anchor: .bottom)
                }
            }
        }
    }

    private var placeholder: String {
        isActive ? "Listening…" : "Tap the orb to begin"
    }

    private var attributed: AttributedString {
        var out = AttributedString("")
        for (i, token) in tokens.enumerated() {
            if i > 0 {
                let gap = token.start - tokens[i - 1].end
                if gap >= 1.0 {
                    out.append(silence("  ····  ", isBlock: true))
                } else if gap >= 0.7 {
                    out.append(silence("  ···  ", isBlock: true))
                } else if gap >= 0.4 {
                    out.append(silence("  ··  ", isBlock: false))
                } else {
                    out.append(AttributedString(" "))
                }
            }
            out.append(styled(token))
        }
        return out
    }

    private func styled(_ token: LiveTranscriptToken) -> AttributedString {
        var s = AttributedString(token.text)
        switch token.kind {
        case .normal:
            s.foregroundColor = EasePalette.primaryText
        case .prolongation:
            s.foregroundColor = EasePalette.mutedRose
            s.backgroundColor = EasePalette.mutedRose.opacity(0.14)
        case .block:
            s.foregroundColor = EasePalette.mutedBrick
            s.backgroundColor = EasePalette.mutedBrick.opacity(0.14)
        case .wordRepetition:
            s.foregroundColor = EasePalette.sage
            s.backgroundColor = EasePalette.sage.opacity(0.16)
        case .interjection:
            s.foregroundColor = EasePalette.primaryText.opacity(0.75)
            s.backgroundColor = EasePalette.mistBlue.opacity(0.9)
        }
        return s
    }

    private func silence(_ text: String, isBlock: Bool) -> AttributedString {
        var s = AttributedString(text)
        s.foregroundColor = isBlock
            ? EasePalette.mutedBrick.opacity(0.8)
            : EasePalette.secondaryText.opacity(0.6)
        return s
    }
}

/// Phase 4 revision: File-mode transcript, rendered as wrapping prose
/// with the same color language as the live strip. Uses AttributedString
/// so lines wrap naturally and highlighted words read as part of the
/// paragraph, not as separate cards.
private struct FileTranscriptCard: View {
    let tokens: [LiveTranscriptToken]

    var body: some View {
        EaseCard {
            Text("Transcript")
                .font(.custom("Georgia-Bold", size: 18))
                .foregroundStyle(EasePalette.primaryText)

            Text(attributed)
                .font(.custom("Georgia", size: 17))
                .foregroundStyle(EasePalette.primaryText)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

            TranscriptLegend()
                .padding(.top, 4)
        }
    }

    private var attributed: AttributedString {
        var out = AttributedString("")
        for (i, token) in tokens.enumerated() {
            if i > 0 {
                let gap = token.start - tokens[i - 1].end
                if gap >= 1.0 {
                    out.append(silence("  ····  ", kind: .block))
                } else if gap >= 0.7 {
                    out.append(silence("  ···  ", kind: .block))
                } else if gap >= 0.4 {
                    out.append(silence("  ··  ", kind: .normal))
                } else {
                    out.append(AttributedString(" "))
                }
            }
            out.append(styled(token))
        }
        return out
    }

    private func styled(_ token: LiveTranscriptToken) -> AttributedString {
        var s = AttributedString(token.text)
        let (fg, bg) = colors(for: token.kind)
        s.foregroundColor = fg
        if let bg {
            s.backgroundColor = bg
        }
        return s
    }

    private func silence(_ text: String, kind: LiveTokenKind) -> AttributedString {
        var s = AttributedString(text)
        s.foregroundColor = kind == .block
            ? EasePalette.mutedBrick.opacity(0.8)
            : EasePalette.secondaryText.opacity(0.6)
        return s
    }

    private func colors(for kind: LiveTokenKind) -> (Color, Color?) {
        switch kind {
        case .normal:
            return (EasePalette.primaryText, nil)
        case .prolongation:
            return (EasePalette.mutedRose, EasePalette.mutedRose.opacity(0.14))
        case .block:
            return (EasePalette.mutedBrick, EasePalette.mutedBrick.opacity(0.14))
        case .wordRepetition:
            return (EasePalette.sage, EasePalette.sage.opacity(0.16))
        case .interjection:
            return (EasePalette.primaryText.opacity(0.75), EasePalette.mistBlue.opacity(0.9))
        }
    }
}

private struct TranscriptLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            legendDot(color: EasePalette.mutedRose,  label: "Prolongation")
            legendDot(color: EasePalette.mutedBrick, label: "Block")
            legendDot(color: EasePalette.sage,       label: "Repeat")
            legendDot(color: EasePalette.mistBlue.opacity(0.9), label: "Filler")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(EasePalette.secondaryText)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
        }
    }
}

private struct DisfluencyBreakdownCard: View {
    let report: StutterDetectionReport

    var body: some View {
        EaseCard {
            Text("What we heard")
                .font(.custom("Georgia", size: 20))
                .foregroundStyle(EasePalette.primaryText)

            Text("Gentle patterns found in \(formattedDuration). Counts, not judgments.")
                .font(.system(size: 13))
                .foregroundStyle(EasePalette.secondaryText)

            HStack(spacing: 10) {
                ForEach(visibleKinds, id: \.self) { kind in
                    DisfluencyCountPill(
                        kind: kind,
                        count: report.eventCountsByKind[kind] ?? 0
                    )
                }
            }
        }
    }

    private var visibleKinds: [DisfluencyKind] {
        let counts = report.eventCountsByKind
        return DisfluencyStyle.displayOrder.filter { (counts[$0] ?? 0) > 0 }
    }

    private var formattedDuration: String {
        let total = Int(report.analyzedDuration.rounded())
        let m = total / 60
        let s = total % 60
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
}

private struct DisfluencyCountPill: View {
    let kind: DisfluencyKind
    let count: Int

    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(EasePalette.primaryText)
            Text(DisfluencyStyle.label(for: kind))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(EasePalette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(DisfluencyStyle.color(for: kind).opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct DisfluencyEventsCard: View {
    let events: [DisfluencyEvent]

    var body: some View {
        EaseCard {
            Text("Moments")
                .font(.custom("Georgia", size: 20))
                .foregroundStyle(EasePalette.primaryText)

            VStack(spacing: 10) {
                ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                    DisfluencyEventRow(event: event)
                }
            }
        }
    }
}

private struct DisfluencyEventRow: View {
    let event: DisfluencyEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(DisfluencyStyle.color(for: event.kind))
                .frame(width: 4)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(DisfluencyStyle.label(for: event.kind))
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(DisfluencyStyle.color(for: event.kind))
                    Text(timestampText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(EasePalette.secondaryText)
                    Spacer()
                    Text("\(Int(event.confidence * 100))%")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(EasePalette.secondaryText.opacity(0.7))
                }

                Text(event.text)
                    .font(.custom("Georgia", size: 15))
                    .foregroundStyle(EasePalette.primaryText)
                    .lineLimit(1)

                if let note = event.note {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(EasePalette.secondaryText.opacity(0.75))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private var timestampText: String {
        let s = Int(event.start.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
