import Foundation
import Testing
@testable import ContextKeyV2

@Suite("V2PostProcessor Tests")
struct V2PostProcessorTests {

    // MARK: - Test 1: Length filter rejects 2-word extraction

    @Test("Length filter rejects a 2-word extraction")
    func rejectsTwoWordExtraction() {
        let twoWords = "Uses Swift"
        #expect(V2PostProcessor.passesLengthFilter(twoWords) == false)
    }

    // MARK: - Test 2: Length filter rejects 16-word extraction

    @Test("Length filter rejects a 16-word extraction")
    func rejectsSixteenWordExtraction() {
        let sixteenWords = "This is a very long extraction that has exactly sixteen words in it to test limits"
        let wordCount = sixteenWords.split(separator: " ", omittingEmptySubsequences: true).count
        #expect(wordCount == 16)
        #expect(V2PostProcessor.passesLengthFilter(sixteenWords) == false)
    }

    // MARK: - Test 3: Entity verification fails when no significant word in source

    @Test("Entity verification fails when no significant word from extraction appears in source chunk")
    func entityVerificationFailsNoMatch() {
        let extraction = "Expert in Kubernetes orchestration"
        let sourceChunk = "I built a SwiftUI app for iOS using CoreML and Vision frameworks."

        // "expert" (6 chars, not stop word) — not in source
        // "kubernetes" (10 chars, not stop word) — not in source
        // "orchestration" (13 chars, not stop word) — not in source
        // "in" — stop word, ignored
        #expect(V2PostProcessor.entityVerified(extraction, sourceChunk: sourceChunk) == false)
    }

    // MARK: - Test 4: Deduplication keeps higher-confidence candidate

    @Test("Deduplication keeps higher-confidence candidate when >70% similar")
    func deduplicationKeepsHigherConfidence() {
        let candidate1 = RawExtractionCandidate(
            text: "Uses SwiftUI for iOS app development",
            entityType: .skill,
            speakerAttribution: .userExplicit,
            confidence: 0.7
        )
        let candidate2 = RawExtractionCandidate(
            text: "Uses SwiftUI for iOS application development",
            entityType: .skill,
            speakerAttribution: .userExplicit,
            confidence: 0.9
        )

        // Verify these are >70% similar
        let sim = V2PostProcessor.characterSimilarity(candidate1.text, candidate2.text)
        #expect(sim > 0.70, "Candidates should be >70% similar, got \(sim)")

        let items: [(candidate: RawExtractionCandidate, chunkId: String, verified: Bool)] = [
            (candidate: candidate1, chunkId: "chunk_0", verified: true),
            (candidate: candidate2, chunkId: "chunk_1", verified: true),
        ]

        let result = V2PostProcessor.deduplicateAcrossChunks(items)

        // Should keep only one — the higher confidence (0.9)
        #expect(result.count == 1)
        #expect(result[0].candidate.confidence == 0.9)
        #expect(result[0].candidate.text == "Uses SwiftUI for iOS application development")
    }
}
