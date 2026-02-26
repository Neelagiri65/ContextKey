import SwiftUI

// MARK: - Onboarding View (Tiered Day 1 Identity Bootstrap)

/// Multi-step onboarding that gives value immediately:
/// Step 0: Welcome + name
/// Steps 1-5: Guided questions with live pillar preview
/// Step 6: Paste a conversation (optional)
/// Step 7: Profile ready → HomeView
struct OnboardingView: View {
    @EnvironmentObject var storageService: StorageService
    @State private var name = ""
    @State private var currentStep = 0
    @State private var answers: [String] = Array(repeating: "", count: 5)
    @State private var pastedConversation = ""
    @State private var isExtracting = false
    @State private var extractedPasteFacts: [ContextFact] = []
    @State private var extractionError: String?
    @State private var didAttemptExtraction = false
    @State private var savedFacts: [ContextFact] = []
    @State private var saveError: String?
    @State private var isTransitioning = false
    @FocusState private var isFieldFocused: Bool

    let onComplete: () -> Void

    // 5 guided questions (skip Communication Style and Work Patterns — those come from chat analysis)
    private let questions: [(question: String, placeholder: String, pillar: ContextPillar, icon: String)] = [
        ("What do you do?", "e.g. Senior iOS Developer at a fintech startup", .persona, "person.fill"),
        ("What tools & tech do you use?", "e.g. Swift, SwiftUI, Python, Xcode, Figma", .skillsAndStack, "wrench.and.screwdriver.fill"),
        ("What are you working on?", "e.g. Building a privacy-first AI identity app", .activeProjects, "hammer.fill"),
        ("What are your goals right now?", "e.g. Ship to TestFlight by February, learn ML", .goalsAndPriorities, "target"),
        ("Any constraints or things to avoid?", "e.g. No cloud processing, privacy-first, iOS only", .constraints, "shield.fill"),
    ]

    // Total steps: 0 (welcome) + 5 (questions) + 1 (paste) + 1 (ready) = 8
    private let totalSteps = 8

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar (hidden on welcome and ready steps)
            if currentStep > 0 && currentStep < totalSteps - 1 {
                progressBar
                    .padding(.horizontal, 32)
                    .padding(.top, 12)
            }

            Spacer()

            // Step content
            Group {
                switch currentStep {
                case 0:
                    welcomeStep
                case 1...5:
                    questionStep(index: currentStep - 1)
                case 6:
                    pasteStep
                case 7:
                    readyStep
                default:
                    EmptyView()
                }
            }
            .animation(.smooth(duration: 0.3), value: currentStep)

            Spacer()

            // Mini pillar preview (shown during questions and paste)
            if currentStep >= 1 && currentStep <= 6 {
                miniPillarPreview
                    .padding(.bottom, 8)
            }

            // Navigation buttons
            navigationButtons
                .padding(.horizontal, 32)
                .padding(.bottom, 16)

            // Step dots
            stepDots
                .padding(.bottom, 32)
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray5))
                    .frame(height: 4)

                Capsule()
                    .fill(Color.blue)
                    .frame(width: geo.size.width * CGFloat(currentStep) / CGFloat(totalSteps - 1), height: 4)
                    .animation(.smooth, value: currentStep)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "key.fill")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("ContextKey")
                .font(.largeTitle.bold())

            Text("Your portable AI identity")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("What's your name?")
                    .font(.headline)

                TextField("Your name", text: $name)
                    .font(.title3)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .focused($isFieldFocused)
            }
            .padding(.horizontal, 32)
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    // MARK: - Steps 1-5: Guided Questions

    private func questionStep(index: Int) -> some View {
        let q = questions[index]
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: q.icon)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(pillarColor(q.pillar))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(q.question)
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField(q.placeholder, text: $answers[index], axis: .vertical)
                .lineLimit(2...6)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .focused($isFieldFocused)
        }
        .padding(.horizontal, 32)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .onAppear { isFieldFocused = true }
    }

    // MARK: - Step 6: Paste a Conversation

    private var pasteStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 36))
                .foregroundStyle(.blue)

            Text("Make it richer")
                .font(.title2.bold())

            Text("Paste your best AI conversation and we'll extract even more about you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            TextEditor(text: $pastedConversation)
                .frame(height: 120)
                .padding(8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    Group {
                        if pastedConversation.isEmpty {
                            Text("Paste a conversation snippet here...")
                                .foregroundStyle(.tertiary)
                                .padding(12)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )
                .focused($isFieldFocused)

            if isExtracting {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Extracting context...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !extractedPasteFacts.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Found \(extractedPasteFacts.count) new facts!")
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)
                }
            }

            if let error = extractionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let error = saveError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 32)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    // MARK: - Step 7: Ready

    private var readyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: saveError == nil ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(saveError == nil ? .green : .orange)

            Text(saveError == nil ? "Your profile is ready!" : "Profile created with issues")
                .font(.title.bold())

            let factCount = savedFacts.count
            let filledPillars = Set(savedFacts.map { $0.pillar }).count

            VStack(spacing: 4) {
                Text("\(factCount) facts across \(filledPillars) pillars")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let error = saveError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    Text("Import more anytime from Home.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .transition(.asymmetric(
            insertion: .scale.combined(with: .opacity),
            removal: .opacity
        ))
    }

    // MARK: - Mini Pillar Preview

    /// The pillars relevant to the current onboarding step
    private var visiblePillars: [ContextPillar] {
        if currentStep >= 6 {
            // Paste step: extraction can populate any pillar
            return ContextPillar.allCases
        } else {
            // Steps 1-5: only show the 5 onboarding pillars
            return questions.map { $0.pillar }
        }
    }

    /// The pillar being targeted by the current question (nil on paste/ready steps)
    private var currentQuestionPillar: ContextPillar? {
        guard currentStep >= 1 && currentStep <= 5 else { return nil }
        return questions[currentStep - 1].pillar
    }

    private var miniPillarPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visiblePillars, id: \.self) { pillar in
                    let count = savedFacts.filter { $0.pillar == pillar }.count
                    let isCurrentTarget = pillar == currentQuestionPillar
                    let isFilled = count > 0

                    HStack(spacing: 4) {
                        Image(systemName: pillar.iconName)
                            .font(.system(size: 10))
                        if isFilled {
                            Text("\(count)")
                                .font(.system(size: 10).bold())
                        }
                    }
                    .foregroundStyle(isFilled ? .white : (isCurrentTarget ? pillarColor(pillar) : .secondary))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(isFilled ? pillarColor(pillar) : Color(.systemGray5))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(isCurrentTarget && !isFilled ? pillarColor(pillar) : .clear, lineWidth: 1.5)
                    )
                    .animation(.smooth(duration: 0.3), value: count)
                    .animation(.smooth(duration: 0.3), value: isCurrentTarget)
                }
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack {
            // Back button (not on welcome or ready)
            if currentStep > 0 && currentStep < totalSteps - 1 {
                Button {
                    withAnimation { currentStep -= 1 }
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

            // Main action button
            Button {
                handleNext()
            } label: {
                Text(nextButtonLabel)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(nextButtonDisabled ? Color.gray : Color.blue)
                    .clipShape(Capsule())
            }
            .disabled(nextButtonDisabled)
        }
    }

    private var nextButtonLabel: String {
        switch currentStep {
        case 0: return "Continue"
        case 1...5:
            let answer = answers[currentStep - 1].trimmingCharacters(in: .whitespaces)
            return answer.isEmpty ? "Skip" : "Next"
        case 6:
            if isExtracting { return "Extracting..." }
            if !extractedPasteFacts.isEmpty || didAttemptExtraction { return "Next" }
            return pastedConversation.trimmingCharacters(in: .whitespaces).isEmpty ? "Skip" : "Extract"
        case 7: return "Get Started"
        default: return "Next"
        }
    }

    private var nextButtonDisabled: Bool {
        if isTransitioning { return true }
        if currentStep == 0 {
            return name.trimmingCharacters(in: .whitespaces).isEmpty
        }
        if currentStep == 6 && isExtracting {
            return true
        }
        return false
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Circle()
                    .fill(i == currentStep ? Color.blue : Color.secondary.opacity(0.3))
                    .frame(width: i == currentStep ? 8 : 6, height: i == currentStep ? 8 : 6)
                    .animation(.smooth, value: currentStep)
            }
        }
    }

    // MARK: - Actions

    private func handleNext() {
        switch currentStep {
        case 0:
            // Save name immediately as a persona fact
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            guard !trimmedName.isEmpty else { return }
            UserDefaults.standard.set(trimmedName, forKey: "userName")
            saveFact("Name: \(trimmedName)", pillar: .persona)
            withAnimation { currentStep = 1 }

        case 1...5:
            // Save answer as a fact if non-empty
            let index = currentStep - 1
            let answer = answers[index].trimmingCharacters(in: .whitespaces)
            if !answer.isEmpty {
                isTransitioning = true
                saveFact(answer, pillar: questions[index].pillar)
                // Delay step advance so user sees the capsule fill animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    withAnimation { currentStep += 1 }
                    isTransitioning = false
                }
            } else {
                withAnimation { currentStep += 1 }
            }

        case 6:
            // Paste step: extract, skip, or advance after extraction
            let pasted = pastedConversation.trimmingCharacters(in: .whitespaces)
            if pasted.isEmpty || !extractedPasteFacts.isEmpty || didAttemptExtraction {
                // Skip, already extracted, or extraction returned 0/failed — move to ready
                withAnimation { currentStep = 7 }
            } else {
                // Run extraction
                Task { await extractFromPaste(pasted) }
            }

        case 7:
            // Finish onboarding
            completeOnboarding()

        default:
            break
        }
    }

    private func saveFact(_ content: String, pillar: ContextPillar) {
        let source = ContextSource(
            platform: .manual,
            conversationCount: 0,
            lastConversationDate: Date()
        )

        let layer: ContextLayer = (pillar == .activeProjects || pillar == .goalsAndPriorities)
            ? .currentContext : .coreIdentity

        let fact = ContextFact(
            content: content,
            layer: layer,
            pillar: pillar,
            confidence: 1.0,
            sources: [source]
        )

        withAnimation(.smooth(duration: 0.3)) {
            savedFacts.append(fact)
        }

        // Save incrementally — surface errors so user knows if persistence failed
        let record = ImportRecord(
            platform: .manual,
            conversationCount: 0,
            messageCount: 0,
            importedAt: Date(),
            factsExtracted: 1
        )
        do {
            try storageService.mergeAndSave(newFacts: [fact], from: .manual, stats: record)
            saveError = nil
        } catch {
            saveError = "Couldn't save: \(error.localizedDescription)"
            print("[Onboarding] Save failed: \(error)")
        }
    }

    private func extractFromPaste(_ text: String) async {
        isExtracting = true
        extractionError = nil

        defer {
            isExtracting = false
            didAttemptExtraction = true
        }

        let extractionService = ExtractionService()
        do {
            let facts = try await extractionService.extractFromSingleInput(text)
            extractedPasteFacts = facts
            withAnimation(.smooth(duration: 0.3)) {
                savedFacts.append(contentsOf: facts)
            }

            if facts.isEmpty {
                extractionError = "No facts found. Tap Next to continue, or paste different text and try again."
                return
            }

            // Save extracted facts
            let record = ImportRecord(
                platform: .manual,
                conversationCount: 1,
                messageCount: 1,
                importedAt: Date(),
                factsExtracted: facts.count
            )
            do {
                try storageService.mergeAndSave(newFacts: facts, from: .manual, stats: record)
            } catch {
                saveError = "Extracted facts but couldn't save: \(error.localizedDescription)"
                print("[Onboarding] Paste save failed: \(error)")
            }
        } catch {
            extractionError = "Extraction failed. Tap Next to continue, or try pasting different text."
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        onComplete()
    }

    // MARK: - Helpers

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
