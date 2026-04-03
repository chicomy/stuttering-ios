//
//  ReflectionView.swift
//  stuttering app
//
//  Created by Codex on 4/2/26.
//

import SwiftUI

struct ReflectionView: View {
    let summary: ReflectionSummary
    let onReturnHome: () -> Void

    var body: some View {
        ZStack {
            EasePalette.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Session complete")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(EasePalette.sage)

                    Text(summary.title)
                        .font(.custom("Georgia-Bold", size: 30))
                        .foregroundStyle(EasePalette.primaryText)

                    Text(summary.duration)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(EasePalette.secondaryText)
                }

                EaseCard {
                    Text("STEADIER MOMENTS")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(0.6)
                        .foregroundStyle(EasePalette.secondaryText)
                    Text(summary.steadyMoment)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(EasePalette.primaryText)
                }

                EaseCard {
                    Text("WHERE WE SLOWED DOWN")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(0.6)
                        .foregroundStyle(EasePalette.secondaryText)
                    Text(summary.slowDownMoment)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(EasePalette.primaryText)
                }

                EaseCard {
                    Text("FOR NEXT TIME")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(0.6)
                        .foregroundStyle(EasePalette.secondaryText)
                    Text(summary.nextStep)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(EasePalette.primaryText)
                }

                Spacer()

                EasePrimaryButton(title: "Back to home", action: onReturnHome)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
    }
}
