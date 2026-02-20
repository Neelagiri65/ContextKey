import SwiftUI
import UniformTypeIdentifiers

// MARK: - Input View (Single Sheet — Voice / Type / Import)

enum InputTab: String, CaseIterable {
    case voice = "Voice"
    case type = "Type"
    case importChat = "Import"
}

struct InputView: View {
    @EnvironmentObject var storageService: StorageService
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab: InputTab = .voice
    @State private var showImport = false
    @State private var showProcessing = false
    @State private var pendingText: String?
    @State private var pendingParseResult: ParseResult?
    @State private var pendingClaudeMemory: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented control
                Picker("Input Method", selection: $selectedTab) {
                    ForEach(InputTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                // Tab content
                switch selectedTab {
                case .voice:
                    InlineVoiceTab { transcript in
                        pendingText = transcript
                        showProcessing = true
                    }
                case .type:
                    InlineTypeTab { text in
                        pendingText = text
                        showProcessing = true
                    }
                case .importChat:
                    InlineImportTab {
                        showImport = true
                    }
                }
            }
            .navigationTitle("Add Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showImport) {
                ImportView { parseResult, claudeMemory in
                    pendingParseResult = parseResult
                    pendingClaudeMemory = claudeMemory
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

// MARK: - Inline Voice Tab

struct InlineVoiceTab: View {
    @StateObject private var voiceService = VoiceService()
    @State private var hasPermission = false
    @State private var permissionChecked = false
    let onComplete: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !permissionChecked {
                Spacer()
                ProgressView("Checking permissions...")
                Spacer()
            } else if !hasPermission {
                permissionDeniedView
            } else {
                recorderContent
            }
        }
        .task {
            hasPermission = await voiceService.requestPermissions()
            permissionChecked = true
        }
    }

    private var recorderContent: some View {
        VStack(spacing: 16) {
            // Transcript area
            ScrollView {
                Text(voiceService.liveTranscript.isEmpty
                     ? "Tap the record button and start speaking..."
                     : voiceService.liveTranscript)
                    .font(.body)
                    .foregroundStyle(voiceService.liveTranscript.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.top, 12)

            if let error = voiceService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            // Waveform
            if voiceService.isRecording {
                waveformView
                    .frame(height: 32)
                    .padding(.horizontal)
            }

            // Controls
            HStack(spacing: 32) {
                // Discard
                Button { voiceService.reset() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .opacity(voiceService.liveTranscript.isEmpty ? 0.3 : 1.0)
                .disabled(voiceService.liveTranscript.isEmpty)

                // Record / Stop
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
                            .frame(width: 56, height: 56)
                        if voiceService.isRecording {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white)
                                .frame(width: 20, height: 20)
                        } else {
                            Circle()
                                .fill(.white)
                                .frame(width: 22, height: 22)
                        }
                    }
                }

                // Timer
                VStack(spacing: 2) {
                    Text(formatDuration(voiceService.recordingDuration))
                        .font(.body.monospacedDigit().bold())
                        .foregroundStyle(voiceService.isRecording ? .red : .primary)
                    Text(voiceService.isRecording ? "\(Int(voiceService.remainingSeconds))s left" : "max 90s")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 60)
            }
            .padding(.vertical, 12)

            // Done button (when transcript is ready)
            if !voiceService.isRecording && !voiceService.liveTranscript.isEmpty {
                Button {
                    let transcript = voiceService.finalTranscript.isEmpty
                        ? voiceService.liveTranscript
                        : voiceService.finalTranscript
                    onComplete(transcript)
                } label: {
                    Text("Extract Context")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
            }

            Spacer().frame(height: 8)
        }
    }

    private var waveformView: some View {
        HStack(spacing: 3) {
            ForEach(0..<20, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red.opacity(0.7))
                    .frame(width: 4, height: waveBarHeight(for: index))
                    .animation(.easeInOut(duration: 0.15), value: voiceService.audioLevel)
            }
        }
    }

    private func waveBarHeight(for index: Int) -> CGFloat {
        let base: CGFloat = 4
        let maxH: CGFloat = 28
        let level = CGFloat(voiceService.audioLevel)
        let wave = sin(CGFloat(index) / 20.0 * .pi * 2 + level * 10) * 0.5 + 0.5
        return base + (maxH - base) * level * wave
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "mic.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Microphone & Speech access required")
                .font(.headline)
            Text("Enable in Settings > Privacy.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Inline Type Tab

struct InlineTypeTab: View {
    @State private var currentStep = 0
    @State private var answers: [String] = Array(repeating: "", count: 7)
    @FocusState private var isFieldFocused: Bool
    let onComplete: (String) -> Void

    private let steps: [(question: String, placeholder: String, pillar: ContextPillar, icon: String)] = [
        ("What's your name and what do you do?", "e.g. Sarah, Senior iOS Developer at a fintech startup", .persona, "person.fill"),
        ("What tools and technologies do you use?", "e.g. Swift, SwiftUI, Python, Xcode, Figma", .skillsAndStack, "wrench.and.screwdriver.fill"),
        ("How do you prefer AI to respond?", "e.g. Concise, code-first, no fluff", .communicationStyle, "text.bubble.fill"),
        ("What are you working on right now?", "e.g. Building a privacy-first AI identity app", .activeProjects, "hammer.fill"),
        ("What are your current goals?", "e.g. Ship to TestFlight by February", .goalsAndPriorities, "target"),
        ("Any constraints or things to avoid?", "e.g. No cloud processing, privacy-first", .constraints, "shield.fill"),
        ("How do you typically use AI?", "e.g. Code reviews, debugging, brainstorming", .workPatterns, "arrow.triangle.branch"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Progress
            stepProgress
                .padding(.horizontal)
                .padding(.top, 12)

            // Current step
            ScrollView {
                currentStepView
                    .padding(.horizontal)
                    .padding(.top, 16)
            }

            Spacer()

            // Navigation
            stepNavigation
                .padding(.horizontal)
                .padding(.bottom, 16)
        }
        .onAppear { isFieldFocused = true }
    }

    private var stepProgress: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(0..<steps.count, id: \.self) { i in
                    Capsule()
                        .fill(i < currentStep ? Color.blue : (i == currentStep ? Color.blue.opacity(0.5) : Color(.systemGray4)))
                        .frame(height: 3)
                }
            }
            HStack {
                Text("Step \(currentStep + 1) of \(steps.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var currentStepView: some View {
        let step = steps[currentStep]
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: step.icon)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(pillarColor(step.pillar))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(step.question)
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField(step.placeholder, text: $answers[currentStep], axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .focused($isFieldFocused)
        }
    }

    private var stepNavigation: some View {
        HStack {
            if currentStep > 0 {
                Button {
                    withAnimation(.smooth) { currentStep -= 1 }
                    isFieldFocused = true
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if currentStep < steps.count - 1 {
                Button {
                    withAnimation(.smooth) { currentStep += 1 }
                    isFieldFocused = true
                } label: {
                    Text(answers[currentStep].trimmingCharacters(in: .whitespaces).isEmpty ? "Skip" : "Next")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
            } else {
                Button {
                    onComplete(compileAnswers())
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("Extract Context")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(hasAnyAnswer ? Color.blue : Color.gray)
                    .clipShape(Capsule())
                }
                .disabled(!hasAnyAnswer)
            }
        }
    }

    private var hasAnyAnswer: Bool {
        answers.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func compileAnswers() -> String {
        var parts: [String] = []
        for (i, answer) in answers.enumerated() {
            let trimmed = answer.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            parts.append("[\(steps[i].pillar.displayName)] \(trimmed)")
        }
        return parts.joined(separator: "\n\n")
    }

    private func pillarColor(_ pillar: ContextPillar) -> Color {
        switch pillar.color {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "gray": return .gray
        case "teal": return .teal
        default: return .blue
        }
    }
}

// MARK: - Inline Import Tab

struct InlineImportTab: View {
    let onTapImport: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "doc.text.fill")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            Text("Import Chat Exports")
                .font(.title3.bold())

            Text("Import conversations from ChatGPT, Claude, Gemini, or Perplexity to extract your context automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                onTapImport()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Choose Platform & File")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }
}
