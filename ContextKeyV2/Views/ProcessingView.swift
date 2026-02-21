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
                } else if reviewMode && !editableFacts.isEmpty {
                    reviewView
                } else if reviewMode && editableFacts.isEmpty {
                    emptyResultView
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

            VStack(spacing: 16) {
                ProgressView(value: extractionService.progress) {
                    Text(extractionService.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .progressViewStyle(.linear)

                // SLM engine indicator
                Text("Using \(extractionService.selectedEngine.displayName)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
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

    // MARK: - Review View (Grouped by Pillar)

    private var reviewView: some View {
        List {
            ForEach(ContextPillar.allCases, id: \.self) { pillar in
                let pillarFacts = editableFacts.filter { $0.pillar == pillar }
                if !pillarFacts.isEmpty {
                    Section(header: pillarHeader(pillar, count: pillarFacts.count)) {
                        ForEach(pillarFacts) { fact in
                            FactRow(fact: fact)
                        }
                        .onDelete { offsets in
                            deleteFacts(in: pillar, at: offsets)
                        }
                    }
                }
            }

            // Summary
            Section {
                HStack {
                    Text("\(editableFacts.count) facts extracted")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    let pillarsWithFacts = Set(editableFacts.map { $0.pillar }).count
                    Text("\(pillarsWithFacts)/7 pillars")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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

    private func pillarHeader(_ pillar: ContextPillar, count: Int) -> some View {
        HStack {
            Image(systemName: pillar.iconName)
                .font(.caption)
                .foregroundStyle(pillarColor(pillar))
            Text(pillar.displayName)
                .foregroundStyle(pillarColor(pillar))
            Spacer()
            Text("\(count)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty Result View

    private var emptyResultView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No context found")
                .font(.headline)
            Text("We couldn't extract context from this input. Try providing more detail about yourself — your role, tools you use, or what you're working on.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let lastErr = extractionService.lastError {
                Text("Debug: \(lastErr)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 32)
            }

            Button("Try Again") {
                reviewMode = false
                Task { await startExtraction() }
            }
            .buttonStyle(.borderedProminent)

            Button("Go Back") { dismiss() }
                .foregroundStyle(.secondary)

            Spacer()
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

            Text("Engine: \(extractionService.selectedEngine.displayName)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

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

    private func deleteFacts(in pillar: ContextPillar, at offsets: IndexSet) {
        let pillarFacts = editableFacts.filter { $0.pillar == pillar }
        let idsToRemove = offsets.map { pillarFacts[$0].id }
        editableFacts.removeAll { idsToRemove.contains($0.id) }
    }

    private func saveAndFinish() {
        let platform = parseResult?.platform ?? .manual
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

// MARK: - Fact Row (Updated for 7-Pillar Framework)

struct FactRow: View {
    let fact: ContextFact

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(fact.content)
                .font(.body)

            HStack(spacing: 8) {
                // Frequency badge
                if fact.frequency > 1 {
                    Text("\(fact.frequency)x")
                        .font(.caption2.bold())
                        .foregroundStyle(factPillarColor)
                }

                // Confidence
                Text("\(Int(fact.confidence * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                // Layer tag
                Text(layerLabel(fact.layer))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var factPillarColor: Color {
        switch fact.pillar.color {
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

    private func layerLabel(_ layer: ContextLayer) -> String {
        switch layer {
        case .coreIdentity: return "Core"
        case .currentContext: return "Current"
        case .activeContext: return "Active"
        }
    }
}
