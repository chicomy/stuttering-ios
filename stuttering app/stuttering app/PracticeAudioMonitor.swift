//
//  PracticeAudioMonitor.swift
//  stuttering app
//
//  Created by Codex on 4/3/26.
//

import Foundation
import AVFoundation

enum AudioMonitoringState: Equatable {
    case idle
    case requestingPermission
    case monitoring
    case unavailable(String)
}

final class PracticeAudioMonitor {
    private let audioEngine = AVAudioEngine()
    private let audioSession = AVAudioSession.sharedInstance()
    private var onFrame: ((AudioFrameFeatures) -> Void)?
    private var onStateChange: ((AudioMonitoringState) -> Void)?

    func start(
        onFrame: @escaping (AudioFrameFeatures) -> Void,
        onStateChange: @escaping (AudioMonitoringState) -> Void
    ) {
        stop()

        self.onFrame = onFrame
        self.onStateChange = onStateChange
        onStateChange(.requestingPermission)

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            guard let self else { return }
            if granted {
                self.configureAndStart()
            } else {
                DispatchQueue.main.async {
                    self.onStateChange?(.unavailable("Microphone access is off. You can still use the demo pulse."))
                }
            }
        }
    }

    func stop() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func configureAndStart() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = audioEngine.inputNode
            let format = inputNode.inputFormat(forBus: 0)
            guard format.channelCount > 0 else {
                DispatchQueue.main.async {
                    self.onStateChange?(.unavailable("No microphone input is available in the current environment."))
                }
                return
            }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.consume(buffer: buffer, format: format)
            }

            audioEngine.prepare()
            try audioEngine.start()

            DispatchQueue.main.async {
                self.onStateChange?(.monitoring)
            }
        } catch {
            DispatchQueue.main.async {
                self.onStateChange?(.unavailable("Live listening couldn't start. The demo pulse is still available."))
            }
        }
    }

    private func consume(buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        guard let features = AudioFeatureExtractor.extract(from: buffer, format: format) else { return }

        DispatchQueue.main.async { [onFrame] in
            onFrame?(features)
        }
    }
}
