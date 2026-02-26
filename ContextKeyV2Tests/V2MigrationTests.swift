import Foundation
import Testing
import SwiftData
@testable import ContextKeyV2

@Suite("V2 Migration Tests")
struct V2MigrationTests {

    /// Verifies that runV2Migration is guarded by the UserDefaults flag
    /// and will not run a second time once hasRunV2Migration is true.
    @Test("Migration guard prevents duplicate run")
    func migrationGuardPreventsDuplicateRun() throws {
        // Reset the flag so migration is allowed to run
        UserDefaults.standard.removeObject(forKey: "hasRunV2Migration")

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

        // Confirm the flag was set
        #expect(UserDefaults.standard.bool(forKey: "hasRunV2Migration") == true)

        // Second migration — guard should prevent it
        try runV2Migration(existingFacts: [fact2], modelContext: context)

        // Verify still only one CanonicalEntity (second call was blocked)
        let fetchAfterSecond = FetchDescriptor<CanonicalEntity>()
        let entitiesAfterSecond = try context.fetch(fetchAfterSecond)
        #expect(entitiesAfterSecond.count == 1)

        // Cleanup: remove the flag so other tests aren't affected
        UserDefaults.standard.removeObject(forKey: "hasRunV2Migration")
    }
}
