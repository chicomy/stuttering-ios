//
//  PracticeView.swift
//  stuttering app
//
//  Created by Codex on 4/2/26.
//

import SwiftUI

struct PracticeView: View {
    @ObservedObject var viewModel: PracticeViewModel
    let onEndSession: () -> Void

    var body: some View {
        ZStack {
            EasePalette.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("With you")
                        .font(.custom("Georgia-Bold", size: 28))
                        .foregroundStyle(EasePalette.primaryText)

                    Text(sessionTime)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(EasePalette.secondaryText)
                }

                Spacer()

                PracticeOrbView(mode: viewModel.mode)
                    .frame(maxWidth: .infinity)

                VStack(spacing: 8) {
                    Text(viewModel.prompt)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(EasePalette.primaryText)

                    Text(viewModel.helperText)
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(EasePalette.secondaryText)
                }
                .frame(maxWidth: .infinity)

                EaseCard {
                    Text("Live support")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EasePalette.secondaryText)

                    Text(viewModel.mode == .listening ? "Listening" : "Slow-down support")
                        .font(.custom("Georgia", size: 20))
                        .foregroundStyle(EasePalette.primaryText)

                    Text(statusText)
                        .font(.system(size: 14))
                        .foregroundStyle(EasePalette.secondaryText)

                    VStack(alignment: .leading, spacing: 8) {
                        MeterRow(
                            label: "Voice energy",
                            value: energyMeterValue
                        )
                        MeterRow(
                            label: "Tension score",
                            value: viewModel.latestSnapshot.tensionScore
                        )
                        Text(detailText)
                            .font(.system(size: 13))
                            .foregroundStyle(EasePalette.secondaryText)
                    }

                    if case .unavailable = viewModel.monitoringState {
                        Button("Run demo pulse") {
                            viewModel.simulateTensionDetected()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(EasePalette.sage)
                    }
                }

                EasePrimaryButton(title: "End session", action: onEndSession)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
    }

    private var sessionTime: String {
        let minutes = viewModel.elapsedSeconds / 60
        let seconds = viewModel.elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var statusText: String {
        switch viewModel.monitoringState {
        case .idle:
            return "Preparing the practice session."
        case .requestingPermission:
            return "Requesting microphone access."
        case .monitoring:
            return "Using live rhythm cues from voice energy, pauses, and pacing."
        case .unavailable(let message):
            return message
        }
    }

    private var detailText: String {
        if viewModel.latestSnapshot.isSpeechDetected {
            return "Speaking for \(formatted(viewModel.latestSnapshot.speakingDuration)) with \(viewModel.latestSnapshot.rapidRestartCount) quick restarts detected."
        }
        return "Pause length \(formatted(viewModel.latestSnapshot.silenceDuration)). The app returns to listening after a calm pause."
    }

    private var energyMeterValue: Double {
        if viewModel.latestSnapshot.tensionScore == 0 && !viewModel.latestSnapshot.isSpeechDetected {
            return 0
        }
        let speechBase = viewModel.latestSnapshot.isSpeechDetected ? 0.2 : 0.05
        return min(speechBase + viewModel.latestSnapshot.tensionScore * 0.8, 1)
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        String(format: "%.1fs", seconds)
    }
}

private struct PracticeOrbView: View {
    let mode: PracticeMode

    var body: some View {
        ZStack {
            Circle()
                .stroke(EasePalette.sage.opacity(mode == .listening ? 0.18 : 0.28), lineWidth: 1.5)
                .frame(width: 220, height: 220)

            Circle()
                .stroke(EasePalette.sage.opacity(mode == .listening ? 0.28 : 0.4), lineWidth: 1.5)
                .frame(width: 168, height: 168)

            Circle()
                .fill(mode == .listening ? EasePalette.sageSoft : EasePalette.warmSand)
                .frame(width: mode == .listening ? 112 : 126, height: mode == .listening ? 112 : 126)
                .overlay(
                    Image(systemName: mode == .listening ? "waveform" : "wind")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(mode == .listening ? EasePalette.sage : EasePalette.primaryText)
                )
                .animation(.easeInOut(duration: 0.25), value: mode)
        }
    }
}

private struct MeterRow: View {
    let label: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(EasePalette.secondaryText)
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(EasePalette.secondaryText)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(EasePalette.outline)
                    Capsule()
                        .fill(EasePalette.sage)
                        .frame(width: proxy.size.width * max(0, min(value, 1)))
                }
            }
            .frame(height: 8)
        }
    }
}
