import SwiftUI

// MARK: - Voice Recorder View

struct VoiceRecorderView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var voiceService = VoiceService()
    @State private var hasPermission = false
    @State private var permissionChecked = false
    let onComplete: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if !permissionChecked {
                    ProgressView("Checking permissions...")
                } else if !hasPermission {
                    permissionDeniedView
                } else {
                    recorderView
                }
            }
            .navigationTitle("Speak it")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        voiceService.reset()
                        dismiss()
                    }
                }
            }
            .task {
                hasPermission = await voiceService.requestPermissions()
                permissionChecked = true
            }
        }
    }

    // MARK: - Recorder View

    private var recorderView: some View {
        VStack(spacing: 32) {
            Spacer()

            // Live transcript
            ScrollView {
                Text(voiceService.liveTranscript.isEmpty ? "Tap the button and start speaking..." : voiceService.liveTranscript)
                    .font(.body)
                    .foregroundStyle(voiceService.liveTranscript.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(maxHeight: 300)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)

            // Duration
            if voiceService.isRecording {
                Text(formatDuration(voiceService.recordingDuration))
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(.red)
            }

            // Record button
            Button {
                if voiceService.isRecording {
                    voiceService.stopRecording()
                } else {
                    voiceService.startRecording()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(voiceService.isRecording ? .red : .blue)
                        .frame(width: 80, height: 80)

                    Image(systemName: voiceService.isRecording ? "stop.fill" : "mic.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                }
            }

            // Done button (after recording)
            if !voiceService.isRecording && !voiceService.liveTranscript.isEmpty {
                Button {
                    let transcript = voiceService.finalTranscript.isEmpty ? voiceService.liveTranscript : voiceService.finalTranscript
                    dismiss()
                    onComplete(transcript)
                } label: {
                    Text("Use this transcript")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
            }

            if let error = voiceService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Spacer()
        }
    }

    // MARK: - Permission Denied

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "mic.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Microphone & Speech access required")
                .font(.headline)
            Text("Enable in Settings > Privacy > Microphone and Speech Recognition.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
