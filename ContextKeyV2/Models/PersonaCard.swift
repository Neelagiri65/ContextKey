import Foundation

// MARK: - Persona Status

/// Lifecycle of a persona card
enum PersonaStatus: String, Codable, Sendable {
    case draft       // System-generated suggestion, not yet confirmed by user
    case confirmed   // User has saved/confirmed this persona
    case archived    // User dismissed or system dissolved (cluster lost stability)
}

// MARK: - Persona Membership Rule

/// Defines which MemoryItems belong to a persona.
/// Stored as a struct (not closure) for Codable serialization.
struct PersonaMembershipRule: Codable, Sendable {
    /// Only include items matching these pillars (nil = all pillars)
    var pillarFilters: [String]?  // ContextPillar rawValues

    /// Minimum belief score to include an item
    var beliefThreshold: Double

    /// Topic cluster keywords — items must match at least one (nil = no topic filter)
    var topicCluster: [String]?

    /// Event types to include (nil = all types)
    var eventTypeFilters: [String]?  // EventType rawValues

    init(
        pillarFilters: [ContextPillar]? = nil,
        beliefThreshold: Double = 0.4,
        topicCluster: [String]? = nil,
        eventTypeFilters: [EventType]? = nil
    ) {
        self.pillarFilters = pillarFilters?.map(\.rawValue)
        self.beliefThreshold = beliefThreshold
        self.topicCluster = topicCluster
        self.eventTypeFilters = eventTypeFilters?.map(\.rawValue)
    }

    /// Check if a MemoryItem matches this rule
    func matches(_ item: MemoryItem) -> Bool {
        // Belief threshold
        guard item.beliefScore >= beliefThreshold else { return false }

        // Pillar filter
        if let pillars = pillarFilters {
            let itemPillars = item.pillarScores.filter { $0.value >= 0.3 }.map(\.key)
            guard itemPillars.contains(where: { pillars.contains($0) }) else { return false }
        }

        // Topic cluster
        if let topics = topicCluster, !topics.isEmpty {
            let keyLower = item.canonicalKey.lowercased()
            let textLower = item.displayText.lowercased()
            guard topics.contains(where: { keyLower.contains($0.lowercased()) || textLower.contains($0.lowercased()) }) else {
                return false
            }
        }

        // Event type filter
        if let types = eventTypeFilters {
            guard types.contains(item.eventType.rawValue) else { return false }
        }

        return true
    }
}

// MARK: - Output Length

/// Controls how verbose the generated output is
enum OutputLength: String, Codable, CaseIterable, Sendable {
    case short    // 3-5 lines
    case medium   // 8-12 lines
    case long     // Full detail

    var displayName: String {
        switch self {
        case .short: return "Short"
        case .medium: return "Medium"
        case .long: return "Long"
        }
    }

    /// Approximate target line count
    var targetLines: Int {
        switch self {
        case .short: return 5
        case .medium: return 12
        case .long: return 30
        }
    }
}

// MARK: - Persona Card

/// A curated view of the user's context within a Space.
/// Generates ready-to-paste output (AI Prompt or Structured Notes).
///
/// Personas are clusters of MemoryItems:
/// - Goals + constraints + topics + entities + behaviors
/// - Each persona belongs to exactly one Space
/// - User must confirm before a persona becomes "saved"
struct PersonaCard: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String                     // User-editable: "iOS Developer", "Health Journey"
    var space: SpaceID                   // Which space this persona lives in
    var status: PersonaStatus            // draft, confirmed, archived
    var membershipRule: PersonaMembershipRule
    var stableSignature: String          // Hash of cluster composition for drift detection

    // --- Output settings ---
    var preferredOutputLength: OutputLength
    var includeSensitive: Bool           // Whether to include sensitive items in output

    // --- Timestamps ---
    var createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        space: SpaceID,
        status: PersonaStatus = .draft,
        membershipRule: PersonaMembershipRule = PersonaMembershipRule(),
        stableSignature: String = "",
        preferredOutputLength: OutputLength = .medium,
        includeSensitive: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.space = space
        self.status = status
        self.membershipRule = membershipRule
        self.stableSignature = stableSignature
        self.preferredOutputLength = preferredOutputLength
        self.includeSensitive = includeSensitive
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Filter MemoryItems that belong to this persona
    func matchingItems(from items: [MemoryItem]) -> [MemoryItem] {
        items.filter { item in
            // Must be allowed in this persona's space
            guard item.isAllowed(in: space) else { return false }

            // Sensitivity gate
            if !includeSensitive && item.sensitivity == .sensitive {
                return false
            }

            // Membership rule
            return membershipRule.matches(item)
        }
    }

    /// Whether this persona meets stability requirements for confirmation
    /// Requires items from at least 2 distinct time windows and minimum item count
    func meetsStabilityRequirements(items: [MemoryItem]) -> Bool {
        let matching = matchingItems(from: items)
        guard matching.count >= 3 else { return false }

        // Check for items from at least 2 distinct weeks
        let calendar = Calendar.current
        let weeks = Set(matching.compactMap { item in
            calendar.dateInterval(of: .weekOfYear, for: item.createdAt)?.start
        })
        return weeks.count >= 2
    }
}
