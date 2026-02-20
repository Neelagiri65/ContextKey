import SwiftUI

// MARK: - Processing View (SLM Extraction + Review)

struct ProcessingView: View {
    @EnvironmentObject var storageService: StorageService
    @Environment(\.dismiss) var dismiss
    @StateObject private var extractionService = ExtractionService()

    let parseResult: ParseResult?
    let claudeMemory: String?
    let directText: String?

    @State private var reviewMode = false
    @State private var editableFacts: [ContextFact] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if extractionService.isProcessing {
                    processingView
                } else if reviewMode {
                    reviewView
                } else if let error = errorMessage {
                    errorView(error)
                } else {
                    ProgressView("Starting...")
                }
            }
            .navigationTitle(reviewMode ? "Review Your Context" : "Processing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await startExtraction()
            }
        }
    }

    // MARK: - Processing View

    private var processingView: some View {
        VStack(spacing: 32) {
            Spacer()

            ProgressView(value: extractionService.progress) {
                Text(extractionService.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .progressViewStyle(.linear)
            .padding(.horizontal, 40)

            if let result = parseResult {
                VStack(spacing: 4) {
                    Text("\(result.totalConversations) conversations")
                        .font(.title3.bold())
                    Text("\(result.totalMessages) messages")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    // MARK: - Review View

    private var reviewView: some View {
        List {
            ForEach(ContextLayer.allCases, id: \.self) { layer in
                let layerFacts = editableFacts.filter { $0.layer == layer }
                if !layerFacts.isEmpty {
                    Section(header: Text(layerTitle(layer))) {
                        ForEach(Array(layerFacts.enumerated()), id: \.element.id) { _, fact in
                            FactRow(fact: fact)
                        }
                        .onDelete { offsets in
                            deleteFacts(in: layer, at: offsets)
                        }
                    }
                }
            }

            Section {
                Button {
                    saveAndFinish()
                } label: {
                    Text("Save Context")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Something went wrong")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Try Again") { Task { await startExtraction() } }
                .buttonStyle(.borderedProminent)
            Button("Cancel") { dismiss() }
            Spacer()
        }
    }

    // MARK: - Logic

    private func startExtraction() async {
        do {
            let facts: [ContextFact]

            if let parseResult = parseResult {
                facts = try await extractionService.processImport(
                    parseResult: parseResult,
                    claudeMemory: claudeMemory
                )
            } else if let text = directText {
                facts = try await extractionService.extractFromSingleInput(text)
            } else {
                errorMessage = "No input provided."
                return
            }

            editableFacts = facts
            reviewMode = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteFacts(in layer: ContextLayer, at offsets: IndexSet) {
        let layerFacts = editableFacts.filter { $0.layer == layer }
        let idsToRemove = offsets.map { layerFacts[$0].id }
        editableFacts.removeAll { idsToRemove.contains($0.id) }
    }

    private func saveAndFinish() {
        let platform = parseResult?.platform ?? .claude
        let stats = ImportRecord(
            platform: platform,
            conversationCount: parseResult?.totalConversations ?? 0,
            messageCount: parseResult?.totalMessages ?? 0,
            importedAt: Date(),
            factsExtracted: editableFacts.count
        )

        do {
            try storageService.mergeAndSave(
                newFacts: editableFacts,
                from: platform,
                stats: stats
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func layerTitle(_ layer: ContextLayer) -> String {
        switch layer {
        case .coreIdentity: return "Identity"
        case .currentContext: return "Current Context"
        case .activeContext: return "Right Now"
        }
    }
}

// MARK: - Fact Row

struct FactRow: View {
    let fact: ContextFact

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(categoryLabel(fact.category))
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(categoryColor(fact.category))
                    .clipShape(Capsule())

                Spacer()

                // Confidence indicator
                Text("\(Int(fact.confidence * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(fact.content)
                .font(.body)
        }
        .padding(.vertical, 4)
    }

    private func categoryLabel(_ cat: ContextCategory) -> String {
        switch cat {
        case .role: return "Role"
        case .skill: return "Skill"
        case .project: return "Project"
        case .preference: return "Preference"
        case .goal: return "Goal"
        case .interest: return "Interest"
        case .background: return "Background"
        }
    }

    private func categoryColor(_ cat: ContextCategory) -> Color {
        switch cat {
        case .role: return .blue
        case .skill: return .purple
        case .project: return .green
        case .preference: return .orange
        case .goal: return .red
        case .interest: return .cyan
        case .background: return .gray
        }
    }
}
