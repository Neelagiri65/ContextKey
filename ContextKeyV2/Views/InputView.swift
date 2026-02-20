import SwiftUI
import UniformTypeIdentifiers

// MARK: - Input View (3 Equal Input Methods)

struct InputView: View {
    @EnvironmentObject var storageService: StorageService
    @State private var showVoiceRecorder = false
    @State private var showImport = false
    @State private var showManualEntry = false
    @State private var showProcessing = false
    @State private var pendingText: String?
    @State private var pendingParseResult: ParseResult?
    @State private var pendingClaudeMemory: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                    Text("Build Your Context")
                        .font(.title.bold())
                    Text("Choose how you'd like to add your context.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                Spacer()

                VStack(spacing: 16) {
                    InputMethodButton(
                        icon: "mic.fill",
                        title: "Speak it",
                        subtitle: "Record a voice note",
                        color: .blue
                    ) {
                        showVoiceRecorder = true
                    }

                    InputMethodButton(
                        icon: "doc.text.fill",
                        title: "Import chats",
                        subtitle: "From your AI apps",
                        color: .purple
                    ) {
                        showImport = true
                    }

                    InputMethodButton(
                        icon: "pencil.line",
                        title: "Type it",
                        subtitle: "Guided interview",
                        color: .green
                    ) {
                        showManualEntry = true
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
                Spacer()
            }
            .navigationTitle("")
            .sheet(isPresented: $showVoiceRecorder) {
                VoiceRecorderView { transcript in
                    pendingText = transcript
                    showProcessing = true
                }
            }
            .sheet(isPresented: $showImport) {
                ImportView { parseResult, claudeMemory in
                    pendingParseResult = parseResult
                    pendingClaudeMemory = claudeMemory
                    showProcessing = true
                }
            }
            .sheet(isPresented: $showManualEntry) {
                GuidedInputView { text in
                    pendingText = text
                    showProcessing = true
                }
            }
            .fullScreenCover(isPresented: $showProcessing) {
                ProcessingView(
                    parseResult: pendingParseResult,
                    claudeMemory: pendingClaudeMemory,
                    directText: pendingText
                )
            }
        }
    }
}

// MARK: - Input Method Button

struct InputMethodButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

