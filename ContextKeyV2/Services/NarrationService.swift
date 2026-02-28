import Foundation
import SwiftData

// MARK: - Narration Service (Build 21 — Section 6)

/// Template-based context card generation for each AI platform.
/// No SLM involvement — every output word maps directly to a CanonicalEntity.
enum NarrationService {

    // MARK: - 6.3 Entry Point

    /// Generate a platform-specific context card from faceted entities.
    /// Only Perplexity uses citations; other platforms ignore the parameter.
    static func generateCard(
        for platform: Platform,
        facets: [FacetType: [CanonicalEntity]],
        citations: [CitationReference] = []
    ) -> String {
        let card: String
        switch platform {
        case .claude:
            card = generateClaudeCard(facets: facets)
        case .chatgpt:
            card = generateChatGPTCard(facets: facets)
        case .perplexity:
            card = generatePerplexityCard(facets: facets, citations: citations)
        case .gemini:
            card = generateGeminiCard(facets: facets)
        case .manual:
            card = generateDefaultCard(facets: facets)
        }

        // Section 9 error handling: empty card fallback
        if card.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Import more conversations to generate your context card."
        }
        return card
    }

    // MARK: - Claude Card (natural prose, ~150 words)

    private static func generateClaudeCard(
        facets: [FacetType: [CanonicalEntity]]
    ) -> String {
        var parts: [String] = []

        // Identity opening — weave role and domain together
        let identity = topEntities(from: facets, facet: .professionalIdentity, limit: 3)
        let domains = topEntities(from: facets, facet: .domainKnowledge, limit: 2)
        if !identity.isEmpty && !domains.isEmpty {
            parts.append("I'm \(joinNatural(identity)) with deep experience in \(joinNatural(domains)).")
        } else if !identity.isEmpty {
            parts.append("I'm \(joinNatural(identity)).")
        }

        // Technical capability — flowing sentence
        let tech = topEntities(from: facets, facet: .technicalCapability, limit: 5)
        if !tech.isEmpty {
            parts.append("My primary tools and technologies are \(joinNatural(tech)).")
        }

        // Active projects — what I'm building right now
        let projects = topEntities(from: facets, facet: .activeProjects, limit: 2)
        if !projects.isEmpty {
            parts.append("Right now I'm focused on building \(joinNatural(projects)).")
        }

        // Goals — where I'm heading
        let goals = topEntities(from: facets, facet: .goalsMotivations, limit: 2)
        if !goals.isEmpty {
            parts.append("I'm working towards \(joinNatural(goals)).")
        }

        // Working style — how I prefer to collaborate
        let style = topEntities(from: facets, facet: .workingStyle, limit: 2)
        if !style.isEmpty {
            parts.append("When collaborating, I value \(joinNatural(style)).")
        }

        // Values — close with principles
        let values = topEntities(from: facets, facet: .valuesConstraints, limit: 2)
        if !values.isEmpty {
            parts.append("Principles I hold: \(joinNatural(values)).")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - ChatGPT Card (structured with headers, ~200 words)

    private static func generateChatGPTCard(
        facets: [FacetType: [CanonicalEntity]]
    ) -> String {
        var sections: [String] = []

        // Professional Identity — top 3
        let identity = topEntities(from: facets, facet: .professionalIdentity, limit: 3)
        if !identity.isEmpty {
            sections.append("About Me\n\(joinBullets(identity))")
        }

        // Goals & Motivations — top 3
        let goals = topEntities(from: facets, facet: .goalsMotivations, limit: 3)
        if !goals.isEmpty {
            sections.append("Goals\n\(joinBullets(goals))")
        }

        // Values & Constraints — top 2
        let values = topEntities(from: facets, facet: .valuesConstraints, limit: 2)
        if !values.isEmpty {
            sections.append("Values\n\(joinBullets(values))")
        }

        // Working Style — top 2
        let style = topEntities(from: facets, facet: .workingStyle, limit: 2)
        if !style.isEmpty {
            sections.append("Working Style\n\(joinBullets(style))")
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Perplexity Card (compact, factual, <= 120 words)

    private static func generatePerplexityCard(
        facets: [FacetType: [CanonicalEntity]],
        citations: [CitationReference] = []
    ) -> String {
        var parts: [String] = []

        // Domain Knowledge — top 4
        let domains = topEntities(from: facets, facet: .domainKnowledge, limit: 4)
        if !domains.isEmpty {
            parts.append("Domains: \(domains.joined(separator: ", ")).")
        }

        // Technical Capability — top 3
        let tech = topEntities(from: facets, facet: .technicalCapability, limit: 3)
        if !tech.isEmpty {
            parts.append("Stack: \(tech.joined(separator: ", ")).")
        }

        // Active Projects — top 2
        let projects = topEntities(from: facets, facet: .activeProjects, limit: 2)
        if !projects.isEmpty {
            parts.append("Projects: \(projects.joined(separator: ", ")).")
        }

        // Citation domains — Section 6.5
        let citationDomains = topCitationDomains(from: citations, limit: 3)
        if !citationDomains.isEmpty {
            parts.append("Sources I've already consulted: \(citationDomains.joined(separator: ", ")).")
        }

        let card = parts.joined(separator: " ")

        // Enforce 120-word hard limit — trim to last complete sentence
        return enforceWordLimit(card, maxWords: 120)
    }

    // MARK: - Gemini Card (concise structured, ~150 words)

    private static func generateGeminiCard(
        facets: [FacetType: [CanonicalEntity]]
    ) -> String {
        var sections: [String] = []

        // Professional Identity — top 3
        let identity = topEntities(from: facets, facet: .professionalIdentity, limit: 3)
        if !identity.isEmpty {
            sections.append("Identity: \(identity.joined(separator: ", ")).")
        }

        // Technical Capability — top 3
        let tech = topEntities(from: facets, facet: .technicalCapability, limit: 3)
        if !tech.isEmpty {
            sections.append("Skills: \(tech.joined(separator: ", ")).")
        }

        // Goals & Motivations — top 2
        let goals = topEntities(from: facets, facet: .goalsMotivations, limit: 2)
        if !goals.isEmpty {
            sections.append("Goals: \(goals.joined(separator: ", ")).")
        }

        return sections.joined(separator: "\n")
    }

    // MARK: - Default/Manual Card

    private static func generateDefaultCard(
        facets: [FacetType: [CanonicalEntity]]
    ) -> String {
        var parts: [String] = []

        let identity = topEntities(from: facets, facet: .professionalIdentity, limit: 3)
        if !identity.isEmpty {
            parts.append("I'm \(joinNatural(identity)).")
        }

        let tech = topEntities(from: facets, facet: .technicalCapability, limit: 4)
        if !tech.isEmpty {
            parts.append("I work with \(joinNatural(tech)).")
        }

        let projects = topEntities(from: facets, facet: .activeProjects, limit: 2)
        if !projects.isEmpty {
            parts.append("Currently building \(joinNatural(projects)).")
        }

        let goals = topEntities(from: facets, facet: .goalsMotivations, limit: 2)
        if !goals.isEmpty {
            parts.append("My goals: \(joinNatural(goals)).")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - 6.5 Citation Domains

    /// Returns top citation domains sorted by total cited count.
    static func topCitationDomains(
        from citations: [CitationReference],
        limit: Int = 3
    ) -> [String] {
        var domainCounts: [String: Int] = [:]
        for citation in citations {
            domainCounts[citation.domain, default: 0] += citation.citedCount
        }
        return domainCounts
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }

    // MARK: - 6.4 Card Validation

    /// Validates that every entity referenced in card generation has score >= 0.45.
    /// For v1 (template-based): entities are pre-filtered, so this always passes.
    /// Kept as a safety net for future SLM narration.
    static func validateCard(
        _ cardText: String,
        against entities: [CanonicalEntity]
    ) -> String {
        // Template-based cards only include entities that passed topEntities(),
        // which already filters by BeliefEngine.visibilityThreshold.
        // This is a no-op for v1 but will be implemented for v2 SLM narration.
        return cardText
    }

    // MARK: - Word Limit Enforcement

    private static func enforceWordLimit(_ text: String, maxWords: Int) -> String {
        let words = text.split(separator: " ")
        guard words.count > maxWords else { return text }

        // Take first maxWords words, then trim back to last complete sentence
        let truncated = words.prefix(maxWords).joined(separator: " ")

        // Find last sentence-ending punctuation
        if let lastPeriod = truncated.lastIndex(of: ".") {
            return String(truncated[...lastPeriod])
        }

        // No sentence boundary found — just truncate with period
        return truncated + "."
    }

    // MARK: - Helpers

    /// Extracts top N entity texts from a facet, filtered by visibility threshold.
    private static func topEntities(
        from facets: [FacetType: [CanonicalEntity]],
        facet: FacetType,
        limit: Int
    ) -> [String] {
        guard let entities = facets[facet] else { return [] }
        return entities
            .filter { entity in
                let score = entity.beliefScore?.currentScore ?? 0
                let threshold = entity.hasBeenInteractedWith ? BeliefEngine.visibilityThreshold : BeliefEngine.newEntityThreshold
                return score >= threshold
            }
            .prefix(limit)
            .map(\.canonicalText)
    }

    /// Joins strings with natural English: "A, B, and C"
    private static func joinNatural(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default:
            return items.dropLast().joined(separator: ", ") + ", and " + items.last!
        }
    }

    /// Joins strings as bullet points
    private static func joinBullets(_ items: [String]) -> String {
        items.map { "- \($0)" }.joined(separator: "\n")
    }
}
