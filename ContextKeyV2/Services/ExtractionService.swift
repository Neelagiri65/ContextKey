import Foundation
import FoundationModels

// MARK: - Extraction Service

/// Extracts structured context from parsed conversations using Apple Foundation Models SLM
@MainActor
final class ExtractionService: ObservableObject {

    @Published var isProcessing = false
    @Published var progress: Double = 0.0       // 0.0 - 1.0
    @Published var statusMessage = ""
    @Published var extractedFacts: [ContextFact] = []

    private let session = LanguageModelSession()

    // MARK: - Public API

    /// Process a full import: memories (if Claude) + conversations
    func processImport(
        parseResult: ParseResult,
        claudeMemory: String? = nil
    ) async throws -> [ContextFact] {
        isProcessing = true
        progress = 0.0
        extractedFacts = []

        var allFacts: [ContextFact] = []

        // Step 1: If Claude memory is available, use it directly (it's pre-extracted context)
        if let memory = claudeMemory {
            statusMessage = "Processing Claude memory..."
            let memoryFacts = try await extractFromMemory(memory, platform: .claude)
            allFacts.append(contentsOf: memoryFacts)
            progress = 0.2
        }

        // Step 2: Process conversations in batches
        let conversations = parseResult.conversations
        let total = conversations.count
        statusMessage = "Analyzing \(total) conversations..."

        for (index, conversation) in conversations.enumerated() {
            // Only process conversations with enough content to be meaningful
            let userMessages = conversation.messages.filter { $0.role == .user }
            guard userMessages.count >= 2 else { continue }

            // Combine user messages into a single text block for extraction
            let combinedText = userMessages
                .map { $0.text }
                .joined(separator: "\n---\n")

            // Truncate to avoid exceeding SLM context window
            let truncated = String(combinedText.prefix(3000))

            do {
                let facts = try await extractFromText(
                    truncated,
                    platform: parseResult.platform,
                    conversationTitle: conversation.title,
                    conversationDate: conversation.createdAt
                )
                allFacts.append(contentsOf: facts)
            } catch {
                // Skip failed extractions — don't crash on one bad conversation
                continue
            }

            // Update progress
            let baseProgress = claudeMemory != nil ? 0.2 : 0.0
            progress = baseProgress + (1.0 - baseProgress) * Double(index + 1) / Double(total)
            statusMessage = "Analyzed \(index + 1) of \(total) conversations..."
        }

        // Step 3: Deduplicate and merge
        statusMessage = "Organizing your context..."
        let deduped = deduplicateAndMerge(allFacts)

        extractedFacts = deduped
        isProcessing = false
        progress = 1.0
        statusMessage = "Done — found \(deduped.count) context items"

        return deduped
    }

    /// Extract context from a single text input (voice transcript or manual entry)
    func extractFromSingleInput(_ text: String, source: Platform = .claude) async throws -> [ContextFact] {
        isProcessing = true
        statusMessage = "Analyzing your input..."

        let facts = try await extractFromText(
            String(text.prefix(3000)),
            platform: source,
            conversationTitle: "Direct input",
            conversationDate: Date()
        )

        let deduped = deduplicateAndMerge(facts)
        extractedFacts = deduped
        isProcessing = false
        statusMessage = "Found \(deduped.count) context items"

        return deduped
    }

    // MARK: - Private: SLM Extraction

    private func extractFromText(
        _ text: String,
        platform: Platform,
        conversationTitle: String,
        conversationDate: Date
    ) async throws -> [ContextFact] {
        let prompt = """
        Analyze the following conversation messages from a user. Extract factual information \
        about the user — their role, skills, projects, preferences, goals, background, and interests. \
        Only extract facts that are clearly stated or strongly implied. Do not invent or assume.

        Conversation: "\(conversationTitle)"
        Messages:
        \(text)
        """

        let extracted: ExtractedFacts = try await session.respond(
            to: prompt,
            generating: ExtractedFacts.self
        )

        let source = ContextSource(
            platform: platform,
            conversationCount: 1,
            lastConversationDate: conversationDate
        )

        return convertToFacts(extracted, source: source)
    }

    private func extractFromMemory(_ memory: String, platform: Platform) async throws -> [ContextFact] {
        let prompt = """
        Analyze the following AI memory summary about a user. Extract structured facts about \
        the user — their role, skills, projects, preferences, goals, background, and interests. \
        This is a trusted source, so extract everything mentioned.

        Memory:
        \(memory)
        """

        let extracted: ExtractedFacts = try await session.respond(
            to: prompt,
            generating: ExtractedFacts.self
        )

        let source = ContextSource(
            platform: platform,
            conversationCount: 1,
            lastConversationDate: Date()
        )

        return convertToFacts(extracted, source: source, highConfidence: true)
    }

    // MARK: - Private: Convert & Deduplicate

    private func convertToFacts(
        _ extracted: ExtractedFacts,
        source: ContextSource,
        highConfidence: Bool = false
    ) -> [ContextFact] {
        var facts: [ContextFact] = []
        let confidence = highConfidence ? 0.9 : 0.6

        if let role = extracted.role, !role.isEmpty {
            facts.append(ContextFact(
                content: role,
                layer: .coreIdentity,
                category: .role,
                confidence: confidence,
                sources: [source]
            ))
        }

        for skill in extracted.skills where !skill.isEmpty {
            facts.append(ContextFact(
                content: skill,
                layer: .coreIdentity,
                category: .skill,
                confidence: confidence,
                sources: [source]
            ))
        }

        for project in extracted.projects where !project.isEmpty {
            facts.append(ContextFact(
                content: project,
                layer: .currentContext,
                category: .project,
                confidence: confidence,
                sources: [source]
            ))
        }

        for pref in extracted.preferences where !pref.isEmpty {
            facts.append(ContextFact(
                content: pref,
                layer: .coreIdentity,
                category: .preference,
                confidence: confidence,
                sources: [source]
            ))
        }

        for goal in extracted.goals where !goal.isEmpty {
            facts.append(ContextFact(
                content: goal,
                layer: .currentContext,
                category: .goal,
                confidence: confidence,
                sources: [source]
            ))
        }

        for bg in extracted.background where !bg.isEmpty {
            facts.append(ContextFact(
                content: bg,
                layer: .coreIdentity,
                category: .background,
                confidence: confidence,
                sources: [source]
            ))
        }

        for interest in extracted.interests where !interest.isEmpty {
            facts.append(ContextFact(
                content: interest,
                layer: .activeContext,
                category: .interest,
                confidence: confidence,
                sources: [source]
            ))
        }

        return facts
    }

    /// Deduplicate facts by comparing content similarity (case-insensitive)
    private func deduplicateAndMerge(_ facts: [ContextFact]) -> [ContextFact] {
        var merged: [ContextFact] = []

        for fact in facts {
            let normalized = fact.content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

            if let existingIndex = merged.firstIndex(where: {
                $0.content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalized
            }) {
                // Merge: increase confidence and combine sources
                var existing = merged[existingIndex]
                existing.confidence = min(1.0, existing.confidence + 0.1)
                let newSources = existing.sources + fact.sources
                merged[existingIndex] = ContextFact(
                    content: existing.content,
                    layer: existing.layer,
                    category: existing.category,
                    confidence: existing.confidence,
                    sources: newSources,
                    lastSeenDate: max(existing.lastSeenDate, fact.lastSeenDate)
                )
            } else {
                merged.append(fact)
            }
        }

        // Sort: highest confidence first, then by layer importance
        return merged.sorted { a, b in
            if a.layer != b.layer {
                let order: [ContextLayer] = [.coreIdentity, .currentContext, .activeContext]
                return (order.firstIndex(of: a.layer) ?? 0) < (order.firstIndex(of: b.layer) ?? 0)
            }
            return a.confidence > b.confidence
        }
    }
}
