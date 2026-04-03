//
//  AudioFeatureExtractor.swift
//  stuttering app
//
//  Created by Codex on 4/3/26.
//

import Foundation
import AVFoundation

enum AudioFeatureExtractor {
    nonisolated static func extract(from buffer: AVAudioPCMBuffer, format: AVAudioFormat) -> AudioFrameFeatures? {
        guard let channelData = buffer.floatChannelData?.pointee else { return nil }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 1 else { return nil }

        var sumSquares: Float = 0
        var zeroCrossings = 0
        var previousSample = channelData[0]

        for index in 0..<frameCount {
            let sample = channelData[index]
            sumSquares += sample * sample
            if index > 0, (sample >= 0 && previousSample < 0) || (sample < 0 && previousSample >= 0) {
                zeroCrossings += 1
            }
            previousSample = sample
        }

        let rms = sqrt(sumSquares / Float(frameCount))
        let zcr = Float(zeroCrossings) / Float(frameCount)
        let duration = Double(frameCount) / format.sampleRate
        return AudioFrameFeatures(rms: rms, zeroCrossingRate: zcr, duration: duration)
    }
}
