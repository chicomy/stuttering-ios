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
    private var onFrame: ((AudioFrameFeatures) -> Void)?
    private var onStateChange: ((AudioMonitoringState) -> Void)?
    private var onPCM: ((AVAudioPCMBuffer, AVAudioFormat) -> Void)?
    private var tapInstalled = false

    /// Check whether the device actually has an audio input before touching
    /// `audioEngine.inputNode` — accessing that property is a **fatal error**
    /// when no input hardware exists (e.g. Mac "Designed for iPad" simulator).
    private var hasInputDevice: Bool {
        let session = AVAudioSession.sharedInstance()
        return !(session.availableInputs?.isEmpty ?? true)
    }

    func start(
        onFrame: @escaping (AudioFrameFeatures) -> Void,
        onStateChange: @escaping (AudioMonitoringState) -> Void,
        onPCM: ((AVAudioPCMBuffer, AVAudioFormat) -> Void)? = nil
    ) {
        stop()

        self.onFrame = onFrame
        self.onStateChange = onStateChange
        self.onPCM = onPCM
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
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioEngine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func configureAndStart() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            guard hasInputDevice else {
                DispatchQueue.main.async {
                    self.onStateChange?(.unavailable("No microphone is available in this environment. You can still use the demo pulse."))
                }
                return
            }

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
            tapInstalled = true

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

        // Forward raw PCM (on the audio thread — receiver hops actors as
        // needed). This lets the streaming-ASR path share the mic tap
        // without installing a second one.
        onPCM?(buffer, format)

        DispatchQueue.main.async { [onFrame] in
            onFrame?(features)
        }
    }
}
