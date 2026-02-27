import Foundation
import SwiftData

// MARK: - Extraction Service

/// Extracts structured context from parsed conversations using the selected SLM provider.
/// Supports Apple Foundation Models (iOS 26+) and open-source on-device LLMs.
@MainActor
final class ExtractionService: ObservableObject {

    @Published var isProcessing = false
    @Published var progress: Double = 0.0       // 0.0 - 1.0
    @Published var statusMessage = ""
    @Published var extractedFacts: [ContextFact] = []
    @Published var processedConversations = 0
    @Published var totalConversationsToProcess = 0
    @Published var rawFactsFound = 0

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

    /// SwiftData model context for V2 pipeline. Set externally when SwiftData is configured.
    var modelContext: ModelContext?

    /// The actual provider name (may differ from selectedEngine if fallback was used)
    var activeProviderName: String { provider.displayName }

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
        defer { isProcessing = false }
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

        // Step 2: Process conversations in batches (limit to 50 most recent)
        let conversations = parseResult.conversations
            .sorted { ($0.createdAt) > ($1.createdAt) }
        let batch = Array(conversations.prefix(50))
        let total = batch.count
        totalConversationsToProcess = total
        processedConversations = 0
        rawFactsFound = 0
        statusMessage = "Analyzing \(total) conversations\(conversations.count > 50 ? " (most recent 50 of \(conversations.count))" : "")..."

        for (index, conversation) in batch.enumerated() {
            try Task.checkCancellation()
            // Only process conversations with at least 1 user message
            let userMessages = conversation.messages.filter { $0.role == .user }
            guard userMessages.count >= 1 else { continue }

            // Combine user messages into a single text block for extraction
            let combinedText = userMessages
                .map { $0.text }
                .joined(separator: "\n---\n")

            // Truncate to avoid exceeding SLM context window (6000 chars for Apple FM)
            let truncated = String(combinedText.prefix(6000))

            do {
                let facts = try await extractFromText(
                    truncated,
                    platform: parseResult.platform,
                    conversationTitle: conversation.title,
                    conversationDate: conversation.createdAt
                )
                if !facts.isEmpty {
                    allFacts.append(contentsOf: facts)
                } else {
                    // Primary returned 0 facts — try fallback (separate catch to avoid double-retry)
                    let fallbackFacts = try? await extractWithFallback(
                        truncated,
                        platform: parseResult.platform,
                        conversationTitle: conversation.title,
                        conversationDate: conversation.createdAt
                    )
                    if let fb = fallbackFacts {
                        allFacts.append(contentsOf: fb)
                    }
                }
            } catch {
                // Primary provider threw — try fallback heuristic provider
                lastError = "Primary: \(error.localizedDescription)"
                let fallbackFacts = try? await extractWithFallback(
                    truncated,
                    platform: parseResult.platform,
                    conversationTitle: conversation.title,
                    conversationDate: conversation.createdAt
                )
                if let fb = fallbackFacts {
                    allFacts.append(contentsOf: fb)
                }
            }

            // Update progress and stats
            processedConversations = index + 1
            rawFactsFound = allFacts.count
            let baseProgress = claudeMemory != nil ? 0.2 : 0.0
            progress = baseProgress + (1.0 - baseProgress) * Double(index + 1) / Double(total)
            statusMessage = "Analyzed \(index + 1)/\(total) — \(allFacts.count) facts found"
        }

        // Step 3: Deduplicate and merge
        statusMessage = "Organizing \(allFacts.count) raw facts..."
        let deduped = deduplicateAndMerge(allFacts)

        extractedFacts = deduped
        progress = 1.0
        statusMessage = "Done — found \(deduped.count) context items"

        return deduped
    }

    /// Extract context from a single text input (voice transcript or manual entry)
    func extractFromSingleInput(_ text: String, source: Platform = .manual) async throws -> [ContextFact] {
        isProcessing = true
        defer { isProcessing = false }
        statusMessage = "Analyzing your input..."

        var facts: [ContextFact]
        let truncated = String(text.prefix(6000))
        try Task.checkCancellation()
        do {
            facts = try await extractFromText(
                truncated,
                platform: source,
                conversationTitle: "Direct input",
                conversationDate: Date()
            )
            // If primary returned 0 facts, try fallback — empty success is still a failure
            if facts.isEmpty {
                statusMessage = "Primary returned nothing, trying backup..."
                facts = try await extractWithFallback(
                    truncated,
                    platform: source,
                    conversationTitle: "Direct input",
                    conversationDate: Date()
                )
            }
        } catch {
            // Primary failed, try fallback
            lastError = "Primary (\(selectedEngine.displayName)): \(error.localizedDescription)"
            statusMessage = "Using backup extraction..."
            facts = try await extractWithFallback(
                truncated,
                platform: source,
                conversationTitle: "Direct input",
                conversationDate: Date()
            )
        }

        let deduped = deduplicateAndMerge(facts)
        extractedFacts = deduped
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
        // V2 pipeline gate — when enabled, runs the full V2 extraction path
        if FeatureFlags.v2EnhancedExtraction {
            return try await extractV2(
                from: text,
                platform: platform,
                conversationTitle: conversationTitle,
                conversationDate: conversationDate
            )
        }

        // --- Existing v1 extraction path (unchanged below) ---
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

    // MARK: - V2 Pipeline

    /// Full V2 extraction: PreProcessor → SLMCaller → PostProcessor → SwiftData save.
    /// Returns [ContextFact] for backward compatibility with existing UI.
    private func extractV2(
        from text: String,
        platform: Platform,
        conversationTitle: String,
        conversationDate: Date
    ) async throws -> [ContextFact] {
        // Step 1: Pre-process
        let preProcessed = ConversationPreProcessor.process(text)
        let conversationTimestamp = preProcessed.estimatedDate ?? conversationDate
        let sourceConversationId = UUID()

        // Step 2: Run SLM on each chunk (or NLTagger fallback)
        var chunkResults: [(chunkId: String, chunkText: String, candidates: [RawExtractionCandidate])] = []

        for (index, chunk) in preProcessed.chunks.enumerated() {
            let chunkId = "chunk_\(index)"
            var candidates: [RawExtractionCandidate] = []

            // Try V2SLMCaller first
            if let caller = createV2SLMCaller() {
                do {
                    candidates = try await caller.call(
                        chunk: chunk,
                        primingTopics: preProcessed.primingTopics
                    )
                } catch let error as SLMError where error == .timeout {
                    // Timeout — skip chunk, continue
                    print("[V2] Chunk \(index) timed out, skipping")
                    continue
                } catch {
                    // Model unavailable or other error — fall back to NLTagger
                    candidates = nlTaggerFallback(
                        chunk: chunk,
                        primingTopics: preProcessed.primingTopics
                    )
                }
            } else {
                // No SLM available — NLTagger fallback
                candidates = nlTaggerFallback(
                    chunk: chunk,
                    primingTopics: preProcessed.primingTopics
                )
            }

            chunkResults.append((chunkId: chunkId, chunkText: chunk, candidates: candidates))
        }

        // Step 3: Post-process
        let rawExtractions = V2PostProcessor.process(
            chunks: chunkResults,
            sourceConversationId: sourceConversationId,
            conversationTimestamp: conversationTimestamp
        )

        // Step 4: Save to SwiftData
        if let context = modelContext {
            for extraction in rawExtractions {
                context.insert(extraction)
            }
            try? context.save()
        }

        // Step 5: Reconciliation
        if let context = modelContext {
            try? await ReconciliationService.reconcile(extractions: rawExtractions, modelContext: context)

            // Step 6: Recalculate belief scores for affected entities
            let affectedEntityIds = Set(rawExtractions.compactMap { $0.canonicalEntityId })
            if !affectedEntityIds.isEmpty {
                let descriptor = FetchDescriptor<CanonicalEntity>()
                if let allEntities = try? context.fetch(descriptor) {
                    let affected = allEntities.filter { affectedEntityIds.contains($0.id) }
                    BeliefEngine.recalculateAffected(entities: affected)
                }
            }
        }

        // Convert to ContextFact for backward compatibility with existing UI
        let source = ContextSource(
            platform: platform,
            conversationCount: 1,
            lastConversationDate: conversationDate
        )
        return rawExtractions.filter { $0.isActive }.map { extraction in
            ContextFact(
                content: extraction.text,
                layer: v2EntityTypeToLayer(extraction.entityType),
                pillar: v2EntityTypeToPillar(extraction.entityType),
                confidence: extraction.rawConfidence,
                sources: [source]
            )
        }
    }

    /// Create a V2SLMCaller with the appropriate session for the current device.
    private func createV2SLMCaller() -> V2SLMCaller? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return V2SLMCaller(session: AppleLanguageModelSession())
        }
        #endif
        return nil
    }

    /// NLTagger fallback (Section 2.5 basic): converts priming topics to candidates.
    /// Used when the SLM is unavailable.
    private func nlTaggerFallback(
        chunk: String,
        primingTopics: [String]
    ) -> [RawExtractionCandidate] {
        // Use priming topics as basic entity candidates
        var candidates = primingTopics.map { topic in
            RawExtractionCandidate(
                text: topic,
                entityType: .context,
                speakerAttribution: .ambiguous,
                confidence: 0.3
            )
        }

        // Also run NLTagger on this specific chunk for additional entities
        let chunkTopics = ConversationPreProcessor.extractPrimingTopics(chunk)
        for topic in chunkTopics where !primingTopics.contains(topic) {
            candidates.append(RawExtractionCandidate(
                text: topic,
                entityType: .context,
                speakerAttribution: .ambiguous,
                confidence: 0.2
            ))
        }

        return candidates
    }

    /// Map V2 EntityType to v1 ContextLayer for backward compatibility.
    private func v2EntityTypeToLayer(_ entityType: EntityType) -> ContextLayer {
        switch entityType {
        case .identity, .skill, .tool, .domain, .preference, .company:
            return .coreIdentity
        case .project, .goal:
            return .currentContext
        case .context:
            return .activeContext
        }
    }

    /// Map V2 EntityType to v1 ContextPillar for backward compatibility.
    private func v2EntityTypeToPillar(_ entityType: EntityType) -> ContextPillar {
        switch entityType {
        case .identity:   return .persona
        case .skill:      return .skillsAndStack
        case .tool:       return .skillsAndStack
        case .project:    return .activeProjects
        case .goal:       return .goalsAndPriorities
        case .preference: return .communicationStyle
        case .context:    return .workPatterns
        case .domain:     return .persona
        case .company:    return .persona
        }
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
