import Foundation
import Speech
import AVFoundation

// MARK: - Voice Service

/// Handles audio recording and on-device speech-to-text transcription
@MainActor
final class VoiceService: ObservableObject {

    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var liveTranscript = ""
    @Published var finalTranscript = ""
    @Published var errorMessage: String?
    @Published var recordingDuration: TimeInterval = 0

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var durationTimer: Timer?

    static let maxDuration: TimeInterval = 300 // 5 minutes

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: - Authorization

    func requestPermissions() async -> Bool {
        let speechAuth = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        let audioAuth: Bool
        if #available(iOS 17.0, *) {
            audioAuth = await AVAudioApplication.requestRecordPermission()
        } else {
            audioAuth = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        return speechAuth && audioAuth
    }

    // MARK: - Recording + Live Transcription

    func startRecording() {
        guard !isRecording else { return }

        errorMessage = nil
        liveTranscript = ""
        finalTranscript = ""
        recordingDuration = 0

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition is not available on this device."
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else { return }

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let request = recognitionRequest else { return }

            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self = self else { return }
                    if let result = result {
                        self.liveTranscript = result.bestTranscription.formattedString
                        if result.isFinal {
                            self.finalTranscript = result.bestTranscription.formattedString
                        }
                    }
                    if let error = error {
                        // Don't show error if we intentionally stopped
                        if self.isRecording {
                            self.errorMessage = error.localizedDescription
                        }
                    }
                }
            }

            isRecording = true

            // Duration timer
            durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.recordingDuration += 1
                    if self.recordingDuration >= Self.maxDuration {
                        self.stopRecording()
                    }
                }
            }

        } catch {
            errorMessage = "Could not start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        isRecording = false
        durationTimer?.invalidate()
        durationTimer = nil

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        // Wait a moment for final transcription
        Task {
            try? await Task.sleep(for: .seconds(1))
            if finalTranscript.isEmpty {
                finalTranscript = liveTranscript
            }
        }
    }

    func reset() {
        stopRecording()
        liveTranscript = ""
        finalTranscript = ""
        errorMessage = nil
        recordingDuration = 0
    }
}
