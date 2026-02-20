import SwiftUI

// MARK: - Voice Recorder View (Floating Compact Recorder)

struct VoiceRecorderView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var voiceService = VoiceService()
    @State private var hasPermission = false
    @State private var permissionChecked = false
    let onComplete: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !permissionChecked {
                    Spacer()
                    ProgressView("Checking permissions...")
                    Spacer()
                } else if !hasPermission {
                    permissionDeniedView
                } else {
                    recorderView
                }
            }
            .navigationTitle("Voice Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        voiceService.reset()
                        dismiss()
                    }
                }

                if !voiceService.isRecording && !voiceService.liveTranscript.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            let transcript = voiceService.finalTranscript.isEmpty
                                ? voiceService.liveTranscript
                                : voiceService.finalTranscript
                            dismiss()
                            onComplete(transcript)
                        }
                        .fontWeight(.semibold)
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
        VStack(spacing: 20) {
            // Live transcript area
            ScrollView {
                Text(voiceService.liveTranscript.isEmpty
                     ? "Tap record and start speaking..."
                     : voiceService.liveTranscript)
                    .font(.body)
                    .foregroundStyle(voiceService.liveTranscript.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            .padding(.top, 8)

            // Error message
            if let error = voiceService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            // Floating recorder panel
            floatingRecorderPanel
                .padding(.bottom, 8)
        }
    }

    // MARK: - Floating Recorder Panel

    private var floatingRecorderPanel: some View {
        VStack(spacing: 16) {
            // Waveform / level indicator
            if voiceService.isRecording {
                waveformView
                    .frame(height: 40)
                    .padding(.horizontal)
            }

            // Timer and controls
            HStack(spacing: 32) {
                // Discard button
                Button {
                    voiceService.reset()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .opacity(voiceService.liveTranscript.isEmpty ? 0.3 : 1.0)
                .disabled(voiceService.liveTranscript.isEmpty)

                // Record / Stop button
                Button {
                    if voiceService.isRecording {
                        voiceService.stopRecording()
                    } else {
                        voiceService.startRecording()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(voiceService.isRecording ? Color.red : Color.blue)
                            .frame(width: 64, height: 64)
                            .shadow(color: voiceService.isRecording ? .red.opacity(0.3) : .blue.opacity(0.3), radius: 8)

                        if voiceService.isRecording {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white)
                                .frame(width: 22, height: 22)
                        } else {
                            Circle()
                                .fill(.white)
                                .frame(width: 24, height: 24)
                        }
                    }
                }

                // Timer display
                VStack(spacing: 2) {
                    Text(formatDuration(voiceService.recordingDuration))
                        .font(.title3.monospacedDigit().bold())
                        .foregroundStyle(voiceService.isRecording ? .red : .primary)

                    if voiceService.isRecording {
                        Text("\(Int(voiceService.remainingSeconds))s left")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("max 90s")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 70)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
        )
        .padding(.horizontal)
    }

    // MARK: - Waveform

    private var waveformView: some View {
        HStack(spacing: 3) {
            ForEach(0..<20, id: \.self) { index in
                let height = waveBarHeight(for: index)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red.opacity(0.7))
                    .frame(width: 4, height: height)
                    .animation(.easeInOut(duration: 0.15), value: voiceService.audioLevel)
            }
        }
    }

    private func waveBarHeight(for index: Int) -> CGFloat {
        let base: CGFloat = 4
        let maxHeight: CGFloat = 36
        let level = CGFloat(voiceService.audioLevel)
        // Create a wave pattern that varies by position
        let position = CGFloat(index) / 20.0
        let wave = sin(position * .pi * 2 + level * 10) * 0.5 + 0.5
        return base + (maxHeight - base) * level * wave
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

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)

            Spacer()
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
