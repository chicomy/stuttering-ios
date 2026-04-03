//
//  AudioFileAnalyzer.swift
//  stuttering app
//
//  Created by Codex on 4/3/26.
//

import Foundation
import AVFoundation

enum AudioFileAnalyzerError: LocalizedError {
    case unsupportedFormat
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "This audio format could not be analyzed."
        case .unreadableFile:
            return "The audio file could not be read."
        }
    }
}

extension AudioFileAnalyzer: Sendable {}

struct AudioFileAnalyzer {
    nonisolated func analyze(url: URL) throws -> StutterDetectionReport {
        let file = try AVAudioFile(forReading: url)
        let processingFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: file.processingFormat.sampleRate, channels: 1, interleaved: false)
        guard let processingFormat else {
            throw AudioFileAnalyzerError.unsupportedFormat
        }

        let frameCapacity: AVAudioFrameCount = 1024
        guard let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: frameCapacity) else {
            throw AudioFileAnalyzerError.unreadableFile
        }

        let converter = AVAudioConverter(from: file.processingFormat, to: processingFormat)
        guard let converter else {
            throw AudioFileAnalyzerError.unsupportedFormat
        }

        var engine = StutterDetectionEngine()
        var finished = false

        while !finished {
            var error: NSError?
            let status = converter.convert(to: buffer, error: &error) { _, outStatus in
                if finished {
                    outStatus.pointee = .endOfStream
                    return nil
                }

                do {
                    let sourceBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCapacity)!
                    try file.read(into: sourceBuffer, frameCount: frameCapacity)
                    if sourceBuffer.frameLength == 0 {
                        finished = true
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                    outStatus.pointee = .haveData
                    return sourceBuffer
                } catch {
                    finished = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
            }

            if let error {
                throw error
            }

            switch status {
            case .haveData:
                if let frame = AudioFeatureExtractor.extract(from: buffer, format: processingFormat) {
                    _ = engine.process(frame)
                }
            case .inputRanDry:
                continue
            case .endOfStream:
                finished = true
            case .error:
                throw AudioFileAnalyzerError.unreadableFile
            @unknown default:
                finished = true
            }
        }

        return engine.finalReport()
    }
}
