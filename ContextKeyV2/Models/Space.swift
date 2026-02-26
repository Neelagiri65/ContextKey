import Foundation

// MARK: - Space (Sharing Scope)

/// Spaces are sharing scopes — they control what context is visible and exportable.
/// Pre-seeded: Work, Personal, Private. User can view items per Space.
/// Spaces are NOT pillars. Pillars = "what kind of fact". Spaces = "who sees it".
enum SpaceID: String, Codable, CaseIterable, Sendable {
    case work
    case personal
    case `private`
    case unsorted

    var displayName: String {
        switch self {
        case .work: return "Work"
        case .personal: return "Personal"
        case .private: return "Private"
        case .unsorted: return "Unsorted"
        }
    }

    var iconName: String {
        switch self {
        case .work: return "briefcase.fill"
        case .personal: return "person.crop.circle.fill"
        case .private: return "lock.fill"
        case .unsorted: return "tray.fill"
        }
    }

    var color: String {
        switch self {
        case .work: return "blue"
        case .personal: return "green"
        case .private: return "red"
        case .unsorted: return "gray"
        }
    }

    /// Default time lens in days for this space
    var defaultTimeLensDays: Int {
        switch self {
        case .work: return 90
        case .personal: return 180
        case .private: return 45
        case .unsorted: return 90
        }
    }

    /// The three real spaces (excludes unsorted)
    static var realSpaces: [SpaceID] {
        [.work, .personal, .private]
    }
}

// MARK: - Export Policy

/// Controls what gets included when generating output from a Space
enum ExportPolicy: String, Codable, Sendable {
    case include              // All non-sensitive items included
    case excludeSensitive     // Sensitive items excluded (default for Work/Personal)
    case excludeAll           // Nothing exported (default for Private)
}

// MARK: - Space Configuration

/// Per-space settings (stored as part of the user's profile)
struct SpaceConfig: Codable, Sendable {
    let spaceId: SpaceID
    var displayName: String
    var timeLensDays: Int
    var exportPolicy: ExportPolicy

    /// Default configurations for the three pre-seeded spaces
    static var defaults: [SpaceConfig] {
        [
            SpaceConfig(
                spaceId: .work,
                displayName: "Work",
                timeLensDays: 90,
                exportPolicy: .excludeSensitive
            ),
            SpaceConfig(
                spaceId: .personal,
                displayName: "Personal",
                timeLensDays: 180,
                exportPolicy: .excludeSensitive
            ),
            SpaceConfig(
                spaceId: .private,
                displayName: "Private",
                timeLensDays: 45,
                exportPolicy: .excludeAll
            ),
            SpaceConfig(
                spaceId: .unsorted,
                displayName: "Unsorted",
                timeLensDays: 90,
                exportPolicy: .excludeAll
            ),
        ]
    }
}

// MARK: - Space Membership

/// How a MemoryItem relates to a specific Space
enum MembershipStatus: String, Codable, Sendable {
    case allowed     // Confirmed by user or system — included in this Space's output
    case blocked     // Explicitly excluded from this Space
    case suggested   // System suggests this Space, awaiting user confirmation
}

/// A MemoryItem's relationship to one Space
struct SpaceMembership: Codable, Sendable, Equatable {
    var status: MembershipStatus
    var locked: Bool  // User explicitly set this — classifier won't override

    static let defaultAllowed = SpaceMembership(status: .allowed, locked: false)
    static let defaultSuggested = SpaceMembership(status: .suggested, locked: false)
    static let defaultBlocked = SpaceMembership(status: .blocked, locked: false)
}
