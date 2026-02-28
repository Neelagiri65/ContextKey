import Foundation
import SwiftData

// MARK: - Belief Engine (Build 19 — Section 4)

/// Calculates and manages belief scores for CanonicalEntities.
/// Pure math — no UI, no SwiftData fetching in the formula itself.
enum BeliefEngine {

    // MARK: - Constants

    static let visibilityThreshold = 0.45

    static let halfLifeByType: [EntityType: Double] = [
        .identity: 730.0, .skill: 180.0, .tool: 180.0,
        .project: 90.0, .goal: 180.0, .preference: 365.0,
        .context: 14.0, .domain: 365.0, .company: 365.0
    ]

    // MARK: - 4.1 The Formula

    /// Calculate belief score from entity and its score record.
    /// Returns clamped 0.0–1.0. NaN returns 0.5 per Section 9 error matrix.
    static func calculateBeliefScore(
        for entity: CanonicalEntity,
        score: BeliefScore
    ) -> Double {
        // 1. Support factor (logarithmically dampened)
        let supportFactor = log(1.0 + Double(score.supportCount))

        // 2. Recency factor (exponential decay with entity-type-specific half-life)
        let daysSince = Date().timeIntervalSince(score.lastCorroboratedDate) / 86400.0
        let recencyFactor = pow(0.5, daysSince / score.halfLifeDays)

        // 3. Attribution weight — use the score's stored weight
        //    (set from extraction's speakerAttribution during reconciliation)
        let attributionWeight = score.attributionWeight

        // 4. External corroboration (from citations, capped at 0.3)
        let corroborationBoost = min(score.externalCorroboration, 0.3)

        // 5. User feedback delta (capped at 0.3)
        let feedbackDelta = min(score.userFeedbackDelta, 0.3)

        // 6. Base confidence
        let baseConfidence = 0.5

        // 7. Raw score
        let rawScore = baseConfidence
            * (supportFactor / 5.0)
            * recencyFactor
            * attributionWeight
            + corroborationBoost
            + feedbackDelta

        // 8. NaN guard (Section 9)
        guard !rawScore.isNaN else {
            print("[BeliefEngine] NaN detected for entity \(entity.id), clamping to 0.5")
            return 0.5
        }

        // 9. Stability floor
        let floor = score.stabilityFloorActive ? 0.4 : 0.0

        return min(max(rawScore, floor), 1.0)
    }

    // MARK: - 4.3 Implicit Feedback Signals

    enum UserFeedbackSignal {
        case copiedFact         // +0.15
        case longPressedCard    // +0.15
        case includedInCard     // +0.20
        case contextCardCopied  // +0.10 per entity in copied card
        case viewedThreeTimes   // +0.05
        case explicitConfirm    // +0.25
        case explicitDismiss    // -0.40

        var delta: Double {
            switch self {
            case .copiedFact:        return  0.15
            case .longPressedCard:   return  0.15
            case .includedInCard:    return  0.20
            case .contextCardCopied: return  0.10
            case .viewedThreeTimes:  return  0.05
            case .explicitConfirm:   return  0.25
            case .explicitDismiss:   return -0.40
            }
        }
    }

    /// Apply a feedback signal to a single entity's belief score.
    /// Recalculates immediately per Section 4.5.
    @MainActor
    static func applyFeedback(
        signal: UserFeedbackSignal,
        to entity: CanonicalEntity
    ) {
        guard let score = entity.beliefScore else { return }
        score.userFeedbackDelta += signal.delta
        entity.hasBeenInteractedWith = true
        // Activate stability floor if support count >= 3
        if score.supportCount >= 3 {
            score.stabilityFloorActive = true
        }
        score.currentScore = calculateBeliefScore(for: entity, score: score)
        score.lastCalculated = Date()
    }

    // MARK: - 4.5 Recalculation Triggers

    /// Recalculate scores for specific entities (after import completion).
    @MainActor
    static func recalculateAffected(
        entities: [CanonicalEntity]
    ) {
        for entity in entities {
            guard let score = entity.beliefScore else { continue }
            if score.supportCount >= 3 {
                score.stabilityFloorActive = true
            }
            score.currentScore = calculateBeliefScore(for: entity, score: score)
            score.lastCalculated = Date()
        }
    }

    /// Decay-only pass on app open if >24h since last run.
    /// Skips entities where score change < 0.05.
    @MainActor
    static func decayPassIfNeeded(modelContext: ModelContext) throws {
        let lastRunKey = "beliefEngineLastDecayRun"
        let lastRun = UserDefaults.standard.object(forKey: lastRunKey) as? Date ?? .distantPast
        let hoursSince = Date().timeIntervalSince(lastRun) / 3600.0
        guard hoursSince >= 24.0 else { return }

        let descriptor = FetchDescriptor<CanonicalEntity>()
        let entities = try modelContext.fetch(descriptor)

        for entity in entities {
            guard let score = entity.beliefScore else { continue }
            let newScore = calculateBeliefScore(for: entity, score: score)
            let change = abs(newScore - score.currentScore)
            if change >= 0.05 {
                score.currentScore = newScore
                score.lastCalculated = Date()
            }
        }

        try modelContext.save()
        UserDefaults.standard.set(Date(), forKey: lastRunKey)
    }

    // MARK: - 4.4 Visibility Filter

    /// Threshold for new entities that haven't been interacted with yet.
    /// Lower than visibilityThreshold to allow user review before hiding.
    static let newEntityThreshold = 0.1

    /// Returns only entities with belief score at or above the visibility threshold.
    /// New entities (never interacted with) use a lower threshold to allow user review.
    /// Interacted entities use the full 0.45 threshold.
    static func visibleEntities(from entities: [CanonicalEntity]) -> [CanonicalEntity] {
        entities.filter { entity in
            guard let score = entity.beliefScore else { return false }
            let threshold = entity.hasBeenInteractedWith ? visibilityThreshold : newEntityThreshold
            return score.currentScore >= threshold
        }
    }

    /// Returns entities sorted by belief score descending.
    static func sortedByScore(_ entities: [CanonicalEntity]) -> [CanonicalEntity] {
        entities.sorted { a, b in
            (a.beliefScore?.currentScore ?? 0) > (b.beliefScore?.currentScore ?? 0)
        }
    }
}

// MARK: - Belief Feedback Helpers

extension BeliefEngine {

    /// Looks up a CanonicalEntity by matching fact text and applies a feedback signal.
    /// No-op if modelContext is nil, no matching entity found, or entity has no BeliefScore.
    @MainActor
    static func applyFeedbackByText(
        signal: UserFeedbackSignal,
        factText: String,
        modelContext: ModelContext?
    ) {
        guard let context = modelContext else { return }
        let normalised = factText.lowercased().trimmingCharacters(in: .whitespaces)

        let descriptor = FetchDescriptor<CanonicalEntity>()
        guard let entities = try? context.fetch(descriptor) else { return }

        guard let match = entities.first(where: {
            $0.canonicalText.lowercased() == normalised ||
            $0.aliases.contains { $0.lowercased() == normalised }
        }) else { return }

        applyFeedback(signal: signal, to: match)
    }

    /// Applies .contextCardCopied to every visible CanonicalEntity.
    /// Used when user taps an AI app icon to copy+launch.
    @MainActor
    static func applyContextCardCopiedToAll(modelContext: ModelContext?) {
        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<CanonicalEntity>()
        guard let entities = try? context.fetch(descriptor) else { return }

        let visible = visibleEntities(from: entities)
        for entity in visible {
            applyFeedback(signal: .contextCardCopied, to: entity)
        }
    }
}
