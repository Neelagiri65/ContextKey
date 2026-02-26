import Foundation
@preconcurrency import Speech
@preconcurrency import AVFoundation

// MARK: - Voice Service

/// Handles audio recording and speech-to-text transcription
@MainActor
final class VoiceService: ObservableObject {

    @Published var isRecording = false
    @Published var liveTranscript = ""
    @Published var finalTranscript = ""
    @Published var errorMessage: String?
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0.0

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var durationTimer: Timer?
    private var retryCount = 0

    static let maxDuration: TimeInterval = 90
    private static let maxRetries = 1

    init() {
        // Try current locale first, then en-US fallback
        let current = SFSpeechRecognizer(locale: Locale.current)
        if let current, current.isAvailable {
            speechRecognizer = current
        } else {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        }
    }

    // Note: Cleanup handled by reset() called from onDisappear/scenePhase in InlineVoiceTab.
    // deinit cannot access non-Sendable properties in Swift 6 @MainActor classes.

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

        if !speechAuth && !audioAuth {
            errorMessage = "Microphone and Speech Recognition access are required. Enable them in Settings."
        } else if !speechAuth {
            errorMessage = "Speech Recognition access is required. Enable it in Settings > Privacy."
        } else if !audioAuth {
            errorMessage = "Microphone access is required. Enable it in Settings > Privacy."
        }

        return speechAuth && audioAuth
    }

    // MARK: - Recording + Live Transcription

    func startRecording() {
        guard !isRecording else { return }

        errorMessage = nil
        if retryCount == 0 {
            liveTranscript = ""
            finalTranscript = ""
            recordingDuration = 0
        }
        audioLevel = 0.0

        guard let recognizer = speechRecognizer else {
            errorMessage = "Speech recognition is not available for your language."
            return
        }

        guard recognizer.isAvailable else {
            errorMessage = "Speech recognition is temporarily unavailable. Please try again."
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            audioEngine = engine

            let request = SFSpeechAudioBufferRecognitionRequest()
            recognitionRequest = request

            // KEY FIX: Do NOT force on-device recognition
            // Even when supportsOnDeviceRecognition is true, the on-device model
            // may not be downloaded. Setting requiresOnDeviceRecognition = true
            // causes silent failures. Let the system decide.
            request.requiresOnDeviceRecognition = false
            request.shouldReportPartialResults = true
            request.addsPunctuation = true

            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
                errorMessage = "Invalid audio format. Please check your microphone."
                return
            }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                request.append(buffer)

                // Calculate audio level for visualization
                guard let channelData = buffer.floatChannelData?[0] else { return }
                let frameLength = Int(buffer.frameLength)
                guard frameLength > 0 else { return }

                var sum: Float = 0
                for i in 0..<frameLength {
                    sum += abs(channelData[i])
                }
                let average = sum / Float(frameLength)
                let level = min(1.0, average * 10)
                Task { @MainActor in
                    self?.audioLevel = level
                }
            }

            engine.prepare()
            try engine.start()

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }

                    if let result {
                        self.liveTranscript = result.bestTranscription.formattedString
                        if result.isFinal {
                            self.finalTranscript = result.bestTranscription.formattedString
                            self.stopRecording()
                        }
                    }

                    if let error = error as? NSError {
                        // Don't show error if we intentionally stopped
                        guard self.isRecording else { return }

                        switch error.code {
                        case 201:
                            self.errorMessage = "No speech detected. Please try speaking clearly."
                        case 203:
                            break // Normal cancel
                        case 209:
                            self.errorMessage = "Recognition interrupted. Please try again."
                        case 1100, 1101:
                            // Connection invalidated — common on first attempt, auto-retry once
                            self.stopRecording()
                            if self.retryCount < Self.maxRetries {
                                self.retryCount += 1
                                Task {
                                    try? await Task.sleep(for: .milliseconds(500))
                                    self.startRecording()
                                }
                            } else {
                                self.errorMessage = "Speech engine error. Please try again."
                            }
                        default:
                            self.errorMessage = "Recognition error (\(error.code)): \(error.localizedDescription)"
                            self.stopRecording()
                        }
                    }
                }
            }

            isRecording = true

            // Duration timer with auto-stop at 90 seconds
            durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.recordingDuration += 1
                    if self.recordingDuration >= Self.maxDuration {
                        self.stopRecording()
                    }
                }
            }

        } catch {
            cleanupAudio()
            errorMessage = "Could not start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        durationTimer?.invalidate()
        durationTimer = nil

        // End recognition first, then stop engine
        recognitionRequest?.endAudio()

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioLevel = 0.0

        // Release audio session immediately — don't hold the mic
        cleanupAudio()

        // Finalize transcript asynchronously (audio session already released)
        if finalTranscript.isEmpty && !liveTranscript.isEmpty {
            finalTranscript = liveTranscript
        }
    }

    func reset() {
        if isRecording {
            isRecording = false
            durationTimer?.invalidate()
            durationTimer = nil
            recognitionTask?.cancel()
            recognitionRequest?.endAudio()
            audioEngine?.stop()
            audioEngine?.inputNode.removeTap(onBus: 0)
        }

        liveTranscript = ""
        finalTranscript = ""
        errorMessage = nil
        recordingDuration = 0
        audioLevel = 0.0
        retryCount = 0
        cleanupAudio()
    }

    var remainingSeconds: TimeInterval {
        max(0, Self.maxDuration - recordingDuration)
    }

    private func cleanupAudio() {
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
