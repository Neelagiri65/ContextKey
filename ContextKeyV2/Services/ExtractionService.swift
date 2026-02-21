import Foundation

// MARK: - Extraction Service

/// Extracts structured context from parsed conversations using the selected SLM provider.
/// Supports Apple Foundation Models (iOS 26+) and open-source on-device LLMs.
@MainActor
final class ExtractionService: ObservableObject {

    @Published var isProcessing = false
    @Published var progress: Double = 0.0       // 0.0 - 1.0
    @Published var statusMessage = ""
    @Published var extractedFacts: [ContextFact] = []

    /// The active SLM engine — user can change this in settings
    @Published var selectedEngine: SLMEngine {
        didSet {
            UserDefaults.standard.set(selectedEngine.rawValue, forKey: "selectedSLMEngine")
            provider = SLMProviderFactory.create(for: selectedEngine)
        }
    }

    private var provider: any SLMProvider
    private let fallbackProvider: any SLMProvider = HeuristicProvider()
    @Published var lastError: String?

    init() {
        // Restore user's SLM preference, default to Apple FM if available
        let savedEngine = UserDefaults.standard.string(forKey: "selectedSLMEngine")
            .flatMap { SLMEngine(rawValue: $0) }

        let engine: SLMEngine
        if let saved = savedEngine, saved.isAvailable {
            engine = saved
        } else if SLMEngine.appleFoundationModels.isAvailable {
            engine = .appleFoundationModels
        } else {
            // Skip onDeviceOpenSource (not implemented) — go straight to heuristic
            engine = .appleFoundationModels // Will use HeuristicProvider as fallback
        }

        self.selectedEngine = engine
        self.provider = SLMProviderFactory.create(for: engine)
    }

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
            do {
                let memoryFacts = try await extractFromMemory(memory, platform: .claude)
                allFacts.append(contentsOf: memoryFacts)
            } catch {
                lastError = "Memory extraction: \(error.localizedDescription)"
                // Try fallback for memory too
                if let fallbackFacts = try? await extractWithFallback(memory, platform: .claude, conversationTitle: "Claude Memory", conversationDate: Date()) {
                    allFacts.append(contentsOf: fallbackFacts)
                }
            }
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
                // Primary provider failed — try fallback heuristic provider
                lastError = "Primary: \(error.localizedDescription)"
                do {
                    let fallbackFacts = try await extractWithFallback(
                        truncated,
                        platform: parseResult.platform,
                        conversationTitle: conversation.title,
                        conversationDate: conversation.createdAt
                    )
                    allFacts.append(contentsOf: fallbackFacts)
                } catch {
                    // Both providers failed — skip this conversation
                    continue
                }
            }

            // Update progress
            let baseProgress = claudeMemory != nil ? 0.2 : 0.0
            progress = baseProgress + (1.0 - baseProgress) * Double(index + 1) / Double(total)
            statusMessage = "Analyzed \(index + 1) of \(total) conversations..."
        }

        // Step 3: Deduplicate and merge
        statusMessage = "Organizing \(allFacts.count) raw facts..."
        let deduped = deduplicateAndMerge(allFacts)

        extractedFacts = deduped
        isProcessing = false
        progress = 1.0
        statusMessage = "Done — found \(deduped.count) context items"

        return deduped
    }

    /// Extract context from a single text input (voice transcript or manual entry)
    func extractFromSingleInput(_ text: String, source: Platform = .manual) async throws -> [ContextFact] {
        isProcessing = true
        statusMessage = "Analyzing your input..."

        var facts: [ContextFact]
        do {
            facts = try await extractFromText(
                String(text.prefix(3000)),
                platform: source,
                conversationTitle: "Direct input",
                conversationDate: Date()
            )
        } catch {
            // Primary failed, try fallback
            lastError = "Primary: \(error.localizedDescription)"
            statusMessage = "Using backup extraction..."
            facts = try await extractWithFallback(
                String(text.prefix(3000)),
                platform: source,
                conversationTitle: "Direct input",
                conversationDate: Date()
            )
        }

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
        about the user organized into these categories:

        - Persona: their role, job title, expertise level, industry, years of experience
        - Skills & Stack: tools, languages, frameworks, platforms they use or know
        - Communication Style: how they prefer AI responses — tone, length, format, interaction style
        - Active Projects: what they're currently building or working on
        - Goals & Priorities: objectives they're trying to achieve, success criteria
        - Constraints: limitations, things they avoid, boundaries they set
        - Work Patterns: how they use AI — coding, writing, research, email, brainstorming, review

        Extract everything clearly stated or strongly implied. Be specific, not generic.

        Conversation: "\(conversationTitle)"
        """

        let extracted = try await provider.extract(from: text, prompt: prompt)

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
        the user into these categories:

        - Persona: role, title, expertise, industry
        - Skills & Stack: tools, languages, frameworks
        - Communication Style: response preferences, tone, format
        - Active Projects: current work
        - Goals & Priorities: objectives, success criteria
        - Constraints: boundaries, limitations
        - Work Patterns: how they use AI

        This is a trusted source, so extract everything mentioned. Be specific.
        """

        let extracted = try await provider.extract(from: memory, prompt: prompt)

        let source = ContextSource(
            platform: platform,
            conversationCount: 1,
            lastConversationDate: Date()
        )

        return convertToFacts(extracted, source: source, highConfidence: true)
    }

    /// Fallback extraction using HeuristicProvider when primary provider fails
    private func extractWithFallback(
        _ text: String,
        platform: Platform,
        conversationTitle: String,
        conversationDate: Date
    ) async throws -> [ContextFact] {
        let prompt = """
        Extract factual information about the user from this text.
        """

        let extracted = try await fallbackProvider.extract(from: text, prompt: prompt)

        let source = ContextSource(
            platform: platform,
            conversationCount: 1,
            lastConversationDate: conversationDate
        )

        return convertToFacts(extracted, source: source)
    }

    // MARK: - Private: Convert & Deduplicate

    private func convertToFacts(
        _ extracted: ExtractedFactsRaw,
        source: ContextSource,
        highConfidence: Bool = false
    ) -> [ContextFact] {
        var facts: [ContextFact] = []
        let confidence = highConfidence ? 0.9 : 0.6

        for item in extracted.persona where !item.isEmpty {
            facts.append(ContextFact(
                content: item,
                layer: .coreIdentity,
                pillar: .persona,
                confidence: confidence,
                sources: [source]
            ))
        }

        for item in extracted.skillsAndStack where !item.isEmpty {
            facts.append(ContextFact(
                content: item,
                layer: .coreIdentity,
                pillar: .skillsAndStack,
                confidence: confidence,
                sources: [source]
            ))
        }

        for item in extracted.communicationStyle where !item.isEmpty {
            facts.append(ContextFact(
                content: item,
                layer: .coreIdentity,
                pillar: .communicationStyle,
                confidence: confidence,
                sources: [source]
            ))
        }

        for item in extracted.activeProjects where !item.isEmpty {
            facts.append(ContextFact(
                content: item,
                layer: .currentContext,
                pillar: .activeProjects,
                confidence: confidence,
                sources: [source]
            ))
        }

        for item in extracted.goalsAndPriorities where !item.isEmpty {
            facts.append(ContextFact(
                content: item,
                layer: .currentContext,
                pillar: .goalsAndPriorities,
                confidence: confidence,
                sources: [source]
            ))
        }

        for item in extracted.constraints where !item.isEmpty {
            facts.append(ContextFact(
                content: item,
                layer: .coreIdentity,
                pillar: .constraints,
                confidence: confidence,
                sources: [source]
            ))
        }

        for item in extracted.workPatterns where !item.isEmpty {
            facts.append(ContextFact(
                content: item,
                layer: .currentContext,
                pillar: .workPatterns,
                confidence: confidence,
                sources: [source]
            ))
        }

        return facts
    }

    /// Deduplicate facts by comparing content similarity (case-insensitive)
    /// Tracks frequency — duplicates increment the count instead of being discarded
    private func deduplicateAndMerge(_ facts: [ContextFact]) -> [ContextFact] {
        var merged: [ContextFact] = []

        for fact in facts {
            let normalized = fact.content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

            if let existingIndex = merged.firstIndex(where: {
                $0.content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalized
            }) {
                // Merge: increase confidence, bump frequency, combine sources
                merged[existingIndex].confidence = min(1.0, merged[existingIndex].confidence + 0.1)
                merged[existingIndex].frequency += fact.frequency
                merged[existingIndex].lastSeenDate = max(merged[existingIndex].lastSeenDate, fact.lastSeenDate)
                merged[existingIndex].sources.append(contentsOf: fact.sources)
            } else {
                merged.append(fact)
            }
        }

        // Sort: frequency first, then layer importance, then confidence
        return merged.sorted { a, b in
            if a.frequency != b.frequency { return a.frequency > b.frequency }
            if a.layer != b.layer {
                let order: [ContextLayer] = [.coreIdentity, .currentContext, .activeContext]
                return (order.firstIndex(of: a.layer) ?? 0) < (order.firstIndex(of: b.layer) ?? 0)
            }
            return a.confidence > b.confidence
        }
    }
}
