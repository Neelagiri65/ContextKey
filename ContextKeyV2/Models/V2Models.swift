import Foundation
import SwiftData

// MARK: - V2 Pipeline SwiftData Models

// MARK: - RawExtraction

/// Stores everything the SLM outputs, exactly as it outputs it, before any reconciliation.
@Model
final class RawExtraction {
    @Attribute(.unique) var id: UUID
    var text: String
    var entityType: EntityType
    var sourceConversationId: UUID
    var sourceChunkId: String
    var extractionTimestamp: Date
    var conversationTimestamp: Date
    var speakerAttribution: AttributionType
    var rawConfidence: Double
    var entityVerified: Bool
    var canonicalEntityId: UUID?
    var isActive: Bool

    init(
        id: UUID = UUID(),
        text: String,
        entityType: EntityType,
        sourceConversationId: UUID,
        sourceChunkId: String,
        extractionTimestamp: Date = Date(),
        conversationTimestamp: Date,
        speakerAttribution: AttributionType,
        rawConfidence: Double = 0.5,
        entityVerified: Bool = false,
        canonicalEntityId: UUID? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.text = text
        self.entityType = entityType
        self.sourceConversationId = sourceConversationId
        self.sourceChunkId = sourceChunkId
        self.extractionTimestamp = extractionTimestamp
        self.conversationTimestamp = conversationTimestamp
        self.speakerAttribution = speakerAttribution
        self.rawConfidence = rawConfidence
        self.entityVerified = entityVerified
        self.canonicalEntityId = canonicalEntityId
        self.isActive = isActive
    }
}

// MARK: - ImportedConversation

/// Tracks every conversation the user has pasted in.
@Model
final class ImportedConversation {
    @Attribute(.unique) var id: UUID
    var platform: Platform
    var rawText: String
    var importDate: Date
    var estimatedConversationDate: Date?
    var extractionStatus: ExtractionStatus
    var chunkCount: Int
    var extractionCount: Int
    var processingDurationSeconds: Double?

    init(
        id: UUID = UUID(),
        platform: Platform,
        rawText: String,
        importDate: Date = Date(),
        estimatedConversationDate: Date? = nil,
        extractionStatus: ExtractionStatus = .pending,
        chunkCount: Int = 0,
        extractionCount: Int = 0,
        processingDurationSeconds: Double? = nil
    ) {
        self.id = id
        self.platform = platform
        self.rawText = rawText
        self.importDate = importDate
        self.estimatedConversationDate = estimatedConversationDate
        self.extractionStatus = extractionStatus
        self.chunkCount = chunkCount
        self.extractionCount = extractionCount
        self.processingDurationSeconds = processingDurationSeconds
    }
}

// MARK: - CanonicalEntity

/// The deduplicated, merged identity of a fact.
/// Multiple RawExtractions can point to one CanonicalEntity.
@Model
final class CanonicalEntity {
    @Attribute(.unique) var id: UUID
    var canonicalText: String
    var entityType: EntityType
    var aliases: [String]
    var firstSeenDate: Date
    var lastSeenDate: Date
    var supportingExtractionIds: [UUID]
    var userMergeDecisions: [MergeDecision]
    var facetAssignments: [FacetAssignment]
    @Relationship(deleteRule: .nullify) var beliefScore: BeliefScore?
    var citationIds: [UUID]
    var pendingAliasCandidates: [PendingAliasCandidate]
    var hasMergeConflict: Bool

    init(
        id: UUID = UUID(),
        canonicalText: String,
        entityType: EntityType,
        aliases: [String] = [],
        firstSeenDate: Date = Date(),
        lastSeenDate: Date = Date(),
        supportingExtractionIds: [UUID] = [],
        userMergeDecisions: [MergeDecision] = [],
        facetAssignments: [FacetAssignment] = [],
        beliefScore: BeliefScore? = nil,
        citationIds: [UUID] = [],
        pendingAliasCandidates: [PendingAliasCandidate] = [],
        hasMergeConflict: Bool = false
    ) {
        self.id = id
        self.canonicalText = canonicalText
        self.entityType = entityType
        self.aliases = aliases
        self.firstSeenDate = firstSeenDate
        self.lastSeenDate = lastSeenDate
        self.supportingExtractionIds = supportingExtractionIds
        self.userMergeDecisions = userMergeDecisions
        self.facetAssignments = facetAssignments
        self.beliefScore = beliefScore
        self.citationIds = citationIds
        self.pendingAliasCandidates = pendingAliasCandidates
        self.hasMergeConflict = hasMergeConflict
    }
}

// MARK: - BeliefScore

/// The mathematical confidence score for a CanonicalEntity.
@Model
final class BeliefScore {
    @Attribute(.unique) var id: UUID
    var canonicalEntityId: UUID
    var currentScore: Double
    var supportCount: Int
    var lastCalculated: Date
    var lastCorroboratedDate: Date
    var attributionWeight: Double
    var userFeedbackDelta: Double
    var halfLifeDays: Double
    var stabilityFloorActive: Bool
    var externalCorroboration: Double

    init(
        id: UUID = UUID(),
        canonicalEntityId: UUID,
        currentScore: Double = 0.5,
        supportCount: Int = 1,
        lastCalculated: Date = Date(),
        lastCorroboratedDate: Date = Date(),
        attributionWeight: Double = 1.0,
        userFeedbackDelta: Double = 0.0,
        halfLifeDays: Double = 365.0,
        stabilityFloorActive: Bool = false,
        externalCorroboration: Double = 0.0
    ) {
        self.id = id
        self.canonicalEntityId = canonicalEntityId
        self.currentScore = currentScore
        self.supportCount = supportCount
        self.lastCalculated = lastCalculated
        self.lastCorroboratedDate = lastCorroboratedDate
        self.attributionWeight = attributionWeight
        self.userFeedbackDelta = userFeedbackDelta
        self.halfLifeDays = halfLifeDays
        self.stabilityFloorActive = stabilityFloorActive
        self.externalCorroboration = externalCorroboration
    }
}

// MARK: - ContextCard

/// The final generated output that the user copies.
@Model
final class ContextCard {
    @Attribute(.unique) var id: UUID
    var generatedText: String
    var targetPlatform: Platform
    var generatedAt: Date
    var facetSnapshots: [FacetSnapshot]
    var userCopiedAt: Date?
    var beliefBoostApplied: Bool

    init(
        id: UUID = UUID(),
        generatedText: String,
        targetPlatform: Platform,
        generatedAt: Date = Date(),
        facetSnapshots: [FacetSnapshot] = [],
        userCopiedAt: Date? = nil,
        beliefBoostApplied: Bool = false
    ) {
        self.id = id
        self.generatedText = generatedText
        self.targetPlatform = targetPlatform
        self.generatedAt = generatedAt
        self.facetSnapshots = facetSnapshots
        self.userCopiedAt = userCopiedAt
        self.beliefBoostApplied = beliefBoostApplied
    }
}

// MARK: - Supporting Codable Structs

/// A join between a CanonicalEntity and a Facet, with relevance weight.
struct FacetAssignment: Codable {
    var facetType: FacetType
    var relevanceWeight: Double
    var isPrimary: Bool
}

/// Records what the user decided when presented with a merge suggestion.
struct MergeDecision: Codable {
    var entityAId: UUID
    var entityBId: UUID
    var decision: MergeDecisionType
    var decidedAt: Date
    var userInitiated: Bool
}

/// Records which facet data was used to generate a context card.
struct FacetSnapshot: Codable {
    var facetType: FacetType
    var entityIds: [UUID]
}

/// A Tier B merge candidate awaiting auto-promotion to alias.
struct PendingAliasCandidate: Codable {
    var extractionId: UUID
    var candidateEntityId: UUID
    var coOccurrenceCount: Int
    var firstSeen: Date
}

// MARK: - CitationReference

/// Tracks URLs and external references found in conversations,
/// linked to nearby CanonicalEntities for evidence attribution.
@Model
final class CitationReference {
    @Attribute(.unique) var id: UUID
    var url: String
    var domain: String              // apple.com, docs.swift.org etc
    var title: String?              // page title if extractable from text
    var citedInConversationId: UUID
    var relatedEntityIds: [UUID]    // CanonicalEntities nearby in the conversation
    var proximityScore: Double      // how close the citation was to related entities
    var firstCitedDate: Date
    var citedCount: Int             // times this URL appeared across all conversations

    init(
        id: UUID = UUID(),
        url: String,
        domain: String,
        title: String? = nil,
        citedInConversationId: UUID,
        relatedEntityIds: [UUID] = [],
        proximityScore: Double = 0.0,
        firstCitedDate: Date = Date(),
        citedCount: Int = 1
    ) {
        self.id = id
        self.url = url
        self.domain = domain
        self.title = title
        self.citedInConversationId = citedInConversationId
        self.relatedEntityIds = relatedEntityIds
        self.proximityScore = proximityScore
        self.firstCitedDate = firstCitedDate
        self.citedCount = citedCount
    }
}
