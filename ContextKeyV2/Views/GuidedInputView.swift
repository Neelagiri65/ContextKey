import SwiftUI

// MARK: - Guided Input View (Step-by-Step Form Wizard)

/// A clean form wizard that walks the user through 7 context pillars.
/// Each step is a full-screen card with a question, text field, and progress indicator.
struct GuidedInputView: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentStep = 0
    @State private var answers: [String]
    @State private var isComplete = false
    @FocusState private var isFieldFocused: Bool

    let onComplete: (String) -> Void

    private let steps: [(question: String, placeholder: String, pillar: ContextPillar, icon: String)] = [
        (
            "What's your name and what do you do?",
            "e.g. Sarah, Senior iOS Developer at a fintech startup",
            .persona,
            "person.fill"
        ),
        (
            "What tools and technologies do you use?",
            "e.g. Swift, SwiftUI, Python, Xcode, Figma, Git",
            .skillsAndStack,
            "wrench.and.screwdriver.fill"
        ),
        (
            "How do you prefer AI to respond?",
            "e.g. Concise, code-first, no fluff, use bullet points",
            .communicationStyle,
            "text.bubble.fill"
        ),
        (
            "What are you working on right now?",
            "e.g. Building a privacy-first AI identity app called ContextKey",
            .activeProjects,
            "hammer.fill"
        ),
        (
            "What are your current goals?",
            "e.g. Ship to TestFlight by February, grow to 1K users",
            .goalsAndPriorities,
            "target"
        ),
        (
            "Any constraints or things to avoid?",
            "e.g. No cloud processing, privacy-first, iOS only",
            .constraints,
            "shield.fill"
        ),
        (
            "How do you typically use AI?",
            "e.g. Code reviews, debugging, writing docs, brainstorming",
            .workPatterns,
            "arrow.triangle.branch"
        ),
    ]

    init(onComplete: @escaping (String) -> Void) {
        self.onComplete = onComplete
        _answers = State(initialValue: Array(repeating: "", count: 7))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                progressBar
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                // Step content
                TabView(selection: $currentStep) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        stepCard(index: index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.smooth, value: currentStep)

                // Bottom navigation
                bottomBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
            .navigationTitle("Build Your Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                isFieldFocused = true
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Capsule()
                        .fill(progressColor(for: index))
                        .frame(height: 4)
                }
            }

            HStack {
                Text("Step \(currentStep + 1) of \(steps.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(steps[currentStep].pillar.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(pillarColor(steps[currentStep].pillar))
            }
        }
    }

    private func progressColor(for index: Int) -> Color {
        if index < currentStep {
            return .blue
        } else if index == currentStep {
            return .blue.opacity(0.6)
        } else {
            return Color(.systemGray4)
        }
    }

    // MARK: - Step Card

    private func stepCard(index: Int) -> some View {
        let step = steps[index]
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer().frame(height: 16)

                // Icon + question
                HStack(spacing: 12) {
                    Image(systemName: step.icon)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(pillarColor(step.pillar))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text(step.question)
                        .font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Text editor
                TextEditor(text: $answers[index])
                    .font(.body)
                    .frame(minHeight: 120, maxHeight: 200)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topLeading) {
                        if answers[index].isEmpty {
                            Text(step.placeholder)
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(16)
                                .allowsHitTesting(false)
                        }
                    }
                    .focused($isFieldFocused)

                // Skip hint
                if answers[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("You can skip this and come back later")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 16) {
            // Back button
            if currentStep > 0 {
                Button {
                    withAnimation(.smooth) {
                        currentStep -= 1
                    }
                    isFieldFocused = true
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 48, height: 48)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Next / Done button
            if currentStep < steps.count - 1 {
                Button {
                    withAnimation(.smooth) {
                        currentStep += 1
                    }
                    isFieldFocused = true
                } label: {
                    HStack(spacing: 6) {
                        Text(answers[currentStep].trimmingCharacters(in: .whitespaces).isEmpty ? "Skip" : "Next")
                            .font(.headline)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .clipShape(Capsule())
                }
            } else {
                Button {
                    let compiled = compileAnswers()
                    dismiss()
                    onComplete(compiled)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("Extract Context")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(hasAnyAnswer ? Color.blue : Color.gray)
                    .clipShape(Capsule())
                }
                .disabled(!hasAnyAnswer)
            }
        }
    }

    // MARK: - Helpers

    private var hasAnyAnswer: Bool {
        answers.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func compileAnswers() -> String {
        var parts: [String] = []
        for (index, answer) in answers.enumerated() {
            let trimmed = answer.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            parts.append("[\(steps[index].pillar.displayName)] \(trimmed)")
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
