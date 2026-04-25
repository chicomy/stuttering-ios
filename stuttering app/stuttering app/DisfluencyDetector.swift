//
//  DisfluencyDetector.swift
//  stuttering app
//
//  Created by Codex on 4/17/26.
//
//  Rule-based text-layer detector that turns Whisper word-level timestamps
//  into DisfluencyEvent values. Phase 2 scope — thresholds are absolute
//  buckets by word letter count; Phase 5 will swap in an adaptive median.
//

import Foundation

struct DisfluencyDetector: Sendable {

    struct Thresholds: Sendable {
        /// Prolongation threshold = first tier whose `maxChars` ≥ word letter count.
        /// Calibrated from the "I Have a Stutter" SEP sample on tiny.en.
        var prolongationByChars: [(maxChars: Int, dur: TimeInterval)] = [
            (1, 0.40),
            (3, 0.65),
            (6, 0.85),
            (Int.max, 1.10)
        ]

        /// Intra-sentence silence gap that counts as a block. Sentences are
        /// recognized by terminal punctuation on the previous token.
        var blockSilence: TimeInterval = 0.65

        /// Two consecutive same-lemma tokens within this gap count as a word
        /// repetition.
        var repetitionMaxGap: TimeInterval = 0.8

        /// Tokens matched against the lowercased, punctuation-stripped word
        /// text. English + common Mandarin fillers.
        var interjections: Set<String> = [
            "um", "umm", "uh", "uhh", "er", "erm", "ah", "ahh", "hmm", "mhm",
            "呃", "嗯", "那个", "就是"
        ]
    }

    var thresholds = Thresholds()

    func detect(in words: [TranscribedWord]) -> [DisfluencyEvent] {
        guard !words.isEmpty else { return [] }

        var events: [DisfluencyEvent] = []

        for (i, w) in words.enumerated() {
            let lowered = Self.normalize(w.text)

            // 1) Interjection — take precedence, skip other checks for this
            //    token (an "um" is by definition not a prolongation).
            if thresholds.interjections.contains(lowered) {
                events.append(.init(
                    kind: .interjection,
                    start: w.start, end: w.end,
                    text: w.text,
                    confidence: 0.9,
                    note: nil
                ))
                continue
            }

            // 2) Prolongation — compare duration against the tier for the
            //    word's letter count. Digits and punctuation are skipped
            //    (e.g. "20" has 0 letters and shouldn't be prolongation-checked).
            let letterCount = lowered.filter { $0.isLetter }.count
            if letterCount > 0 {
                let threshold = durationThreshold(forChars: letterCount)
                if w.duration > threshold {
                    let ratio = w.duration / threshold
                    events.append(.init(
                        kind: .prolongation,
                        start: w.start, end: w.end,
                        text: w.text,
                        confidence: min(1.0, (ratio - 1.0) / 1.5),
                        note: String(format: "%.2fs > %.2fs", w.duration, threshold)
                    ))
                }
            }

            // 3) Word repetition — same lemma back-to-back within gap window.
            if i > 0 {
                let prev = words[i - 1]
                let prevLowered = Self.normalize(prev.text)
                let gap = w.start - prev.end
                if !prevLowered.isEmpty,
                   prevLowered == lowered,
                   gap < thresholds.repetitionMaxGap {
                    events.append(.init(
                        kind: .wordRepetition,
                        start: prev.start, end: w.end,
                        text: "\(prev.text) \(w.text)",
                        confidence: 0.95,
                        note: nil
                    ))
                }
            }

            // 4) Block — long silence before this token, but only if the
            //    previous token wasn't a sentence terminator (those are
            //    natural pauses, e.g. after "Demnitz." in the sample).
            if i > 0 {
                let prev = words[i - 1]
                let gap = w.start - prev.end
                if gap > thresholds.blockSilence, !Self.endsSentence(prev.text) {
                    events.append(.init(
                        kind: .block,
                        start: prev.end, end: w.start,
                        text: "↓ \(w.text)",
                        confidence: min(1.0, gap / 1.5),
                        note: String(format: "%.2fs silence", gap)
                    ))
                }
            }
        }

        return events.sorted { $0.start < $1.start }
    }

    // MARK: - Helpers

    private func durationThreshold(forChars count: Int) -> TimeInterval {
        for tier in thresholds.prolongationByChars where count <= tier.maxChars {
            return tier.dur
        }
        return thresholds.prolongationByChars.last?.dur ?? 1.0
    }

    private static let sentenceTerminators: Set<Character> = [
        ".", "!", "?", "。", "!", "?", "…"
    ]

    private static func endsSentence(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespaces).last else { return false }
        return sentenceTerminators.contains(last)
    }

    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
    }
}
