import Foundation
import Testing
@testable import ContextKeyV2

@Suite("ConversationPreProcessor Tests")
struct ConversationPreProcessorTests {

    // MARK: - Test 1: ChatGPT Speaker Tagging

    @Test("Speaker tagging correctly tags a ChatGPT-format conversation")
    func chatGPTSpeakerTagging() {
        let input = """
        You said:
        I'm an iOS developer working on a SwiftUI app called ContextKey.

        ChatGPT said:
        That sounds interesting! What kind of app is ContextKey?

        You said:
        It's a portable AI identity app that stores your context on-device.

        ChatGPT said:
        Great concept. Are you using Core Data or SwiftData for persistence?
        """

        let result = ConversationPreProcessor.process(input)

        // Platform should be detected as ChatGPT
        #expect(result.detectedPlatform == .chatgpt)

        // Tagged text should contain [USER] and [ASSISTANT] markers
        #expect(result.taggedText.contains("[USER]"))
        #expect(result.taggedText.contains("[ASSISTANT]"))

        // Should NOT contain original markers
        #expect(!result.taggedText.contains("You said:"))
        #expect(!result.taggedText.contains("ChatGPT said:"))

        // Verify user content is present
        #expect(result.taggedText.contains("iOS developer"))
        #expect(result.taggedText.contains("portable AI identity"))

        // Verify assistant content is present
        #expect(result.taggedText.contains("That sounds interesting"))
        #expect(result.taggedText.contains("Core Data or SwiftData"))
    }

    // MARK: - Test 2: Overlapping Chunks

    @Test("createOverlappingChunks produces correct overlap on 20000-char input with 2000-char overlap")
    func overlappingChunks() {
        // Create a 20000-character input by repeating a known pattern
        let unit = "ABCDEFGHIJ" // 10 chars
        let input = String(repeating: unit, count: 2000) // 20000 chars
        #expect(input.count == 20000)

        let chunkSize = 8000
        let overlapSize = 2000
        let chunks = ConversationPreProcessor.createOverlappingChunks(
            input, chunkSize: chunkSize, overlapSize: overlapSize
        )

        // With 20000 chars, chunkSize=8000, overlap=2000, stride=6000:
        // Chunk 0: chars 0..<8000
        // Chunk 1: chars 6000..<14000
        // Chunk 2: chars 12000..<20000
        #expect(chunks.count == 3)

        // Each chunk should be exactly chunkSize (input divides evenly)
        #expect(chunks[0].count == 8000)
        #expect(chunks[1].count == 8000)
        #expect(chunks[2].count == 8000)

        // Verify overlap: last 2000 chars of chunk 0 == first 2000 chars of chunk 1
        let chunk0Tail = String(chunks[0].suffix(overlapSize))
        let chunk1Head = String(chunks[1].prefix(overlapSize))
        #expect(chunk0Tail == chunk1Head)

        // Verify overlap: last 2000 chars of chunk 1 == first 2000 chars of chunk 2
        let chunk1Tail = String(chunks[1].suffix(overlapSize))
        let chunk2Head = String(chunks[2].prefix(overlapSize))
        #expect(chunk1Tail == chunk2Head)
    }

    // MARK: - Test 3: NLTagger Priming

    @Test("NLTagger priming extracts at least one named entity from a real sentence")
    func nlTaggerPriming() {
        let input = """
        I work at Apple in Cupertino. My manager is John Smith \
        and we're building features for the iPhone using Swift.
        """

        let topics = ConversationPreProcessor.extractPrimingTopics(input)

        // NLTagger should find at least one named entity from this text.
        // Common entities: "Apple", "Cupertino", "John Smith", "iPhone"
        #expect(!topics.isEmpty, "NLTagger should extract at least one named entity")

        // Verify the results are strings of reasonable length (not noise)
        for topic in topics {
            #expect(topic.count >= 2, "Each topic should be at least 2 characters")
        }
    }
}
