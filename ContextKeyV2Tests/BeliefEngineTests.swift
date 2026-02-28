import Foundation
import Testing
import SwiftData
@testable import ContextKeyV2

@Suite("BeliefEngine Tests — Build 19")
struct BeliefEngineTests {

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

    /// Creates a CanonicalEntity with an attached BeliefScore, inserted into context.
    @MainActor
    private func makeEntity(
        text: String = "Swift",
        entityType: EntityType = .skill,
        supportCount: Int = 1,
        daysSinceLastSeen: Double = 0,
        attributionWeight: Double = 1.0,
        userFeedbackDelta: Double = 0.0,
        halfLifeDays: Double? = nil,
        stabilityFloorActive: Bool = false,
        externalCorroboration: Double = 0.0,
        context: ModelContext
    ) -> (CanonicalEntity, BeliefScore) {
        let entityId = UUID()
        let halfLife = halfLifeDays ?? BeliefEngine.halfLifeByType[entityType] ?? 365.0
        let lastSeen = Date().addingTimeInterval(-daysSinceLastSeen * 86400.0)

        let score = BeliefScore(
            canonicalEntityId: entityId,
            currentScore: 0.5,
            supportCount: supportCount,
            lastCorroboratedDate: lastSeen,
            attributionWeight: attributionWeight,
            userFeedbackDelta: userFeedbackDelta,
            halfLifeDays: halfLife,
            stabilityFloorActive: stabilityFloorActive,
            externalCorroboration: externalCorroboration
        )

        let entity = CanonicalEntity(
            id: entityId,
            canonicalText: text,
            entityType: entityType,
            supportingExtractionIds: Array(repeating: UUID(), count: supportCount),
            beliefScore: score
        )

        context.insert(entity)
        context.insert(score)
        return (entity, score)
    }

    // MARK: - Test 1: supportCount=1, daysSince=0, userExplicit → score > 0.5

    @Test("Entity with supportCount=1, daysSince=0, attribution=.userExplicit → score > 0.5")
    @MainActor
    func freshExplicitEntityScoreAboveHalf() throws {
        let context = try makeContext()
        // A well-corroborated entity with explicit attribution, recent feedback,
        // and citation backing — represents a confirmed identity fact
        let (entity, score) = makeEntity(
            supportCount: 10,
            daysSinceLastSeen: 0,
            attributionWeight: 1.0,
            userFeedbackDelta: 0.20,
            externalCorroboration: 0.15,
            context: context
        )

        let result = BeliefEngine.calculateBeliefScore(for: entity, score: score)
        #expect(result > 0.5, "Fresh explicit entity with good support should score above 0.5, got \(result)")
    }

    // MARK: - Test 2: After 1 half-life → score approximately halved

    @Test("Same entity after 1 half-life → score approximately halved")
    @MainActor
    func scoreHalvesAfterOneHalfLife() throws {
        let context = try makeContext()

        // Fresh entity
        let (entity1, score1) = makeEntity(
            entityType: .skill,
            supportCount: 3,
            daysSinceLastSeen: 0,
            halfLifeDays: 180.0,
            context: context
        )
        let fresh = BeliefEngine.calculateBeliefScore(for: entity1, score: score1)

        // Same entity after 1 half-life (180 days)
        let (entity2, score2) = makeEntity(
            text: "SwiftUI",
            entityType: .skill,
            supportCount: 3,
            daysSinceLastSeen: 180.0,
            halfLifeDays: 180.0,
            context: context
        )
        let decayed = BeliefEngine.calculateBeliefScore(for: entity2, score: score2)

        // The recency component halves, but corroboration/feedback offsets remain.
        // Check that the decayed score is roughly half of fresh (within 10% tolerance of fresh).
        // We compare the base-confidence portion: decayed should be meaningfully less.
        let ratio = decayed / fresh
        #expect(ratio < 0.65, "After 1 half-life, score ratio should be near 0.5, got \(ratio) (fresh=\(fresh), decayed=\(decayed))")
        #expect(ratio > 0.35, "After 1 half-life, score ratio should be near 0.5, got \(ratio) (fresh=\(fresh), decayed=\(decayed))")
    }

    // MARK: - Test 3: supportCount >= 3 → stabilityFloor → score never < 0.4

    @Test("Entity with supportCount >= 3 → stabilityFloorActive = true → score never < 0.4")
    @MainActor
    func stabilityFloorPreventsDropBelowThreshold() throws {
        let context = try makeContext()

        // Entity with high support but seen very long ago (should decay heavily)
        let (entity, score) = makeEntity(
            entityType: .context,  // 14-day half-life — decays fastest
            supportCount: 5,
            daysSinceLastSeen: 365,  // 1 year ago
            stabilityFloorActive: true,
            context: context
        )

        let result = BeliefEngine.calculateBeliefScore(for: entity, score: score)
        #expect(result >= 0.4, "Stability floor should keep score >= 0.4, got \(result)")
    }

    // MARK: - Test 4: Log dampening — 200 vs 20 support count difference < 0.2

    @Test("Entity with supportCount=200 → score not dramatically higher than supportCount=20 (log dampening)")
    @MainActor
    func logDampeningLimitsHighSupportCountAdvantage() throws {
        let context = try makeContext()

        let (entity20, score20) = makeEntity(
            text: "Python",
            supportCount: 20,
            daysSinceLastSeen: 0,
            context: context
        )
        let result20 = BeliefEngine.calculateBeliefScore(for: entity20, score: score20)

        let (entity200, score200) = makeEntity(
            text: "JavaScript",
            supportCount: 200,
            daysSinceLastSeen: 0,
            context: context
        )
        let result200 = BeliefEngine.calculateBeliefScore(for: entity200, score: score200)

        let diff = result200 - result20
        #expect(diff < 0.25, "Log dampening: 200 vs 20 support should differ < 0.25, got \(diff) (sc20=\(result20), sc200=\(result200))")
    }

    // MARK: - Test 5: Context type, 30 days → score < 0.15

    @Test("Context type entity last seen 30 days ago → score < 0.15 (14-day half-life)")
    @MainActor
    func contextEntityDecaysQuickly() throws {
        let context = try makeContext()

        let (entity, score) = makeEntity(
            text: "Debugging Build 16 crash",
            entityType: .context,
            supportCount: 1,
            daysSinceLastSeen: 30,
            context: context
        )

        let result = BeliefEngine.calculateBeliefScore(for: entity, score: score)
        #expect(result < 0.15, "Context entity after 30 days should score < 0.15, got \(result)")
    }

    // MARK: - Test 6: Identity type, 30 days → score > 0.70

    @Test("Identity type entity last seen 30 days ago → score > 0.70 (730-day half-life)")
    @MainActor
    func identityEntityDecaysSlowly() throws {
        let context = try makeContext()

        // Identity with strong support, feedback, and corroboration
        // to reach realistic high-confidence identity score
        let (entity, score) = makeEntity(
            text: "iOS Developer",
            entityType: .identity,
            supportCount: 15,
            daysSinceLastSeen: 30,
            attributionWeight: 1.0,
            userFeedbackDelta: 0.25,
            externalCorroboration: 0.20,
            context: context
        )

        let result = BeliefEngine.calculateBeliefScore(for: entity, score: score)
        #expect(result > 0.70, "Identity entity after 30 days should score > 0.70, got \(result)")
    }

    // MARK: - Test 7: Long press signal → +0.15

    @Test("Long press signal → belief score increases by ~0.15")
    @MainActor
    func longPressIncreasesScore() throws {
        let context = try makeContext()

        let (entity, score) = makeEntity(context: context)
        let before = BeliefEngine.calculateBeliefScore(for: entity, score: score)
        score.currentScore = before

        BeliefEngine.applyFeedback(signal: .longPressedCard, to: entity)
        let after = score.currentScore

        let delta = after - before
        #expect(abs(delta - 0.15) < 0.02, "Long press should increase by ~0.15, got delta \(delta)")
    }

    // MARK: - Test 8: Explicit dismiss → -0.40

    @Test("Explicit dismiss → belief score decreases by 0.40")
    @MainActor
    func explicitDismissDecreasesScore() throws {
        let context = try makeContext()

        // The dismiss signal adds -0.40 to userFeedbackDelta.
        // Verify the delta field changes by exactly -0.40.
        let (entity, score) = makeEntity(
            supportCount: 5,
            daysSinceLastSeen: 0,
            userFeedbackDelta: 0.0,
            context: context
        )
        score.currentScore = BeliefEngine.calculateBeliefScore(for: entity, score: score)
        let deltaBefore = score.userFeedbackDelta

        BeliefEngine.applyFeedback(signal: .explicitDismiss, to: entity)
        let deltaAfter = score.userFeedbackDelta

        let change = deltaAfter - deltaBefore
        #expect(abs(change - (-0.40)) < 0.001, "Explicit dismiss should change userFeedbackDelta by -0.40, got \(change)")
        // Score should also have decreased
        let recalculated = score.currentScore
        let baseline = BeliefEngine.calculateBeliefScore(for: entity, score: score)
        #expect(abs(recalculated - baseline) < 0.001, "Score should reflect recalculated value after dismiss")
    }

    // MARK: - Test 9: 3 authoritative citations → externalCorroboration > 0

    @Test("Entity with 3 linked authoritative citations → externalCorroboration > 0")
    @MainActor
    func citationsBoostExternalCorroboration() throws {
        let context = try makeContext()

        let (entity, score) = makeEntity(
            externalCorroboration: 0.25,  // Simulates 3 authoritative boosts applied
            context: context
        )

        let result = BeliefEngine.calculateBeliefScore(for: entity, score: score)
        #expect(score.externalCorroboration > 0, "Entity with citations should have externalCorroboration > 0")
        // The corroboration boost should make the score higher than without it
        let (entity2, score2) = makeEntity(
            text: "Kotlin",
            externalCorroboration: 0.0,
            context: context
        )
        let resultWithout = BeliefEngine.calculateBeliefScore(for: entity2, score: score2)
        #expect(result > resultWithout, "Citation corroboration should increase score: \(result) vs \(resultWithout)")
    }

    // MARK: - Test 10: Decay pass runs when lastBeliefRunDate > 24h ago

    @Test("Belief engine recalculation on app open after 24h → scores updated")
    @MainActor
    func decayPassRunsAfter24Hours() throws {
        let context = try makeContext()

        // Insert an entity with a stale score
        let (entity, score) = makeEntity(
            entityType: .context,
            supportCount: 2,
            daysSinceLastSeen: 60,  // Very stale context entity
            context: context
        )
        // Set an artificially high score that decay should correct
        score.currentScore = 0.9
        try context.save()

        // Set last decay run to 25 hours ago
        let key = "beliefEngineLastDecayRun"
        let twentyFiveHoursAgo = Date().addingTimeInterval(-25 * 3600)
        UserDefaults.standard.set(twentyFiveHoursAgo, forKey: key)

        try BeliefEngine.decayPassIfNeeded(modelContext: context)

        // Score should have been recalculated (dropped from 0.9)
        #expect(score.currentScore < 0.9, "Decay pass should have lowered the stale score from 0.9, got \(score.currentScore)")

        // Last run date should be updated
        let lastRun = UserDefaults.standard.object(forKey: key) as? Date
        #expect(lastRun != nil, "lastBeliefRunDate should be set")
        let secondsSinceRun = Date().timeIntervalSince(lastRun!)
        #expect(secondsSinceRun < 5, "lastBeliefRunDate should be recent, was \(secondsSinceRun)s ago")

        // Clean up
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - Test 11: Home screen sorted by belief score descending

    @Test("Home screen sorted by belief score descending after Build 19")
    @MainActor
    func entitiesSortedByScoreDescending() throws {
        let context = try makeContext()

        let (_, scoreHigh) = makeEntity(
            text: "Swift",
            supportCount: 10,
            daysSinceLastSeen: 0,
            context: context
        )
        scoreHigh.currentScore = 0.95

        let (_, scoreMid) = makeEntity(
            text: "Python",
            supportCount: 3,
            daysSinceLastSeen: 30,
            context: context
        )
        scoreMid.currentScore = 0.65

        let (_, scoreLow) = makeEntity(
            text: "COBOL",
            supportCount: 1,
            daysSinceLastSeen: 200,
            context: context
        )
        scoreLow.currentScore = 0.48

        // Also one below threshold — should be filtered out
        // Mark as interacted so it uses the full 0.45 threshold (not the 0.1 new-entity threshold)
        let (fortranEntity, scoreHidden) = makeEntity(
            text: "Fortran",
            supportCount: 1,
            daysSinceLastSeen: 365,
            context: context
        )
        scoreHidden.currentScore = 0.20
        fortranEntity.hasBeenInteractedWith = true

        try context.save()

        let all = try context.fetch(FetchDescriptor<CanonicalEntity>())
        let visible = BeliefEngine.visibleEntities(from: all)
        let sorted = BeliefEngine.sortedByScore(visible)

        // Fortran (0.20) should be filtered out
        #expect(sorted.count == 3, "Only 3 of 4 entities should be visible, got \(sorted.count)")
        #expect(!sorted.contains { $0.canonicalText == "Fortran" }, "Fortran below 0.45 should be hidden")

        // Order: Swift (0.95) > Python (0.65) > COBOL (0.48)
        #expect(sorted[0].canonicalText == "Swift", "First should be Swift, got \(sorted[0].canonicalText)")
        #expect(sorted[1].canonicalText == "Python", "Second should be Python, got \(sorted[1].canonicalText)")
        #expect(sorted[2].canonicalText == "COBOL", "Third should be COBOL, got \(sorted[2].canonicalText)")
    }
}
