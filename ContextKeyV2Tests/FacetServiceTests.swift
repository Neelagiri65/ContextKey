import Foundation
import Testing
import SwiftData
@testable import ContextKeyV2

@Suite("FacetService Tests — Build 20")
struct FacetServiceTests {

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: RawExtraction.self, CanonicalEntity.self, BeliefScore.self,
                 CitationReference.self, ImportedConversation.self, ContextCard.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @MainActor
    private func makeEntity(
        text: String,
        entityType: EntityType,
        score: Double,
        context: ModelContext
    ) -> CanonicalEntity {
        let entityId = UUID()
        let beliefScore = BeliefScore(
            canonicalEntityId: entityId,
            currentScore: score,
            supportCount: 3,
            lastCorroboratedDate: Date(),
            attributionWeight: 1.0,
            halfLifeDays: BeliefEngine.halfLifeByType[entityType] ?? 365.0,
            stabilityFloorActive: false
        )
        let entity = CanonicalEntity(
            id: entityId,
            canonicalText: text,
            entityType: entityType,
            beliefScore: beliefScore
        )
        context.insert(entity)
        context.insert(beliefScore)
        return entity
    }

    // MARK: - Test 1: Facet with 0 entities → not shown

    @Test("Facet with 0 entities → not shown")
    @MainActor
    func facetWithZeroEntitiesNotShown() throws {
        let context = try makeContext()
        // No entities at all
        let entities: [CanonicalEntity] = []
        let visible = FacetService.visibleFacets(from: entities)
        #expect(visible.isEmpty, "No facets should be visible with 0 entities")
    }

    // MARK: - Test 2: Facet with 1 entity → not shown

    @Test("Facet with 1 entity → not shown")
    @MainActor
    func facetWithOneEntityNotShown() throws {
        let context = try makeContext()
        // One skill entity — technicalCapability facet gets 1 entity, not enough
        let _ = makeEntity(text: "Swift", entityType: .skill, score: 0.80, context: context)
        try context.save()

        let entities = try context.fetch(FetchDescriptor<CanonicalEntity>())
        let visible = FacetService.visibleFacets(from: entities)

        let techCap = visible[.technicalCapability]
        #expect(techCap == nil, "technicalCapability with only 1 entity should not be visible")
    }

    // MARK: - Test 3: Facet with 2+ entities above threshold → shown

    @Test("Facet with 2+ entities above threshold → shown")
    @MainActor
    func facetWithTwoPlusEntitiesShown() throws {
        let context = try makeContext()
        let _ = makeEntity(text: "Swift", entityType: .skill, score: 0.80, context: context)
        let _ = makeEntity(text: "Python", entityType: .skill, score: 0.65, context: context)
        try context.save()

        let entities = try context.fetch(FetchDescriptor<CanonicalEntity>())
        let visible = FacetService.visibleFacets(from: entities)

        let techCap = visible[.technicalCapability]
        #expect(techCap != nil, "technicalCapability with 2 skill entities should be visible")
        #expect(techCap?.count == 2, "Should contain both entities, got \(techCap?.count ?? 0)")
    }

    // MARK: - Test 4: Skill entity appears in technicalCapability facet (primary)

    @Test("Skill entity appears in technicalCapability facet (primary)")
    @MainActor
    func skillEntityInTechnicalCapabilityFacet() throws {
        let context = try makeContext()
        let swift = makeEntity(text: "Swift", entityType: .skill, score: 0.80, context: context)
        let python = makeEntity(text: "Python", entityType: .skill, score: 0.65, context: context)
        try context.save()

        let entities = try context.fetch(FetchDescriptor<CanonicalEntity>())
        let grouped = FacetService.groupByFacet(entities: entities)

        // Skill maps to technicalCapability (1.0) and professionalIdentity (0.3)
        let techCap = grouped[.technicalCapability] ?? []
        let techCapTexts = techCap.map(\.canonicalText)
        #expect(techCapTexts.contains("Swift"), "Swift should appear in technicalCapability")
        #expect(techCapTexts.contains("Python"), "Python should appear in technicalCapability")

        // Also appears in professionalIdentity as secondary
        let profId = grouped[.professionalIdentity] ?? []
        let profIdTexts = profId.map(\.canonicalText)
        #expect(profIdTexts.contains("Swift"), "Swift should also appear in professionalIdentity (secondary)")
    }

    // MARK: - Test 5: Preference entity appears in valuesConstraints, not only workingStyle

    @Test("Constraints pillar facts appear in valuesConstraints facet (not workingStyle)")
    @MainActor
    func preferenceEntityAppearsInValuesConstraints() throws {
        let context = try makeContext()
        // Preference maps to workingStyle (1.0) AND valuesConstraints (0.3)
        let _ = makeEntity(text: "Never compromise on code quality", entityType: .preference, score: 0.70, context: context)
        let _ = makeEntity(text: "Privacy is non-negotiable", entityType: .preference, score: 0.65, context: context)
        try context.save()

        let entities = try context.fetch(FetchDescriptor<CanonicalEntity>())
        let grouped = FacetService.groupByFacet(entities: entities)

        // Must appear in valuesConstraints
        let valuesConstraints = grouped[.valuesConstraints] ?? []
        let vcTexts = valuesConstraints.map(\.canonicalText)
        #expect(vcTexts.contains("Never compromise on code quality"), "Should appear in valuesConstraints")
        #expect(vcTexts.contains("Privacy is non-negotiable"), "Should appear in valuesConstraints")

        // Also appears in workingStyle (primary)
        let workingStyle = grouped[.workingStyle] ?? []
        #expect(workingStyle.count == 2, "Should also appear in workingStyle as primary")
    }
}
