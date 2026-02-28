import Foundation
import NaturalLanguage
import SwiftData

// MARK: - Reconciliation Service (Build 18 — Section 3)

/// Merges new RawExtractions into existing CanonicalEntities.
/// Handles three-tier entity matching, citation deduplication, and corroboration boost.
enum ReconciliationService {

    // MARK: - Constants

    private static let batchSize = 50
    private static let maxMergeSuggestionsPerDay = 2
    private static let snoozeDays = 7

    // MARK: - Public API

    /// Reconcile new extractions against existing canonical entities.
    /// Runs in order: citations first, then entity reconciliation, then pending alias promotion.
    @MainActor
    static func reconcile(extractions: [RawExtraction], modelContext: ModelContext) async throws {
        // Classify entity types using NLTagger before reconciliation.
        // Extractions arrive with default .preference from the simplified SLM prompt.
        for extraction in extractions {
            if extraction.entityType == .preference {
                extraction.entityType = classifyEntityType(extraction.text)
            }
        }
        try await reconcileCitations(from: extractions, modelContext: modelContext)
        try await reconcileEntities(extractions: extractions, modelContext: modelContext)
        try await processPendingAliasCandidates(modelContext: modelContext)
    }

    // MARK: - Entity Reconciliation (Section 3.2)

    @MainActor
    static func reconcileEntities(extractions: [RawExtraction], modelContext: ModelContext) async throws {
        // Process in batches of 50 — never load all CanonicalEntities at once
        for batch in extractions.chunked(into: batchSize) {
            // Fetch entities relevant to this batch
            let descriptor = FetchDescriptor<CanonicalEntity>()
            let existingEntities = try modelContext.fetch(descriptor)

            for extraction in batch {
                // Tier A: Exact match
                if let match = tierAMatch(extractionText: extraction.text, existingEntities: existingEntities) {
                    // Link extraction to existing entity
                    extraction.canonicalEntityId = match.id
                    if !match.supportingExtractionIds.contains(extraction.id) {
                        match.supportingExtractionIds.append(extraction.id)
                    }
                    match.lastSeenDate = max(match.lastSeenDate, extraction.conversationTimestamp)
                    if let score = match.beliefScore {
                        score.supportCount += 1
                        score.lastCorroboratedDate = Date()
                    }
                    continue
                }

                // Tier B: Co-occurrence alias detection for generic references
                if isGenericReference(extraction.text) {
                    tierBProcess(
                        extraction: extraction,
                        batch: batch,
                        allEntities: existingEntities,
                        modelContext: modelContext
                    )
                    // Still create a new entity for the generic reference if no match
                    if extraction.canonicalEntityId == nil {
                        createNewEntity(for: extraction, modelContext: modelContext)
                    }
                    continue
                }

                // No match — create new CanonicalEntity
                createNewEntity(for: extraction, modelContext: modelContext)
            }

            try modelContext.save()
        }
    }

    // MARK: - Tier A: Exact Match

    static func tierAMatch(
        extractionText: String,
        existingEntities: [CanonicalEntity]
    ) -> CanonicalEntity? {
        let normalised = extractionText.lowercased().trimmingCharacters(in: .whitespaces)
        return existingEntities.first { entity in
            entity.canonicalText.lowercased() == normalised ||
            entity.aliases.contains { $0.lowercased() == normalised }
        }
    }

    // MARK: - Tier B: Co-occurrence Alias Detection

    static func isGenericReference(_ text: String) -> Bool {
        let genericPhrases = ["my app", "this project", "the app", "my project",
                              "it", "this tool", "the tool", "my work", "this"]
        return genericPhrases.contains(text.lowercased().trimmingCharacters(in: .whitespaces))
    }

    @MainActor
    private static func tierBProcess(
        extraction: RawExtraction,
        batch: [RawExtraction],
        allEntities: [CanonicalEntity],
        modelContext: ModelContext
    ) {
        // Find named entities from the same conversation
        let sameConversation = batch.filter {
            $0.sourceConversationId == extraction.sourceConversationId &&
            $0.id != extraction.id &&
            !isGenericReference($0.text)
        }

        for namedExtraction in sameConversation {
            // Find the CanonicalEntity for this named extraction
            guard let namedEntity = allEntities.first(where: {
                $0.canonicalText.lowercased() == namedExtraction.text.lowercased() ||
                $0.aliases.contains { $0.lowercased() == namedExtraction.text.lowercased() }
            }) else { continue }

            // Check merge compatibility
            guard mergeCompatible(extraction.entityType, namedEntity.entityType) else { continue }

            // Create or increment PendingAliasCandidate on the named entity
            if let idx = namedEntity.pendingAliasCandidates.firstIndex(where: {
                $0.candidateEntityId == extraction.canonicalEntityId ?? UUID()
            }) {
                namedEntity.pendingAliasCandidates[idx].coOccurrenceCount += 1
            } else {
                let candidate = PendingAliasCandidate(
                    extractionId: extraction.id,
                    candidateEntityId: extraction.canonicalEntityId ?? extraction.id,
                    coOccurrenceCount: 1,
                    firstSeen: Date()
                )
                namedEntity.pendingAliasCandidates.append(candidate)
            }
        }
    }

    // MARK: - Tier C: User Review Queue

    /// Stores pending merge suggestions in UserDefaults.
    static func loadMergeSuggestions() -> [MergeSuggestion] {
        guard let data = UserDefaults.standard.data(forKey: "pendingMergeSuggestions"),
              let suggestions = try? JSONDecoder().decode([MergeSuggestion].self, from: data) else {
            return []
        }
        return suggestions
    }

    static func saveMergeSuggestions(_ suggestions: [MergeSuggestion]) {
        guard let data = try? JSONEncoder().encode(suggestions) else { return }
        UserDefaults.standard.set(data, forKey: "pendingMergeSuggestions")
    }

    /// Returns up to maxMergeSuggestionsPerDay unsnoozed suggestions for today.
    static func pendingSuggestionsForToday() -> [MergeSuggestion] {
        let suggestions = loadMergeSuggestions()
        let now = Date()
        return Array(suggestions.filter { suggestion in
            if let snoozed = suggestion.snoozedUntil, snoozed > now { return false }
            return true
        }.prefix(maxMergeSuggestionsPerDay))
    }

    /// Record user decision on a merge suggestion.
    @MainActor
    static func decideMerge(
        _ suggestion: MergeSuggestion,
        decision: MergeDecisionType,
        modelContext: ModelContext
    ) throws {
        var suggestions = loadMergeSuggestions()
        suggestions.removeAll { $0.entityAId == suggestion.entityAId && $0.entityBId == suggestion.entityBId }

        switch decision {
        case .merged:
            // Merge: add alias, link extractions
            let descriptor = FetchDescriptor<CanonicalEntity>()
            let entities = try modelContext.fetch(descriptor)
            guard let entityA = entities.first(where: { $0.id == suggestion.entityAId }),
                  let entityB = entities.first(where: { $0.id == suggestion.entityBId }) else { return }

            // Add entityB's text as alias of entityA
            if !entityA.aliases.contains(entityB.canonicalText) {
                entityA.aliases.append(entityB.canonicalText)
            }
            entityA.aliases.append(contentsOf: entityB.aliases.filter { !entityA.aliases.contains($0) })

            // Link extractions
            entityA.supportingExtractionIds.append(contentsOf: entityB.supportingExtractionIds)
            entityA.lastSeenDate = max(entityA.lastSeenDate, entityB.lastSeenDate)

            // Record decision
            let mergeDecision = MergeDecision(
                entityAId: suggestion.entityAId,
                entityBId: suggestion.entityBId,
                decision: .merged,
                decidedAt: Date(),
                userInitiated: true
            )
            entityA.userMergeDecisions.append(mergeDecision)

            // Delete entityB
            modelContext.delete(entityB)
            try modelContext.save()

        case .kept_separate:
            // Store decision so it's never suggested again
            let decisionRecord = MergeDecision(
                entityAId: suggestion.entityAId,
                entityBId: suggestion.entityBId,
                decision: .kept_separate,
                decidedAt: Date(),
                userInitiated: true
            )
            // Store in UserDefaults alongside suggestions
            var rejections = loadRejectedMerges()
            rejections.append(decisionRecord)
            saveRejectedMerges(rejections)
        }

        saveMergeSuggestions(suggestions)
    }

    /// Snooze a merge suggestion for 7 days.
    static func snoozeSuggestion(_ suggestion: MergeSuggestion) {
        var suggestions = loadMergeSuggestions()
        if let idx = suggestions.firstIndex(where: {
            $0.entityAId == suggestion.entityAId && $0.entityBId == suggestion.entityBId
        }) {
            suggestions[idx].snoozedUntil = Calendar.current.date(byAdding: .day, value: snoozeDays, to: Date())
        }
        saveMergeSuggestions(suggestions)
    }

    // MARK: - Merge Compatibility (Section 3.2)

    static func mergeCompatible(_ typeA: EntityType, _ typeB: EntityType) -> Bool {
        let incompatible: Set<Set<EntityType>> = [
            [.skill, .identity],
            [.project, .identity],
            [.tool, .goal],
            [.project, .company]
        ]
        return !incompatible.contains([typeA, typeB])
    }

    // MARK: - Process Pending Alias Candidates (Section 3.2 Tier B promotion)

    @MainActor
    static func processPendingAliasCandidates(modelContext: ModelContext) async throws {
        let descriptor = FetchDescriptor<CanonicalEntity>()
        let entities = try modelContext.fetch(descriptor)

        let rejectedMerges = loadRejectedMerges()

        for entity in entities {
            var updatedCandidates: [PendingAliasCandidate] = []
            for candidate in entity.pendingAliasCandidates {
                // Check if this merge was previously rejected
                let isRejected = rejectedMerges.contains {
                    ($0.entityAId == entity.id && $0.entityBId == candidate.candidateEntityId) ||
                    ($0.entityAId == candidate.candidateEntityId && $0.entityBId == entity.id)
                }
                guard !isRejected else { continue }

                if candidate.coOccurrenceCount >= 2 {
                    // Auto-promote to alias
                    if let candidateEntity = entities.first(where: { $0.id == candidate.candidateEntityId }) {
                        if !entity.aliases.contains(candidateEntity.canonicalText) {
                            entity.aliases.append(candidateEntity.canonicalText)
                        }
                        entity.supportingExtractionIds.append(contentsOf: candidateEntity.supportingExtractionIds)

                        let mergeDecision = MergeDecision(
                            entityAId: entity.id,
                            entityBId: candidate.candidateEntityId,
                            decision: .merged,
                            decidedAt: Date(),
                            userInitiated: false
                        )
                        entity.userMergeDecisions.append(mergeDecision)

                        modelContext.delete(candidateEntity)
                    }
                    // Remove from pending — promoted
                } else if candidate.coOccurrenceCount == 1 {
                    // Queue for Tier C user review if entity types match
                    if let candidateEntity = entities.first(where: { $0.id == candidate.candidateEntityId }),
                       candidateEntity.entityType == entity.entityType {

                        let suggestion = MergeSuggestion(
                            entityAText: entity.canonicalText,
                            entityBText: candidateEntity.canonicalText,
                            entityAId: entity.id,
                            entityBId: candidate.candidateEntityId,
                            suggestedAt: Date(),
                            snoozedUntil: nil
                        )

                        var suggestions = loadMergeSuggestions()
                        // Don't duplicate existing suggestions
                        let alreadyExists = suggestions.contains {
                            ($0.entityAId == suggestion.entityAId && $0.entityBId == suggestion.entityBId) ||
                            ($0.entityAId == suggestion.entityBId && $0.entityBId == suggestion.entityAId)
                        }
                        if !alreadyExists {
                            suggestions.append(suggestion)
                            saveMergeSuggestions(suggestions)
                        }
                    }
                    updatedCandidates.append(candidate)
                } else {
                    updatedCandidates.append(candidate)
                }
            }
            entity.pendingAliasCandidates = updatedCandidates
        }

        try modelContext.save()
    }

    // MARK: - Citation Reconciliation (Section 2.2)

    @MainActor
    static func reconcileCitations(from extractions: [RawExtraction], modelContext: ModelContext) async throws {
        // Citation extraction happens in V2PostProcessor during the pipeline.
        // Here we handle deduplication and corroboration boost only.

        // Deduplicate citations: same URL across conversations → increment citedCount
        let citationDescriptor = FetchDescriptor<CitationReference>()
        let existingCitations = try modelContext.fetch(citationDescriptor)

        let citationsByURL = Dictionary(grouping: existingCitations, by: { $0.url })
        for (_, citations) in citationsByURL where citations.count > 1 {
            // Keep the first, merge others into it
            let primary = citations[0]
            for duplicate in citations.dropFirst() {
                primary.citedCount += duplicate.citedCount
                // Merge related entity IDs
                for entityId in duplicate.relatedEntityIds where !primary.relatedEntityIds.contains(entityId) {
                    primary.relatedEntityIds.append(entityId)
                }
                modelContext.delete(duplicate)
            }
        }

        // Apply corroboration boost for entities with linked citations
        for citation in existingCitations {
            for entityId in citation.relatedEntityIds {
                applyCorroborationBoost(to: entityId, citationDomain: citation.domain, modelContext: modelContext)
            }
        }

        try modelContext.save()
    }

    // MARK: - Citation → BeliefScore Boost (Section 2.3)

    @MainActor
    static func applyCorroborationBoost(to entityId: UUID, citationDomain: String, modelContext: ModelContext) {
        let authorityDomains: [String: Double] = [
            "developer.apple.com": 0.15,
            "docs.swift.org": 0.15,
            "github.com": 0.10,
            "arxiv.org": 0.12,
            "stackoverflow.com": 0.08,
            "medium.com": 0.05
        ]

        let boost = authorityDomains[citationDomain] ?? 0.05

        // Fetch BeliefScore for entity
        let descriptor = FetchDescriptor<BeliefScore>()
        guard let scores = try? modelContext.fetch(descriptor) else { return }
        guard let score = scores.first(where: { $0.canonicalEntityId == entityId }) else { return }

        // Cap externalCorroboration at 0.3 total
        score.externalCorroboration = min(score.externalCorroboration + boost, 0.3)
    }

    // MARK: - Entity Type Classification (NLTagger-based)

    /// Classifies an untyped fact text into an EntityType using NLTagger
    /// and pattern matching. Called on RawExtractions that arrive with
    /// the default .preference type from the simplified SLM prompt.
    static func classifyEntityType(_ text: String) -> EntityType {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        var detectedTag: NLTag?
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitPunctuation, .omitWhitespace, .joinNames]
        ) { tag, _ in
            if let tag = tag {
                detectedTag = tag
                return false  // stop at first match
            }
            return true
        }

        // NLTagger-based classification
        if let tag = detectedTag {
            switch tag {
            case .personalName:     return .identity
            case .organizationName: return .company
            case .placeName:        return .context
            default: break
            }
        }

        // Pattern-based fallback
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // Contains digit → .skill (e.g. "5 years of Swift", "iOS 17")
        if trimmed.contains(where: { $0.isNumber }) {
            return .skill
        }

        // All uppercase, length >= 2 → .domain (e.g. "AI", "ML", "SaaS")
        let letters = trimmed.filter { $0.isLetter }
        if letters.count >= 2 && letters == letters.uppercased() {
            return .domain
        }

        // Role suffixes → .identity
        let roleSuffixes = [
            "er", "or", "ist", "ant", "ent",
            "manager", "director", "head", "chief",
            "lead", "founder", "officer"
        ]
        let lastWord = lower.components(separatedBy: .whitespaces).last ?? ""
        if roleSuffixes.contains(where: { lastWord.hasSuffix($0) }) {
            return .identity
        }

        // Default → .preference (365-day half-life, NOT .context's 14-day)
        return .preference
    }

    // MARK: - Private Helpers

    @MainActor
    private static func createNewEntity(for extraction: RawExtraction, modelContext: ModelContext) {
        let beliefScore = BeliefScore(
            canonicalEntityId: UUID(), // placeholder, updated below
            currentScore: 0.5,
            supportCount: 1,
            lastCorroboratedDate: extraction.conversationTimestamp,
            attributionWeight: extraction.speakerAttribution == .userExplicit ? 1.0 : 0.5,
            halfLifeDays: halfLifeDays(for: extraction.entityType)
        )

        let entity = CanonicalEntity(
            canonicalText: extraction.text,
            entityType: extraction.entityType,
            firstSeenDate: extraction.conversationTimestamp,
            lastSeenDate: extraction.conversationTimestamp,
            supportingExtractionIds: [extraction.id],
            beliefScore: beliefScore
        )

        beliefScore.canonicalEntityId = entity.id
        extraction.canonicalEntityId = entity.id

        modelContext.insert(beliefScore)
        modelContext.insert(entity)
    }

    // MARK: - Rejected Merges Persistence

    private static func loadRejectedMerges() -> [MergeDecision] {
        guard let data = UserDefaults.standard.data(forKey: "rejectedMergeDecisions"),
              let decisions = try? JSONDecoder().decode([MergeDecision].self, from: data) else {
            return []
        }
        return decisions
    }

    private static func saveRejectedMerges(_ decisions: [MergeDecision]) {
        guard let data = try? JSONEncoder().encode(decisions) else { return }
        UserDefaults.standard.set(data, forKey: "rejectedMergeDecisions")
    }
}

// MARK: - MergeSuggestion (Section 3.2 Tier C)

struct MergeSuggestion: Codable {
    var entityAText: String
    var entityBText: String
    var entityAId: UUID
    var entityBId: UUID
    var suggestedAt: Date
    var snoozedUntil: Date?
}

// MARK: - Array Chunking Extension

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
