import Foundation
import SwiftData

// MARK: - Facet Service (Build 20 — Section 5)

/// Assigns CanonicalEntities to facets and determines facet visibility.
/// Pure logic — no UI. Reads from SwiftData, returns computed facet groups.
enum FacetService {

    // MARK: - 5.1 Entity Type → Facet Assignment Map

    static let entityTypeToFacets: [EntityType: [(FacetType, Double)]] = [
        .skill:      [(.technicalCapability, 1.0), (.professionalIdentity, 0.3)],
        .tool:       [(.technicalCapability, 0.9), (.currentContext, 0.2)],
        .project:    [(.activeProjects, 1.0), (.currentContext, 0.5)],
        .goal:       [(.goalsMotivations, 1.0), (.currentContext, 0.4)],
        .preference: [(.workingStyle, 1.0), (.valuesConstraints, 0.3)],
        .identity:   [(.professionalIdentity, 1.0)],
        .context:    [(.currentContext, 1.0), (.activeProjects, 0.3)],
        .domain:     [(.domainKnowledge, 1.0), (.professionalIdentity, 0.3)],
        .company:    [(.professionalIdentity, 0.8), (.domainKnowledge, 0.3)]
    ]

    // MARK: - Facet Grouping

    /// Groups visible entities into their assigned facets, sorted by relevance weight.
    static func groupByFacet(
        entities: [CanonicalEntity]
    ) -> [FacetType: [CanonicalEntity]] {
        let visible = BeliefEngine.visibleEntities(from: entities)
        var result: [FacetType: [(CanonicalEntity, Double)]] = [:]

        for entity in visible {
            guard let assignments = entityTypeToFacets[entity.entityType] else { continue }
            for (facet, weight) in assignments {
                result[facet, default: []].append((entity, weight))
            }
        }

        // Sort each facet's entities by relevance weight descending,
        // then by belief score descending as tiebreaker
        return result.mapValues { pairs in
            pairs
                .sorted { a, b in
                    if a.1 != b.1 { return a.1 > b.1 }
                    return (a.0.beliefScore?.currentScore ?? 0) > (b.0.beliefScore?.currentScore ?? 0)
                }
                .map(\.0)
        }
    }

    // MARK: - 5.2 Facet Visibility Rule

    /// Returns only facets with >= 2 entities above the visibility threshold.
    static func visibleFacets(
        from entities: [CanonicalEntity]
    ) -> [FacetType: [CanonicalEntity]] {
        let grouped = groupByFacet(entities: entities)
        return grouped.filter { $0.value.count >= 2 }
    }

    /// Returns facets that exist but don't meet the visibility threshold.
    /// Used for empty-state prompts.
    static func emptyFacets(
        from entities: [CanonicalEntity]
    ) -> [FacetType] {
        let visible = visibleFacets(from: entities)
        let allFacets = Set(FacetType.allCases)
        let shownFacets = Set(visible.keys)

        return allFacets.subtracting(shownFacets)
            .sorted { $0.rawValue < $1.rawValue }
    }

    // MARK: - Empty Facet Prompts

    static func prompt(for facet: FacetType) -> String {
        switch facet {
        case .professionalIdentity:
            return "Import a conversation about your role or career to enrich your profile."
        case .technicalCapability:
            return "Import a conversation about your skills or tools to enrich your profile."
        case .activeProjects:
            return "Import a conversation about what you're building to enrich your profile."
        case .goalsMotivations:
            return "Import a conversation about your goals to enrich your profile."
        case .workingStyle:
            return "Import a conversation about how you prefer to work to enrich your profile."
        case .valuesConstraints:
            return "Import a conversation about your principles or constraints to enrich your profile."
        case .domainKnowledge:
            return "Import a conversation about your area of expertise to enrich your profile."
        case .currentContext:
            return "Import a conversation about what you're focused on right now to enrich your profile."
        }
    }

    // MARK: - Facet Display Name

    static func displayName(for facet: FacetType) -> String {
        switch facet {
        case .professionalIdentity: return "Professional Identity"
        case .technicalCapability:  return "Technical Capability"
        case .activeProjects:       return "Active Projects"
        case .goalsMotivations:     return "Goals & Motivations"
        case .workingStyle:         return "Working Style"
        case .valuesConstraints:    return "Values & Constraints"
        case .domainKnowledge:      return "Domain Knowledge"
        case .currentContext:       return "Current Context"
        }
    }
}
