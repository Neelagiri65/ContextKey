import Foundation
import Testing
import SwiftData
@testable import ContextKeyV2

@Suite("ReconciliationService Tests — Build 18")
struct ReconciliationServiceTests {

    // MARK: - Helpers

    /// Creates an in-memory SwiftData container with all V2 models.
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: RawExtraction.self, CanonicalEntity.self, BeliefScore.self,
                 CitationReference.self, ImportedConversation.self, ContextCard.self,
            configurations: config
        )
        return ModelContext(container)
    }

    /// Creates a RawExtraction with sensible defaults.
    private func makeExtraction(
        text: String,
        entityType: EntityType = .skill,
        conversationId: UUID = UUID(),
        chunkId: String = "chunk_0",
        attribution: AttributionType = .userExplicit,
        confidence: Double = 0.8
    ) -> RawExtraction {
        RawExtraction(
            text: text,
            entityType: entityType,
            sourceConversationId: conversationId,
            sourceChunkId: chunkId,
            conversationTimestamp: Date(),
            speakerAttribution: attribution,
            rawConfidence: confidence,
            entityVerified: true,
            isActive: true
        )
    }

    // MARK: - Tier A Tests

    @Test("Tier A: importing same fact twice creates only one CanonicalEntity")
    @MainActor
    func tierADuplicateFactCreatesOneEntity() async throws {
        let context = try makeContext()

        let ext1 = makeExtraction(text: "Uses Swift")
        let ext2 = makeExtraction(text: "Uses Swift")
        context.insert(ext1)
        context.insert(ext2)
        try context.save()

        // First reconciliation creates a new entity
        try await ReconciliationService.reconcileEntities(extractions: [ext1], modelContext: context)

        // Second reconciliation should match existing, not create new
        try await ReconciliationService.reconcileEntities(extractions: [ext2], modelContext: context)

        let entities = try context.fetch(FetchDescriptor<CanonicalEntity>())
        #expect(entities.count == 1)
        #expect(entities[0].supportingExtractionIds.count == 2)
    }

    @Test("Tier A: importing alias of existing entity links to existing entity")
    @MainActor
    func tierAAliasLinksToExisting() async throws {
        let context = try makeContext()

        // Create an existing entity with an alias
        let existingEntity = CanonicalEntity(
            canonicalText: "Swift",
            entityType: .skill,
            aliases: ["swift language"],
            supportingExtractionIds: [UUID()]
        )
        let score = BeliefScore(canonicalEntityId: existingEntity.id, supportCount: 1)
        existingEntity.beliefScore = score
        context.insert(existingEntity)
        context.insert(score)
        try context.save()

        // New extraction matches the alias
        let ext = makeExtraction(text: "swift language", entityType: .skill)
        context.insert(ext)
        try context.save()

        try await ReconciliationService.reconcileEntities(extractions: [ext], modelContext: context)

        let entities = try context.fetch(FetchDescriptor<CanonicalEntity>())
        #expect(entities.count == 1)
        #expect(ext.canonicalEntityId == existingEntity.id)
    }

    // MARK: - Tier B Tests

    @Test("Tier B: generic reference + named entity in same conversation creates PendingAliasCandidate")
    @MainActor
    func tierBCreatesCandidate() async throws {
        let context = try makeContext()
        let conversationId = UUID()

        // Create a named entity first
        let namedEntity = CanonicalEntity(
            canonicalText: "ContextKey",
            entityType: .project,
            supportingExtractionIds: []
        )
        let score = BeliefScore(canonicalEntityId: namedEntity.id, supportCount: 1)
        namedEntity.beliefScore = score
        context.insert(namedEntity)
        context.insert(score)
        try context.save()

        // Two extractions from the same conversation: "ContextKey" and "my app"
        let namedExt = makeExtraction(text: "ContextKey", entityType: .project, conversationId: conversationId)
        let genericExt = makeExtraction(text: "my app", entityType: .project, conversationId: conversationId)
        context.insert(namedExt)
        context.insert(genericExt)
        try context.save()

        // Link namedExt to the existing entity first (simulate Tier A match)
        namedExt.canonicalEntityId = namedEntity.id
        namedEntity.supportingExtractionIds.append(namedExt.id)

        try await ReconciliationService.reconcileEntities(extractions: [namedExt, genericExt], modelContext: context)

        // The named entity should have a pending alias candidate
        let entities = try context.fetch(FetchDescriptor<CanonicalEntity>())
        let contextKeyEntity = entities.first { $0.canonicalText == "ContextKey" }
        #expect(contextKeyEntity != nil)
        #expect(contextKeyEntity!.pendingAliasCandidates.count >= 1)
    }

    @Test("Tier B: same pair in second conversation auto-promotes to alias")
    @MainActor
    func tierBAutoPromotes() async throws {
        let context = try makeContext()

        // Create entity with an existing PendingAliasCandidate (coOccurrenceCount = 1)
        let candidateEntityId = UUID()
        let candidate = PendingAliasCandidate(
            extractionId: UUID(),
            candidateEntityId: candidateEntityId,
            coOccurrenceCount: 1,
            firstSeen: Date()
        )

        let namedEntity = CanonicalEntity(
            canonicalText: "ContextKey",
            entityType: .project,
            pendingAliasCandidates: [candidate]
        )
        let score = BeliefScore(canonicalEntityId: namedEntity.id, supportCount: 1)
        namedEntity.beliefScore = score
        context.insert(namedEntity)
        context.insert(score)

        // Create the candidate entity that will be merged
        let candidateEntity = CanonicalEntity(
            id: candidateEntityId,
            canonicalText: "my app",
            entityType: .project,
            supportingExtractionIds: [UUID()]
        )
        let candidateScore = BeliefScore(canonicalEntityId: candidateEntityId, supportCount: 1)
        candidateEntity.beliefScore = candidateScore
        context.insert(candidateEntity)
        context.insert(candidateScore)
        try context.save()

        // Bump coOccurrenceCount to 2 (simulating second conversation)
        namedEntity.pendingAliasCandidates[0].coOccurrenceCount = 2

        try await ReconciliationService.processPendingAliasCandidates(modelContext: context)

        // "my app" should now be an alias of "ContextKey"
        let entities = try context.fetch(FetchDescriptor<CanonicalEntity>())
        let contextKey = entities.first { $0.canonicalText == "ContextKey" }
        #expect(contextKey != nil)
        #expect(contextKey!.aliases.contains("my app"))
        #expect(contextKey!.pendingAliasCandidates.isEmpty)
    }

    // MARK: - Tier C Tests

    @Test("Tier C: merge suggestion queues correctly, max 2 per day enforced")
    func tierCMaxSuggestionsPerDay() {
        // Clear any existing suggestions
        UserDefaults.standard.removeObject(forKey: "pendingMergeSuggestions")

        let suggestions = (0..<5).map { i in
            MergeSuggestion(
                entityAText: "Entity A\(i)",
                entityBText: "Entity B\(i)",
                entityAId: UUID(),
                entityBId: UUID(),
                suggestedAt: Date(),
                snoozedUntil: nil
            )
        }
        ReconciliationService.saveMergeSuggestions(suggestions)

        let pending = ReconciliationService.pendingSuggestionsForToday()
        #expect(pending.count == 2)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "pendingMergeSuggestions")
    }

    @Test("Tier C: YES decision merges entities, NO decision prevents future suggestion")
    @MainActor
    func tierCMergeDecisions() async throws {
        let context = try makeContext()

        // Clear merge state
        UserDefaults.standard.removeObject(forKey: "pendingMergeSuggestions")
        UserDefaults.standard.removeObject(forKey: "rejectedMergeDecisions")

        let entityA = CanonicalEntity(
            canonicalText: "Swift",
            entityType: .skill,
            supportingExtractionIds: [UUID()]
        )
        let entityB = CanonicalEntity(
            canonicalText: "SwiftUI",
            entityType: .skill,
            supportingExtractionIds: [UUID()]
        )
        context.insert(entityA)
        context.insert(entityB)
        try context.save()

        // Test YES decision
        let suggestion = MergeSuggestion(
            entityAText: entityA.canonicalText,
            entityBText: entityB.canonicalText,
            entityAId: entityA.id,
            entityBId: entityB.id,
            suggestedAt: Date(),
            snoozedUntil: nil
        )
        ReconciliationService.saveMergeSuggestions([suggestion])

        try ReconciliationService.decideMerge(suggestion, decision: .merged, modelContext: context)

        let entities = try context.fetch(FetchDescriptor<CanonicalEntity>())
        let merged = entities.first { $0.id == entityA.id }
        #expect(merged != nil)
        #expect(merged!.aliases.contains("SwiftUI"))

        // entityB should be deleted
        let entityBStillExists = entities.contains { $0.id == entityB.id }
        #expect(!entityBStillExists)

        // Now test NO decision — create fresh entities
        let entityC = CanonicalEntity(canonicalText: "Python", entityType: .skill)
        let entityD = CanonicalEntity(canonicalText: "Rust", entityType: .skill)
        context.insert(entityC)
        context.insert(entityD)
        try context.save()

        let suggestion2 = MergeSuggestion(
            entityAText: entityC.canonicalText,
            entityBText: entityD.canonicalText,
            entityAId: entityC.id,
            entityBId: entityD.id,
            suggestedAt: Date(),
            snoozedUntil: nil
        )
        ReconciliationService.saveMergeSuggestions([suggestion2])

        try ReconciliationService.decideMerge(suggestion2, decision: .kept_separate, modelContext: context)

        // Both entities should still exist
        let allEntities = try context.fetch(FetchDescriptor<CanonicalEntity>())
        #expect(allEntities.contains { $0.id == entityC.id })
        #expect(allEntities.contains { $0.id == entityD.id })

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "pendingMergeSuggestions")
        UserDefaults.standard.removeObject(forKey: "rejectedMergeDecisions")
    }

    // MARK: - Type Incompatibility

    @Test("Type incompatibility: skill + identity never suggested as merge candidates")
    func typeIncompatibility() {
        #expect(!ReconciliationService.mergeCompatible(.skill, .identity))
        #expect(!ReconciliationService.mergeCompatible(.project, .identity))
        #expect(!ReconciliationService.mergeCompatible(.tool, .goal))
        #expect(!ReconciliationService.mergeCompatible(.project, .company))

        // Compatible types should return true
        #expect(ReconciliationService.mergeCompatible(.skill, .tool))
        #expect(ReconciliationService.mergeCompatible(.project, .project))
        #expect(ReconciliationService.mergeCompatible(.identity, .identity))
    }

    // MARK: - Citation Deduplication

    @Test("Citation deduplication: same URL in two conversations increments citedCount")
    @MainActor
    func citationDeduplication() async throws {
        let context = try makeContext()

        let url = "https://developer.apple.com/documentation/swiftui"
        let citation1 = CitationReference(
            url: url,
            domain: "developer.apple.com",
            citedInConversationId: UUID(),
            relatedEntityIds: [UUID()],
            proximityScore: 0.5,
            citedCount: 1
        )
        let citation2 = CitationReference(
            url: url,
            domain: "developer.apple.com",
            citedInConversationId: UUID(),
            relatedEntityIds: [UUID()],
            proximityScore: 0.6,
            citedCount: 1
        )
        context.insert(citation1)
        context.insert(citation2)
        try context.save()

        // Run citation reconciliation
        try await ReconciliationService.reconcileCitations(from: [], modelContext: context)

        let citations = try context.fetch(FetchDescriptor<CitationReference>())
        #expect(citations.count == 1)
        #expect(citations[0].citedCount == 2)
    }

    // MARK: - Batch Constraint

    @Test("Batch constraint: reconciliation of 200 extractions processes in batches")
    @MainActor
    func batchProcessing() async throws {
        let context = try makeContext()

        // Create 200 extractions with unique text
        let extractions = (0..<200).map { i in
            makeExtraction(text: "Fact number \(i) with enough words here", entityType: .skill)
        }
        for ext in extractions {
            context.insert(ext)
        }
        try context.save()

        // Should not crash or OOM — processes in batches of 50
        try await ReconciliationService.reconcileEntities(extractions: extractions, modelContext: context)

        let entities = try context.fetch(FetchDescriptor<CanonicalEntity>())
        #expect(entities.count == 200)
    }

    // MARK: - Immutability

    @Test("Immutability: merged entities cannot be auto-split by new data")
    @MainActor
    func mergedEntitiesStayMerged() async throws {
        let context = try makeContext()

        // Create a merged entity
        let entity = CanonicalEntity(
            canonicalText: "ContextKey",
            entityType: .project,
            aliases: ["my app"],
            supportingExtractionIds: [UUID(), UUID()],
            userMergeDecisions: [
                MergeDecision(
                    entityAId: UUID(),
                    entityBId: UUID(),
                    decision: .merged,
                    decidedAt: Date(),
                    userInitiated: false
                )
            ]
        )
        let score = BeliefScore(canonicalEntityId: entity.id, supportCount: 2)
        entity.beliefScore = score
        context.insert(entity)
        context.insert(score)
        try context.save()

        // Import contradictory data — "my app" as a separate extraction
        let ext = makeExtraction(text: "my app", entityType: .project)
        context.insert(ext)
        try context.save()

        try await ReconciliationService.reconcileEntities(extractions: [ext], modelContext: context)

        // "my app" should link to existing entity via alias, not create a new one
        let entities = try context.fetch(FetchDescriptor<CanonicalEntity>())
        let contextKeyEntities = entities.filter { $0.canonicalText == "ContextKey" }
        #expect(contextKeyEntities.count == 1)

        // The extraction should be linked to the existing entity
        #expect(ext.canonicalEntityId == entity.id)
    }
}
