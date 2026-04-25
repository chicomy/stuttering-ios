//
//  DisfluencyEvent.swift
//  stuttering app
//
//  Created by Codex on 4/17/26.
//

import Foundation

enum DisfluencyKind: String, Sendable {
    case wordRepetition    // "I I went"
    case soundRepetition   // "b- b- book" — rare from Whisper, comes from acoustic layer
    case prolongation      // "ssssnake" or a word whose duration is way too long
    case block             // long intra-sentence silence before retry
    case interjection      // um / uh / 呃
}

struct DisfluencyEvent: Sendable, Equatable {
    let kind: DisfluencyKind
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    let confidence: Double    // 0…1, event-local
    let note: String?         // human-readable why, e.g. "1.92s > 0.65s"

    var duration: TimeInterval { max(0, end - start) }
}
