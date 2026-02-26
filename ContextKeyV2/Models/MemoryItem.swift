import Foundation

// MARK: - Event Type

/// The semantic type of a candidate event extracted from user conversations.
/// Determines how the belief engine treats this item.
enum EventType: String, Codable, CaseIterable, Sendable {
    case goal           // "I want to ship by March"
    case preference     // "I prefer concise responses"
    case decision       // "I chose SwiftUI over UIKit"
    case constraint     // "No cloud processing"
    case skillClaim     // "I use Swift daily"
    case topic          // "machine learning" (mentioned, not claimed)
    case entity         // "ContextKey", "Xcode" (proper noun reference)
    case task           // "Fix the extraction pipeline"

    /// Whether this event type carries belief weight (affects scoring)
    /// or is metadata-only (useful for clustering but not scored)
    var kind: EventKind {
        switch self {
        case .goal, .preference, .decision, .constraint, .skillClaim, .task:
            return .beliefBearing
        case .topic, .entity:
            return .metadataOnly
        }
    }

    var displayName: String {
        switch self {
        case .goal: return "Goal"
        case .preference: return "Preference"
        case .decision: return "Decision"
        case .constraint: return "Constraint"
        case .skillClaim: return "Skill"
        case .topic: return "Topic"
        case .entity: return "Entity"
        case .task: return "Task"
        }
    }
}

/// Determines how the belief engine treats an event
enum EventKind: String, Codable, Sendable {
    case beliefBearing   // Participates in belief scoring, decay, contradictions
    case metadataOnly    // Useful for clustering/linking but no belief score
}

// MARK: - Sensitivity

/// How sensitive this memory item is — affects default Space assignment and export behavior
enum Sensitivity: String, Codable, Sendable {
    case normal      // Standard item, follows Space export policy
    case sensitive   // Defaults to Private space, excluded from exports unless user overrides
}

// MARK: - Evidence Reference

/// A link back to the source material that supports a MemoryItem.
/// References an InboxItem by ID, with optional position info.
struct EvidenceRef: Codable, Identifiable, Sendable {
    let id: UUID
    let inboxItemId: UUID           // Links to the InboxItem that produced this evidence
    let sourceLabel: String         // Human-readable: "Claude import, Jan 15"
    let timestamp: Date             // When the source material was created
    let snippetHash: String         // SHA-256 of the evidence text (integrity check)
    let offsetRange: OffsetRange?   // Optional position within the source

    init(
        id: UUID = UUID(),
        inboxItemId: UUID,
        sourceLabel: String,
        timestamp: Date,
        snippetHash: String,
        offsetRange: OffsetRange? = nil
    ) {
        self.id = id
        self.inboxItemId = inboxItemId
        self.sourceLabel = sourceLabel
        self.timestamp = timestamp
        self.snippetHash = snippetHash
        self.offsetRange = offsetRange
    }
}

/// Optional byte/character range within source text
struct OffsetRange: Codable, Sendable {
    let start: Int
    let end: Int
}

// MARK: - Memory Item

/// A single unit of user context with belief tracking, space membership, and provenance.
/// Replaces ContextFact as the core data model.
///
/// Key differences from ContextFact:
/// - `canonicalKey` for deterministic dedup/merge (not just string matching)
/// - `pillarScores` for multi-label pillar assignment
/// - `beliefScore` + decay/dampening fields instead of flat `confidence`
/// - `spaceMembership` for multi-space with user locks
/// - `variantGroupId` for contradiction tracking
/// - `evidence` with referential links to InboxItems
struct MemoryItem: Identifiable, Codable, Sendable {
    let id: UUID

    // --- Content ---
    var displayText: String          // User-facing text: "Uses Swift"
    var canonicalKey: String         // Deterministic key for matching: "skill:language:swift"

    // --- Classification ---
    var eventType: EventType         // goal, preference, skill_claim, etc.
    var pillarScores: [String: Double]  // ContextPillar.rawValue → score (0.0-1.0)
    // Note: Keyed by String (pillar rawValue) for Codable compatibility.
    // Use `pillarScore(for:)` and `setPillarScore(_:for:)` helpers.

    // --- Belief fields ---
    var beliefScore: Double          // p(active), 0.0-1.0
    var supportCount: Int            // How many distinct evidence sources support this
    var lastReinforced: Date         // Last time evidence was added
    var stability: Double            // How resistant to change (0.0=volatile, 1.0=rock-solid)

    // --- Space membership ---
    var primarySpace: SpaceID
    var primarySpaceLocked: Bool     // User explicitly chose this — classifier won't override
    var spaceMembership: [String: SpaceMembership]  // SpaceID.rawValue → membership
    // Note: Keyed by String for Codable compatibility.

    // --- Sensitivity ---
    var sensitivity: Sensitivity

    // --- Provenance ---
    var evidence: [EvidenceRef]      // Top 1-3 evidence references (not raw text)

    // --- Contradiction tracking ---
    var variantGroupId: UUID?        // Links competing beliefs (e.g., "prefer concise" vs "prefer detailed")

    // --- Timestamps ---
    var createdAt: Date
    var updatedAt: Date

    // --- Migration ---
    var legacyImport: Bool           // True if migrated from Build 15 ContextFact

    // MARK: - Init

    init(
        id: UUID = UUID(),
        displayText: String,
        canonicalKey: String,
        eventType: EventType,
        pillarScores: [ContextPillar: Double] = [:],
        beliefScore: Double = 0.5,
        supportCount: Int = 1,
        lastReinforced: Date = Date(),
        stability: Double = 0.0,
        primarySpace: SpaceID = .unsorted,
        primarySpaceLocked: Bool = false,
        sensitivity: Sensitivity = .normal,
        evidence: [EvidenceRef] = [],
        variantGroupId: UUID? = nil,
        legacyImport: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayText = displayText
        self.canonicalKey = canonicalKey
        self.eventType = eventType
        self.pillarScores = Dictionary(
            uniqueKeysWithValues: pillarScores.map { ($0.key.rawValue, $0.value) }
        )
        self.beliefScore = beliefScore
        self.supportCount = supportCount
        self.lastReinforced = lastReinforced
        self.stability = stability
        self.primarySpace = primarySpace
        self.primarySpaceLocked = primarySpaceLocked
        self.sensitivity = sensitivity
        self.evidence = evidence
        self.variantGroupId = variantGroupId
        self.createdAt = createdAt
        self.updatedAt = Date()
        self.legacyImport = legacyImport

        // Default space membership: primary = allowed, others = suggested
        // Include all spaces (real + unsorted) to ensure items are always visible somewhere
        var membership: [String: SpaceMembership] = [:]
        for space in SpaceID.allCases {
            if space == primarySpace {
                membership[space.rawValue] = .defaultAllowed
            } else if space == .unsorted && primarySpace != .unsorted {
                // Unsorted gets blocked if item has a real primary space
                membership[space.rawValue] = .defaultBlocked
            } else {
                membership[space.rawValue] = .defaultSuggested
            }
        }
        self.spaceMembership = membership
    }

    // MARK: - Pillar Helpers

    /// Get the score for a specific pillar
    func pillarScore(for pillar: ContextPillar) -> Double {
        pillarScores[pillar.rawValue] ?? 0.0
    }

    /// Set the score for a specific pillar
    mutating func setPillarScore(_ score: Double, for pillar: ContextPillar) {
        pillarScores[pillar.rawValue] = score
    }

    /// The highest-scoring pillar (derived, not stored separately)
    /// Returns nil if pillarScores is empty (item hasn't been classified yet)
    var primaryPillar: ContextPillar? {
        guard let topEntry = pillarScores.max(by: { $0.value < $1.value }),
              let pillar = ContextPillar(rawValue: topEntry.key) else {
            return nil
        }
        return pillar
    }

    /// The primary pillar or a sensible fallback (.persona) for UI display
    var primaryPillarOrDefault: ContextPillar {
        primaryPillar ?? .persona
    }

    /// All pillars with score above threshold, sorted by score descending
    func pillars(above threshold: Double = 0.3) -> [ContextPillar] {
        pillarScores
            .filter { $0.value >= threshold }
            .sorted { $0.value > $1.value }
            .compactMap { ContextPillar(rawValue: $0.key) }
    }

    // MARK: - Space Helpers

    /// Get membership for a space
    func membership(for space: SpaceID) -> SpaceMembership {
        spaceMembership[space.rawValue] ?? .defaultSuggested
    }

    /// Set membership for a space
    mutating func setMembership(_ membership: SpaceMembership, for space: SpaceID) {
        spaceMembership[space.rawValue] = membership
    }

    /// Whether this item is allowed in a given space
    func isAllowed(in space: SpaceID) -> Bool {
        membership(for: space).status == .allowed
    }

    // MARK: - Belief Helpers

    /// Whether this item participates in belief scoring
    var isBeliefBearing: Bool {
        eventType.kind == .beliefBearing
    }

    /// Whether belief is strong enough to be considered "active"
    var isActive: Bool {
        beliefScore >= 0.4
    }
}

// MARK: - Canonical Key Builder

/// Builds deterministic canonical keys for dedup and merge.
/// Format: `{eventType}:{domain}:{normalized_value}`
///
/// Examples:
/// - `skill:language:swift`
/// - `goal:product:ship-contextkey`
/// - `preference:communication:concise`
/// - `constraint:privacy:no-cloud`
/// - `entity:tool:xcode`
enum CanonicalKeyBuilder {
    /// Build a canonical key from components
    static func build(eventType: EventType, domain: String, value: String) -> String {
        let normalizedDomain = normalize(domain)
        let normalizedValue = normalize(value)
        return "\(eventType.rawValue):\(normalizedDomain):\(normalizedValue)"
    }

    /// Build a simple key when domain isn't known yet
    static func build(eventType: EventType, value: String) -> String {
        let normalizedValue = normalize(value)
        return "\(eventType.rawValue):general:\(normalizedValue)"
    }

    /// Normalize a string for canonical key use
    private static func normalize(_ input: String) -> String {
        input
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "_", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == ":" }
    }
}
