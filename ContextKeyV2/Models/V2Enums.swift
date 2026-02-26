import Foundation

// MARK: - V2 Pipeline Enums

/// The type of entity extracted from a conversation
enum EntityType: String, Codable, CaseIterable {
    case skill         // Swift, SwiftUI, Python
    case tool          // Xcode, Linear, Notion
    case project       // ContextKey, Build 17
    case goal          // Launch on App Store, close enterprise deal
    case preference    // Prefers async communication, likes first principles
    case identity      // iOS developer, Strategic Account Executive
    case context       // Currently debugging crash in Build 16, job searching
    case domain        // Enterprise software, fintech, developer tools
}

/// How the fact was attributed to the user
enum AttributionType: String, Codable {
    case userExplicit       // User said it directly in first person
    case userImplied        // Implied by user's questions or decisions
    case assistantSuggested // AI said it, user never confirmed
    case ambiguous          // Cannot determine from text
}

/// The eight identity facets for grouping entities
enum FacetType: String, Codable, CaseIterable {
    case professionalIdentity   // role, company, domain
    case technicalCapability    // skills, tools, languages, frameworks
    case activeProjects         // current builds, recent ships
    case goalsMotivations       // what drives them, where they're heading
    case workingStyle           // communication preferences, decision patterns
    case valuesConstraints      // principles, non-negotiables
    case domainKnowledge        // industries and subjects known deeply
    case currentContext         // immediate priorities, blockers, deadlines
}

/// Status of the extraction pipeline for an imported conversation
enum ExtractionStatus: String, Codable {
    case pending
    case processing
    case complete
    case failed
}

/// User's decision when presented with a merge suggestion
enum MergeDecisionType: String, Codable {
    case merged
    case kept_separate
}
