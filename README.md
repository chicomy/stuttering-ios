# ease

A quiet, on-device stuttering-pattern analyzer for iOS. Built with SwiftUI and
[WhisperKit](https://github.com/argmaxinc/WhisperKit). All audio processing —
including transcription — runs locally; nothing leaves the device.

> ease is a lightweight estimation tool, not a diagnostic instrument.

## Features

- **Live mode** — stream from the microphone and watch a color-coded
  transcript appear in real time, with disfluency events highlighted as they
  happen.
- **Audio File mode** — import a recording (`.mp3`, `.m4a`, `.wav`, …) and
  get a full transcript plus a "What we heard" breakdown.
- **Five disfluency categories** detected from word-level timing alone:
  prolongations, blocks, word repetitions, sound repetitions, and
  interjections (`um`, `uh`, `呃`, `嗯`, …).
- **Bundled Whisper model** — ships with `openai_whisper-tiny.en` so the app
  works offline and on networks where Hugging Face is unreachable.

## Architecture

Two detection layers feed one report.

```
┌──────────────┐     ┌─────────────────────────┐     ┌──────────────────────┐
│ AVAudioEngine│ ──► │ StutterDetectionEngine  │ ──► │ acoustic signal      │
│  (mic / file)│     │ (RMS + ZCR heuristics)  │     │ (rapid restarts,     │
│              │     │                         │     │  sustained tension)  │
│              │     └─────────────────────────┘     └──────────────────────┘
│              │
│              │     ┌─────────────────────────┐     ┌──────────────────────┐
│              │ ──► │ WhisperKit (tiny.en)    │ ──► │ DisfluencyDetector   │
│              │     │ → word-level timestamps │     │ (prolongation/block/ │
└──────────────┘     └─────────────────────────┘     │  repetition/filler)  │
                                                     └──────────┬───────────┘
                                                                ▼
                                                      StutterDetectionReport
```

| File | Role |
| --- | --- |
| [`WhisperTranscriber.swift`](stuttering%20app/stuttering%20app/WhisperTranscriber.swift) | Actor wrapping WhisperKit. Loads the bundled model, exposes one-shot file transcription and streaming-window transcription. |
| [`LiveWhisperStreamer.swift`](stuttering%20app/stuttering%20app/LiveWhisperStreamer.swift) | Captures the mic via `AVAudioEngine`, downsamples to 16 kHz, runs a 15 s sliding window through Whisper every 2 s with a silence gate. |
| [`DisfluencyDetector.swift`](stuttering%20app/stuttering%20app/DisfluencyDetector.swift) | Rule-based pass that turns word timings into `DisfluencyEvent`s. Thresholds are duration-by-letter-count tiers tuned on real samples. |
| [`StutterDetectionEngine.swift`](stuttering%20app/stuttering%20app/StutterDetectionEngine.swift) | Acoustic-only engine that runs even when Whisper isn't loaded yet. |
| [`DetectionWorkbenchViewModel.swift`](stuttering%20app/stuttering%20app/DetectionWorkbenchViewModel.swift) | Glue: status pipeline (`preparingModel → transcribing → detecting → ready`), event merging, transcript stream. |
| [`ContentView.swift`](stuttering%20app/stuttering%20app/ContentView.swift) | SwiftUI surface — color-coded transcript, "What we heard" breakdown, status strip. |

## Build & run

**Requirements**

- Xcode 16 or later
- iOS 17+ deployment target (project targets the latest minor)
- Apple Silicon Mac for first-time Swift Package resolution
- An Apple Developer signing identity (free is fine for local devices)

**Steps**

1. Open `stuttering app/stuttering app.xcodeproj`.
2. Select your team under *Signing & Capabilities*.
3. Pick a real device (the bundled CoreML model needs the Neural Engine for
   reasonable speed; the Simulator works but is much slower).
4. ⌘R.

The first launch warms up the on-device model — the UI surfaces this with a
"Preparing on-device model…" strip while CoreML compiles the weights.

## How the bundled model is loaded

`openai_whisper-tiny.en` (~77 MB: encoder, decoder, mel spectrogram, plus
tokenizer files) lives in
[`stuttering app/stuttering app/openai_whisper-tiny.en/`](stuttering%20app/stuttering%20app/openai_whisper-tiny.en).

`WhisperTranscriber` looks for the model in two layouts:

1. A folder reference under the bundle (`App.app/openai_whisper-tiny.en/…`).
2. The Xcode 16 auto-synced layout, which flattens the wrapper directory but
   preserves `.mlmodelc` bundles at `App.app/AudioEncoder.mlmodelc/…`. In that
   case `Bundle.main.bundleURL` itself acts as the model folder.

If neither is present, it falls back to a Hugging Face download — useful only
on machines that can reach `huggingface.co`.

### Re-downloading the model

If you ever need to recreate the model folder (different variant, fresh
checkout, etc.), the helper script lives at
[`stuttering app/stuttering app/WhisperModels/download_tiny_en.sh`](stuttering%20app/stuttering%20app/WhisperModels/download_tiny_en.sh)
in the worktree's history. It pulls the CoreML weights from
[`argmaxinc/whisperkit-coreml`](https://huggingface.co/argmaxinc/whisperkit-coreml)
and tokenizer files from
[`openai/whisper-tiny.en`](https://huggingface.co/openai/whisper-tiny.en).

## Privacy

- Microphone access is requested with a clear usage string (see
  `INFOPLIST_KEY_NSMicrophoneUsageDescription` in the project file).
- No audio, transcripts, or events leave the device. There is no analytics
  SDK, no remote logging, no cloud transcription.
- Microphone capture only runs while the user is actively in Live mode.

## Tuning notes

- **Streaming window**: 15 s with a 2 s tick. Whisper expects ~30 s context;
  shorter windows trip its no-speech threshold and produce empty results, so
  the streamer also lowers `noSpeechThreshold` to `0.3` and turns on
  `suppressBlank` / `skipSpecialTokens` to keep the live transcript clean.
- **Disfluency thresholds** are absolute, by letter count
  (`(≤1 char, 0.40 s)`, `(≤3, 0.65 s)`, `(≤6, 0.85 s)`, `(>6, 1.10 s)`).
  Calibrated on the SEP "I Have a Stutter" sample. Adaptive median tuning is
  on the roadmap.
- **Filler words** include English (`um`, `uh`, `er`, `ah`, `hmm`) and
  common Mandarin fillers (`呃`, `嗯`, `那个`, `就是`).

## License

WhisperKit is MIT-licensed; the Whisper weights are MIT-licensed by OpenAI.
This project's source is released under the MIT License — see
[`LICENSE`](LICENSE) (add one if you haven't).

## Acknowledgments

- [argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit) — the
  Apple-Silicon-native Whisper runtime that makes on-device ASR practical.
- [OpenAI Whisper](https://github.com/openai/whisper) — the underlying ASR
  model.
