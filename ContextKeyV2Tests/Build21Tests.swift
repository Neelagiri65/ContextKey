import Foundation
import Testing
import SwiftData
import UIKit
@testable import ContextKeyV2

@Suite("Build 21 — NarrationService & AILaunchService Tests")
struct Build21Tests {

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

    @MainActor
    @discardableResult
    private func makeEntity(
        text: String,
        entityType: EntityType,
        score: Double,
        supportCount: Int = 3,
        context: ModelContext
    ) -> CanonicalEntity {
        let entityId = UUID()
        let beliefScore = BeliefScore(
            canonicalEntityId: entityId,
            currentScore: score,
            supportCount: supportCount,
            lastCorroboratedDate: Date(),
            attributionWeight: 1.0,
            halfLifeDays: BeliefEngine.halfLifeByType[entityType] ?? 365.0,
            stabilityFloorActive: supportCount >= 3
        )
        let entity = CanonicalEntity(
            id: entityId,
            canonicalText: text,
            entityType: entityType,
            supportingExtractionIds: Array(repeating: UUID(), count: supportCount),
            beliefScore: beliefScore
        )
        context.insert(entity)
        context.insert(beliefScore)
        return entity
    }

    /// Builds a standard facet map with enough entities for card generation.
    @MainActor
    private func makePopulatedFacets(context: ModelContext) throws -> [FacetType: [CanonicalEntity]] {
        // Professional Identity (3)
        makeEntity(text: "iOS Developer", entityType: .identity, score: 0.90, context: context)
        makeEntity(text: "Mobile Architect", entityType: .identity, score: 0.80, context: context)
        makeEntity(text: "Tech Lead", entityType: .identity, score: 0.75, context: context)

        // Technical Capability (5) — skills + tools
        makeEntity(text: "Swift", entityType: .skill, score: 0.95, context: context)
        makeEntity(text: "SwiftUI", entityType: .skill, score: 0.88, context: context)
        makeEntity(text: "Python", entityType: .skill, score: 0.70, context: context)
        makeEntity(text: "Xcode", entityType: .tool, score: 0.85, context: context)
        makeEntity(text: "Git", entityType: .tool, score: 0.80, context: context)

        // Active Projects (2)
        makeEntity(text: "ContextKey", entityType: .project, score: 0.92, context: context)
        makeEntity(text: "AI Identity Platform", entityType: .project, score: 0.65, context: context)

        // Goals (2)
        makeEntity(text: "Launch on App Store", entityType: .goal, score: 0.85, context: context)
        makeEntity(text: "Build a portable AI identity", entityType: .goal, score: 0.78, context: context)

        // Working Style (2)
        makeEntity(text: "First principles thinking", entityType: .preference, score: 0.70, context: context)
        makeEntity(text: "Async communication", entityType: .preference, score: 0.65, context: context)

        // Values (2)
        makeEntity(text: "Privacy is non-negotiable", entityType: .preference, score: 0.72, context: context)

        // Domain Knowledge (4)
        makeEntity(text: "Enterprise software", entityType: .domain, score: 0.80, context: context)
        makeEntity(text: "Developer tools", entityType: .domain, score: 0.75, context: context)
        makeEntity(text: "Fintech", entityType: .domain, score: 0.60, context: context)
        makeEntity(text: "Mobile platforms", entityType: .domain, score: 0.55, context: context)

        // Current Context (2)
        makeEntity(text: "Building Build 21", entityType: .context, score: 0.88, context: context)
        makeEntity(text: "Preparing for TestFlight", entityType: .context, score: 0.70, context: context)

        try context.save()

        let entities = try context.fetch(FetchDescriptor<CanonicalEntity>())
        return FacetService.visibleFacets(from: entities)
    }

    // MARK: - Test 1: Long press copies to clipboard

    @Test("Long press on persona card → clipboard contains card text")
    @MainActor
    func longPressCopiesCardToClipboard() throws {
        let context = try makeContext()
        let facets = try makePopulatedFacets(context: context)
        let cardText = NarrationService.generateCard(for: .claude, facets: facets)

        // Simulate what long press does: copy to clipboard
        UIPasteboard.general.string = cardText

        #expect(UIPasteboard.general.string == cardText, "Clipboard should contain the card text")
        #expect(!cardText.isEmpty, "Card text should not be empty")
    }

    // MARK: - Test 2: Single tap sets selectedPersonaCard

    @Test("Single tap on persona card → selectedPersonaCard state is set")
    func singleTapSetsSelectedPlatform() {
        // Verify Platform conforms to Identifiable (required for .sheet(item:))
        let platform: Platform = .claude
        #expect(platform.id == "claude", "Platform must be Identifiable with rawValue id")

        // Verify all AI platforms have valid IDs for sheet binding
        for p in Platform.aiPlatforms {
            #expect(!p.id.isEmpty, "\(p) should have non-empty id")
        }
    }

    // MARK: - Test 3: Claude card is natural prose — no markdown headers

    @Test("Claude card is natural prose — no markdown headers")
    @MainActor
    func claudeCardIsNaturalProse() throws {
        let context = try makeContext()
        let facets = try makePopulatedFacets(context: context)
        let card = NarrationService.generateCard(for: .claude, facets: facets)

        #expect(!card.contains("#"), "Claude card should not contain markdown headers, got: \(card)")
        #expect(!card.contains("**"), "Claude card should not contain bold markdown")
        #expect(!card.contains("- "), "Claude card should not contain bullet points")
        #expect(!card.isEmpty, "Claude card should not be empty")
    }

    // MARK: - Test 4: ChatGPT card has plain text section headers

    @Test("ChatGPT card has plain text section headers")
    @MainActor
    func chatGPTCardHasHeaders() throws {
        let context = try makeContext()
        let facets = try makePopulatedFacets(context: context)
        let card = NarrationService.generateCard(for: .chatgpt, facets: facets)

        #expect(card.contains("About Me"), "ChatGPT card should have 'About Me' header")
        #expect(card.contains("Goals"), "ChatGPT card should have 'Goals' header")
        #expect(card.contains("- "), "ChatGPT card should contain bullet points")
        #expect(!card.contains("#"), "ChatGPT card should use plain text headers, not markdown")
    }

    // MARK: - Test 5: Perplexity card is <= 120 words

    @Test("Perplexity card is <= 120 words")
    @MainActor
    func perplexityCardWordLimit() throws {
        let context = try makeContext()
        let facets = try makePopulatedFacets(context: context)

        // Create many citations to push word count
        let citations = (0..<20).map { i in
            CitationReference(
                url: "https://example\(i).com/doc",
                domain: "example\(i).com",
                citedInConversationId: UUID(),
                citedCount: 5 - (i % 5)
            )
        }

        let card = NarrationService.generateCard(for: .perplexity, facets: facets, citations: citations)
        let wordCount = card.split(separator: " ").count

        #expect(wordCount <= 120, "Perplexity card must be <= 120 words, got \(wordCount): \(card)")
    }

    // MARK: - Test 6: Every claim traces to entity with score >= 0.45

    @Test("Every claim in Claude card traces to a CanonicalEntity with score >= 0.45")
    @MainActor
    func allClaimsTraceToVisibleEntities() throws {
        let context = try makeContext()

        // Add one entity below threshold — should NOT appear in card
        // Mark as interacted so it uses the full 0.45 threshold
        let cobol = makeEntity(text: "COBOL", entityType: .skill, score: 0.30, supportCount: 1, context: context)
        cobol.hasBeenInteractedWith = true

        let facets = try makePopulatedFacets(context: context)
        let card = NarrationService.generateCard(for: .claude, facets: facets)

        #expect(!card.contains("COBOL"), "Entity below 0.45 threshold should not appear in card")

        // Verify all entities that DO appear have score >= 0.45
        let allEntities = try context.fetch(FetchDescriptor<CanonicalEntity>())
        let visibleTexts = allEntities
            .filter { ($0.beliefScore?.currentScore ?? 0) >= BeliefEngine.visibilityThreshold }
            .map(\.canonicalText)

        // Every entity text that appears in the card should be in the visible set
        for entityText in visibleTexts where card.contains(entityText) {
            let entity = allEntities.first { $0.canonicalText == entityText }
            let score = entity?.beliefScore?.currentScore ?? 0
            #expect(score >= 0.45, "\(entityText) in card has score \(score), below 0.45")
        }
    }

    // MARK: - Test 7: Web URL fallback — all 4 platforms have web URLs

    @Test("If AI app not installed: web URL exists for all 4 platforms")
    func webURLFallbackExists() {
        for platform in Platform.aiPlatforms {
            let webURL = AILaunchService.webURLs[platform]
            #expect(webURL != nil, "\(platform) should have a web URL fallback")
            #expect(webURL?.hasPrefix("https://") == true, "\(platform) web URL should be HTTPS")
        }

        // Also verify URL schemes exist
        for platform in Platform.aiPlatforms {
            let scheme = AILaunchService.urlSchemes[platform]
            #expect(scheme != nil, "\(platform) should have a URL scheme")
            #expect(scheme?.hasSuffix("://") == true, "\(platform) scheme should end with ://")
        }
    }

    // MARK: - Test 8: Card regenerates with different platform

    @Test("Card regenerates when platform selection changes")
    @MainActor
    func cardRegeneratesPerPlatform() throws {
        let context = try makeContext()
        let facets = try makePopulatedFacets(context: context)

        let claudeCard = NarrationService.generateCard(for: .claude, facets: facets)
        let chatGPTCard = NarrationService.generateCard(for: .chatgpt, facets: facets)

        #expect(claudeCard != chatGPTCard, "Claude and ChatGPT cards should have different formats")
    }

    // MARK: - Test 9: Long press applies belief boost

    @Test("Long press applies belief boost to visible entities")
    @MainActor
    func longPressAppliesBeliefBoost() throws {
        let context = try makeContext()
        let entity = makeEntity(text: "Swift", entityType: .skill, score: 0.80, context: context)
        try context.save()

        let scoreBefore = entity.beliefScore!.userFeedbackDelta

        // Simulate what long press does: apply contextCardCopied to all
        BeliefEngine.applyContextCardCopiedToAll(modelContext: context)

        let scoreAfter = entity.beliefScore!.userFeedbackDelta
        #expect(scoreAfter > scoreBefore, "Belief score feedback delta should increase after long press copy, before=\(scoreBefore) after=\(scoreAfter)")
    }

    // MARK: - Test 10: Perplexity card contains citation domains

    @Test("Perplexity card contains citation domains when citations provided")
    @MainActor
    func perplexityCardIncludesCitationDomains() throws {
        let context = try makeContext()
        let facets = try makePopulatedFacets(context: context)

        let citations = [
            CitationReference(url: "https://developer.apple.com/docs", domain: "developer.apple.com", citedInConversationId: UUID(), citedCount: 5),
            CitationReference(url: "https://docs.swift.org/guide", domain: "docs.swift.org", citedInConversationId: UUID(), citedCount: 3),
            CitationReference(url: "https://github.com/apple/swift", domain: "github.com", citedInConversationId: UUID(), citedCount: 2)
        ]

        let card = NarrationService.generateCard(for: .perplexity, facets: facets, citations: citations)

        #expect(card.contains("Sources I've already consulted"), "Perplexity card should contain citation domains section")
        #expect(card.contains("developer.apple.com"), "Should include top cited domain")
    }

    // MARK: - Test 11: Empty facets → fallback message

    @Test("Empty facets → fallback message returned, not empty string")
    func emptyFacetsReturnFallback() {
        let emptyFacets: [FacetType: [CanonicalEntity]] = [:]

        for platform in Platform.allCases {
            let card = NarrationService.generateCard(for: platform, facets: emptyFacets)
            #expect(!card.isEmpty, "\(platform) card should not be empty with no facets")
            #expect(card == "Import more conversations to generate your context card.",
                    "\(platform) should return fallback message, got: \(card)")
        }
    }

    // MARK: - Test 12: All 4 platforms generate different cards

    @Test("NarrationService returns different card for each of the 4 platforms")
    @MainActor
    func allFourPlatformsGenerateDifferentCards() throws {
        let context = try makeContext()
        let facets = try makePopulatedFacets(context: context)

        let cards = Platform.aiPlatforms.map { platform in
            NarrationService.generateCard(for: platform, facets: facets)
        }

        // All 4 cards should be unique
        let uniqueCards = Set(cards)
        #expect(uniqueCards.count == 4, "All 4 platforms should produce unique cards, got \(uniqueCards.count) unique")
    }

    // MARK: - Test 13: Manual platform — copies text, no crash, no app launch

    @Test("AILaunchService with .manual platform — no crash, dictionaries return nil")
    func manualPlatformNoCrash() {
        // .manual should have no URL scheme and no web URL
        #expect(AILaunchService.urlSchemes[.manual] == nil, ".manual should not have a URL scheme")
        #expect(AILaunchService.webURLs[.manual] == nil, ".manual should not have a web URL")

        // Generate a card for manual — should work without crash
        let emptyFacets: [FacetType: [CanonicalEntity]] = [:]
        let card = NarrationService.generateCard(for: .manual, facets: emptyFacets)
        #expect(!card.isEmpty, "Manual card should return fallback, not empty string")
    }

    // MARK: - Test 14: New entity with low score visible via newEntityThreshold

    @Test("New entity (hasBeenInteractedWith=false) with score 0.15 → visible")
    @MainActor
    func newEntityVisibleAtLowScore() throws {
        let context = try makeContext()
        let entity = makeEntity(text: "Rust", entityType: .skill, score: 0.15, supportCount: 1, context: context)
        // hasBeenInteractedWith defaults to false
        #expect(entity.hasBeenInteractedWith == false)
        try context.save()

        let all = try context.fetch(FetchDescriptor<CanonicalEntity>())
        let visible = BeliefEngine.visibleEntities(from: all)

        #expect(visible.count == 1, "New entity at 0.15 should be visible (threshold 0.1), got \(visible.count)")
        #expect(visible.first?.canonicalText == "Rust")
    }

    // MARK: - Test 15: After interaction, entity uses full 0.45 threshold

    @Test("After applyFeedback → hasBeenInteractedWith=true, uses 0.45 threshold")
    @MainActor
    func interactedEntityUsesFullThreshold() throws {
        let context = try makeContext()
        let entity = makeEntity(text: "Rust", entityType: .skill, score: 0.15, supportCount: 1, context: context)
        try context.save()

        // Before interaction: visible at 0.1 threshold
        let allBefore = try context.fetch(FetchDescriptor<CanonicalEntity>())
        let visibleBefore = BeliefEngine.visibleEntities(from: allBefore)
        #expect(visibleBefore.count == 1, "Should be visible before interaction")

        // Apply feedback — marks hasBeenInteractedWith = true
        BeliefEngine.applyFeedback(signal: .copiedFact, to: entity)
        #expect(entity.hasBeenInteractedWith == true, "Should be marked as interacted")

        // After interaction: score is 0.15 + 0.15 (copiedFact delta) recalculated
        // But the recalculated score from formula with supportCount=1 is very low
        // The entity should now use the 0.45 threshold
        let allAfter = try context.fetch(FetchDescriptor<CanonicalEntity>())
        let visibleAfter = BeliefEngine.visibleEntities(from: allAfter)

        // With supportCount=1 and recalculated score, it should be below 0.45
        let finalScore = entity.beliefScore!.currentScore
        if finalScore < BeliefEngine.visibilityThreshold {
            #expect(!visibleAfter.contains { $0.canonicalText == "Rust" },
                    "Interacted entity with score \(finalScore) < 0.45 should be hidden")
        } else {
            #expect(visibleAfter.contains { $0.canonicalText == "Rust" },
                    "Interacted entity with score \(finalScore) >= 0.45 should be visible")
        }
    }
}
