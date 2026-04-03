//
//  HomeView.swift
//  stuttering app
//
//  Created by Codex on 4/2/26.
//

import SwiftUI

struct HomeView: View {
    let greeting: String
    let onBeginPractice: () -> Void

    var body: some View {
        ZStack {
            EasePalette.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Text("ease")
                    .font(.custom("Georgia", size: 24))
                    .foregroundStyle(EasePalette.primaryText)

                VStack(alignment: .leading, spacing: 8) {
                    Text(greeting)
                        .font(.custom("Georgia-Bold", size: 34))
                        .foregroundStyle(EasePalette.primaryText)

                    Text("Your voice moves at its own pace.")
                        .font(.system(size: 17, weight: .light))
                        .foregroundStyle(EasePalette.secondaryText)
                }

                HomeOrbView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)

                EaseCard {
                    Text("BEFORE YOU BEGIN")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(0.6)
                        .foregroundStyle(EasePalette.secondaryText)

                    Text("Start softly.\nLet your voice find its rhythm.")
                        .font(.custom("Georgia", size: 16))
                        .foregroundStyle(EasePalette.primaryText)
                        .lineSpacing(4)
                }

                EasePrimaryButton(title: "Begin practice", action: onBeginPractice)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 20)
        }
    }
}

private struct HomeOrbView: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(EasePalette.sage.opacity(0.18), lineWidth: 1.5)
                .frame(width: 164, height: 164)
            Circle()
                .stroke(EasePalette.sage.opacity(0.28), lineWidth: 1.5)
                .frame(width: 126, height: 126)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [EasePalette.sageSoft, EasePalette.sage],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 92, height: 92)
                .overlay(Image(systemName: "figure.stand"))
                .foregroundStyle(.white.opacity(0.95))
        }
    }
}
