//
//  EaseAppModel.swift
//  stuttering app
//
//  Created by Codex on 4/2/26.
//

import Foundation
import Combine

enum AppScreen {
    case home
    case practice
    case reflection
}

struct ReflectionSummary {
    let title: String
    let duration: String
    let steadyMoment: String
    let slowDownMoment: String
    let nextStep: String

    static let empty = ReflectionSummary(
        title: "You showed up. That's what matters.",
        duration: "A short session",
        steadyMoment: "A few phrases felt more open and settled.",
        slowDownMoment: "When the pace tightened, the app created room to breathe.",
        nextStep: "Before a harder word, try one quiet breath."
    )
}

@MainActor
final class EaseAppModel: ObservableObject {
    @Published var screen: AppScreen = .home
    @Published var reflectionSummary: ReflectionSummary = .empty

    let practiceViewModel = PracticeViewModel()

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12:
            return "Good morning."
        case 12..<17:
            return "Good afternoon."
        default:
            return "Good evening."
        }
    }

    func startPractice() {
        practiceViewModel.startSession()
        screen = .practice
    }

    func finishPractice() {
        reflectionSummary = practiceViewModel.endSession()
        screen = .reflection
    }

    func returnHome() {
        practiceViewModel.resetSession()
        screen = .home
    }
}
