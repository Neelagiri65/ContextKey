import Foundation
import SwiftData

// MARK: - V2 Migration

/// Maps an existing ContextPillar to the closest V2 EntityType.
func mapPillarToEntityType(_ pillar: ContextPillar) -> EntityType {
    switch pillar {
    case .persona:            return .identity
    case .skillsAndStack:     return .skill
    case .communicationStyle:  return .preference
    case .activeProjects:     return .project
    case .goalsAndPriorities: return .goal
    case .constraints:        return .preference
    case .workPatterns:       return .preference
    }
}

/// Returns the primary FacetAssignment for a given EntityType.
/// Accepts an optional source pillar to disambiguate cases where
/// multiple pillars map to the same EntityType (e.g. .preference).
func mapEntityTypeToFacet(_ entityType: EntityType, sourcePillar: ContextPillar? = nil) -> FacetAssignment {
    switch entityType {
    case .skill:       return FacetAssignment(facetType: .technicalCapability, relevanceWeight: 1.0, isPrimary: true)
    case .tool:        return FacetAssignment(facetType: .technicalCapability, relevanceWeight: 0.9, isPrimary: true)
    case .project:     return FacetAssignment(facetType: .activeProjects, relevanceWeight: 1.0, isPrimary: true)
    case .goal:        return FacetAssignment(facetType: .goalsMotivations, relevanceWeight: 1.0, isPrimary: true)
    case .preference:
        if sourcePillar == .constraints {
            return FacetAssignment(facetType: .valuesConstraints, relevanceWeight: 1.0, isPrimary: true)
        }
        return FacetAssignment(facetType: .workingStyle, relevanceWeight: 1.0, isPrimary: true)
    case .identity:    return FacetAssignment(facetType: .professionalIdentity, relevanceWeight: 1.0, isPrimary: true)
    case .context:     return FacetAssignment(facetType: .currentContext, relevanceWeight: 1.0, isPrimary: true)
    case .domain:      return FacetAssignment(facetType: .domainKnowledge, relevanceWeight: 1.0, isPrimary: true)
    case .company:     return FacetAssignment(facetType: .professionalIdentity, relevanceWeight: 0.8, isPrimary: true)
    }
}

/// Half-life in days for each entity type, per Section 4.3 of the brief.
func halfLifeDays(for entityType: EntityType) -> Double {
    switch entityType {
    case .identity:   return 730.0
    case .skill:      return 180.0
    case .tool:       return 180.0
    case .project:    return 90.0
    case .goal:       return 180.0
    case .preference: return 365.0
    case .context:    return 14.0
    case .domain:     return 365.0
    case .company:    return 365.0
    }
}

/// Migrates all existing ContextFact records from the v1 encrypted storage
/// into the v2 SwiftData models: RawExtraction, CanonicalEntity, BeliefScore.
///
/// - Guarded by UserDefaults flag `hasRunV2Migration`. Runs exactly once.
/// - Forward-only: does not delete or overwrite any existing data.
/// - Does NOT wire to app launch. Must be called explicitly when ready.
///
/// - Parameters:
///   - existingFacts: The array of ContextFact from the loaded UserContextProfile
///   - modelContext: The SwiftData ModelContext to insert new records into
func runV2Migration(existingFacts: [ContextFact], modelContext: ModelContext) throws {
    guard !UserDefaults.standard.bool(forKey: "hasRunV2Migration") else {
        return
    }

    for fact in existingFacts {
        let entityType = mapPillarToEntityType(fact.pillar)
        let facetAssignment = mapEntityTypeToFacet(entityType, sourcePillar: fact.pillar)
        let conversationTimestamp = fact.createdAt

        // 1. Create RawExtraction
        let rawExtraction = RawExtraction(
            text: fact.content,
            entityType: entityType,
            sourceConversationId: UUID(),
            sourceChunkId: "migrated_v1",
            extractionTimestamp: Date(),
            conversationTimestamp: conversationTimestamp,
            speakerAttribution: .userExplicit,
            rawConfidence: 0.5,
            entityVerified: true,
            isActive: true
        )

        // 2. Create BeliefScore
        let beliefScore = BeliefScore(
            canonicalEntityId: UUID(),
            currentScore: 0.5,
            supportCount: max(fact.frequency, 1),
            lastCalculated: Date(),
            lastCorroboratedDate: fact.lastSeenDate,
            attributionWeight: 1.0,
            userFeedbackDelta: 0.0,
            halfLifeDays: halfLifeDays(for: entityType),
            stabilityFloorActive: fact.frequency >= 3
        )

        // 3. Create CanonicalEntity
        let canonicalEntity = CanonicalEntity(
            canonicalText: fact.content,
            entityType: entityType,
            aliases: [],
            firstSeenDate: conversationTimestamp,
            lastSeenDate: fact.lastSeenDate,
            supportingExtractionIds: [rawExtraction.id],
            userMergeDecisions: [],
            facetAssignments: [facetAssignment],
            beliefScore: beliefScore
        )

        // 4. Link RawExtraction → CanonicalEntity
        rawExtraction.canonicalEntityId = canonicalEntity.id

        // 5. Fix BeliefScore.canonicalEntityId to match actual entity
        beliefScore.canonicalEntityId = canonicalEntity.id

        // 6. Insert into SwiftData context
        modelContext.insert(rawExtraction)
        modelContext.insert(beliefScore)
        modelContext.insert(canonicalEntity)
    }

    try modelContext.save()

    UserDefaults.standard.set(true, forKey: "hasRunV2Migration")
}
