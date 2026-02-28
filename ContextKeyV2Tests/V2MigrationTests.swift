import Foundation
import Testing
import SwiftData
@testable import ContextKeyV2

@Suite("V2 Migration Tests")
struct V2MigrationTests {

    /// Verifies that runV2Migration is guarded by the UserDefaults version
    /// and will not run a second time once v2MigrationVersion matches.
    @Test("Migration guard prevents duplicate run")
    func migrationGuardPreventsDuplicateRun() throws {
        // Reset the version so migration is allowed to run
        UserDefaults.standard.removeObject(forKey: "v2MigrationVersion")

        // Create in-memory SwiftData container
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: RawExtraction.self, CanonicalEntity.self, BeliefScore.self,
            configurations: config
        )
        let context = ModelContext(container)

        // Two mock facts with different content and pillars
        let fact1 = ContextFact(
            content: "Knows Swift and SwiftUI",
            layer: .coreIdentity,
            pillar: .skillsAndStack,
            confidence: 0.8,
            frequency: 3
        )
        let fact2 = ContextFact(
            content: "Prefers async communication",
            layer: .currentContext,
            pillar: .communicationStyle,
            confidence: 0.7,
            frequency: 1
        )

        // First migration — should succeed and insert entities
        try runV2Migration(existingFacts: [fact1], modelContext: context)

        // Verify one CanonicalEntity was created
        let fetchAfterFirst = FetchDescriptor<CanonicalEntity>()
        let entitiesAfterFirst = try context.fetch(fetchAfterFirst)
        #expect(entitiesAfterFirst.count == 1)
        #expect(entitiesAfterFirst.first?.canonicalText == "Knows Swift and SwiftUI")

        // Confirm the version was stored
        #expect(UserDefaults.standard.integer(forKey: "v2MigrationVersion") == v2MigrationVersion)

        // Second migration — guard should prevent it
        try runV2Migration(existingFacts: [fact2], modelContext: context)

        // Verify still only one CanonicalEntity (second call was blocked)
        let fetchAfterSecond = FetchDescriptor<CanonicalEntity>()
        let entitiesAfterSecond = try context.fetch(fetchAfterSecond)
        #expect(entitiesAfterSecond.count == 1)

        // Verify migrated entity has recalculated score (not hardcoded 0.5)
        let entity = entitiesAfterFirst.first!
        let score = entity.beliefScore!
        #expect(score.supportCount >= 3, "supportCount should be at least 3, got \(score.supportCount)")
        #expect(score.userFeedbackDelta == 0.3, "userFeedbackDelta should be 0.3, got \(score.userFeedbackDelta)")
        #expect(score.currentScore != 0.5, "currentScore should be recalculated, not hardcoded 0.5")
        #expect(entity.hasBeenInteractedWith == false, "Migrated entities should not be marked as interacted")

        // Cleanup: remove the version so other tests aren't affected
        UserDefaults.standard.removeObject(forKey: "v2MigrationVersion")
    }
}
