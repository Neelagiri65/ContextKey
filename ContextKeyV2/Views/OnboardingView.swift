import SwiftUI

// MARK: - Onboarding View

/// First-launch experience: captures name and role, creates initial Persona pillar facts
struct OnboardingView: View {
    @EnvironmentObject var storageService: StorageService
    @State private var name = ""
    @State private var role = ""
    @State private var currentStep = 0

    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App branding
            VStack(spacing: 12) {
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
            }
            .padding(.bottom, 48)

            // Input fields
            VStack(spacing: 20) {
                if currentStep == 0 {
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
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What do you do?")
                            .font(.headline)

                        TextField("e.g. iOS Developer, Product Manager, Student", text: $role)
                            .font(.title3)
                            .textFieldStyle(.plain)
                            .padding(14)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .textContentType(.jobTitle)

                        Text("Optional — helps personalize your AI context")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }
            }
            .padding(.horizontal, 32)
            .animation(.smooth(duration: 0.3), value: currentStep)

            Spacer()

            // Continue button
            Button {
                if currentStep == 0 {
                    withAnimation {
                        currentStep = 1
                    }
                } else {
                    completeOnboarding()
                }
            } label: {
                Text(currentStep == 0 ? "Continue" : "Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .disabled(currentStep == 0 && name.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, 32)

            // Skip option for role
            if currentStep == 1 {
                Button("Skip for now") {
                    role = ""
                    completeOnboarding()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }

            // Step indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(currentStep == 0 ? Color.blue : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                Circle()
                    .fill(currentStep == 1 ? Color.blue : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
    }

    private func completeOnboarding() {
        // Save name and role as initial Persona facts
        var facts: [ContextFact] = []
        let source = ContextSource(
            platform: .manual,
            conversationCount: 0,
            lastConversationDate: Date()
        )

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty {
            facts.append(ContextFact(
                content: "Name: \(trimmedName)",
                layer: .coreIdentity,
                pillar: .persona,
                confidence: 1.0,
                sources: [source]
            ))
        }

        let trimmedRole = role.trimmingCharacters(in: .whitespaces)
        if !trimmedRole.isEmpty {
            facts.append(ContextFact(
                content: "Role: \(trimmedRole)",
                layer: .coreIdentity,
                pillar: .persona,
                confidence: 1.0,
                sources: [source]
            ))
        }

        // Save to storage
        if !facts.isEmpty {
            let record = ImportRecord(
                platform: .manual,
                conversationCount: 0,
                messageCount: 0,
                importedAt: Date(),
                factsExtracted: facts.count
            )
            try? storageService.mergeAndSave(newFacts: facts, from: .manual, stats: record)
        }

        // Mark onboarding complete
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set(trimmedName, forKey: "userName")
        onComplete()
    }
}
