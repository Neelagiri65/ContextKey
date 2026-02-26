import Foundation

// MARK: - V2 Post-Processor (Section 2.4)

/// Filters, verifies, deduplicates, and converts RawExtractionCandidates
/// into RawExtraction SwiftData models. Does NOT persist — caller inserts into ModelContext.
enum V2PostProcessor {

    // MARK: - Constants

    static let minWords = 3
    static let maxWords = 15
    static let similarityThreshold = 0.70

    static let stopWords: Set<String> = [
        "is", "a", "an", "the", "and", "or", "but",
        "in", "on", "at", "to", "for", "of", "with",
        "my", "i", "am", "are", "was", "be"
    ]

    // MARK: - Public API

    /// Run the full post-processing pipeline on candidates from a single conversation.
    ///
    /// - Parameters:
    ///   - candidates: Raw candidates from V2SLMCaller, grouped by chunk.
    ///     Each element is (chunkId, chunkText, candidates for that chunk).
    ///   - sourceConversationId: UUID of the ImportedConversation.
    ///   - conversationTimestamp: Estimated date of the conversation.
    /// - Returns: Array of RawExtraction models ready for ModelContext insertion.
    static func process(
        chunks: [(chunkId: String, chunkText: String, candidates: [RawExtractionCandidate])],
        sourceConversationId: UUID,
        conversationTimestamp: Date
    ) -> [RawExtraction] {
        // Steps A + B per chunk
        var allProcessed: [(candidate: RawExtractionCandidate, chunkId: String, verified: Bool)] = []

        for (chunkId, chunkText, candidates) in chunks {
            for candidate in candidates {
                // Step A: Length filter
                guard passesLengthFilter(candidate.text) else { continue }

                // Step B: Entity verification
                let verified = entityVerified(candidate.text, sourceChunk: chunkText)
                var adjusted = candidate
                if !verified {
                    adjusted.confidence = min(adjusted.confidence, 0.1)
                }

                allProcessed.append((candidate: adjusted, chunkId: chunkId, verified: verified))
            }
        }

        // Step C: Chunk deduplication across all candidates
        let deduplicated = deduplicateAcrossChunks(allProcessed)

        // Step D: Convert to RawExtraction models
        return deduplicated.map { item in
            RawExtraction(
                text: item.candidate.text,
                entityType: item.candidate.entityType,
                sourceConversationId: sourceConversationId,
                sourceChunkId: item.chunkId,
                extractionTimestamp: Date(),
                conversationTimestamp: conversationTimestamp,
                speakerAttribution: item.candidate.speakerAttribution,
                rawConfidence: item.candidate.confidence,
                entityVerified: item.verified,
                isActive: true
            )
        }
    }

    // MARK: - Step A: Length Filter

    /// Returns true if the extraction text has between minWords and maxWords (inclusive).
    static func passesLengthFilter(_ text: String) -> Bool {
        let wordCount = text.split(separator: " ", omittingEmptySubsequences: true).count
        return wordCount >= minWords && wordCount <= maxWords
    }

    // MARK: - Step B: Entity Verification

    /// Checks that at least one significant word from the extraction appears in the source chunk.
    /// Significant = length > 3 and not a stop word.
    static func entityVerified(_ extractionText: String, sourceChunk: String) -> Bool {
        let words = extractionText.lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { String($0) }

        let significantWords = words.filter { word in
            word.count > 3 && !stopWords.contains(word)
        }

        // If no significant words exist, cannot verify
        guard !significantWords.isEmpty else { return false }

        let chunkLower = sourceChunk.lowercased()
        return significantWords.contains { chunkLower.contains($0) }
    }

    // MARK: - Step C: Chunk Deduplication

    /// Deduplicate candidates across overlapping chunks.
    /// Two candidates are duplicates if character similarity > 70%.
    /// Keeps the one with higher confidence, marks the other inactive.
    static func deduplicateAcrossChunks(
        _ items: [(candidate: RawExtractionCandidate, chunkId: String, verified: Bool)]
    ) -> [(candidate: RawExtractionCandidate, chunkId: String, verified: Bool)] {
        guard items.count > 1 else { return items }

        var active = Array(repeating: true, count: items.count)

        for i in 0..<items.count {
            guard active[i] else { continue }
            for j in (i + 1)..<items.count {
                guard active[j] else { continue }

                let sim = characterSimilarity(items[i].candidate.text, items[j].candidate.text)
                if sim > similarityThreshold {
                    // Keep higher confidence, deactivate the other
                    if items[i].candidate.confidence >= items[j].candidate.confidence {
                        active[j] = false
                    } else {
                        active[i] = false
                        break // i is deactivated, no need to compare further
                    }
                }
            }
        }

        return items.enumerated().compactMap { index, item in
            active[index] ? item : nil
        }
    }

    /// Character-level similarity: 1.0 - (editDistance / longerLength).
    static func characterSimilarity(_ a: String, _ b: String) -> Double {
        let aLower = a.lowercased()
        let bLower = b.lowercased()
        let longerCount = max(aLower.count, bLower.count)
        guard longerCount > 0 else { return 1.0 }

        let distance = editDistance(Array(aLower), Array(bLower))
        return Double(longerCount - distance) / Double(longerCount)
    }

    /// Standard Levenshtein edit distance.
    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        let m = a.count
        let n = b.count

        // Optimize: if one is empty, distance is the other's length
        if m == 0 { return n }
        if n == 0 { return m }

        // Use two rows instead of full matrix for space efficiency
        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    curr[j] = prev[j - 1]
                } else {
                    curr[j] = 1 + min(prev[j], curr[j - 1], prev[j - 1])
                }
            }
            prev = curr
        }

        return prev[n]
    }

    // MARK: - Step E: Citation Extraction (Stub — Build 18)

    /// Detect URLs in chunk text and create CitationReference objects
    /// linking them to nearby entities. Full implementation in Build 18.
    ///
    /// - Parameters:
    ///   - chunk: The raw chunk text to scan for URLs.
    ///   - nearEntities: Extraction candidates from this chunk for proximity matching.
    /// - Returns: Array of CitationReference objects (currently empty — stub).
    static func extractCitations(
        from chunk: String,
        nearEntities: [RawExtractionCandidate]
    ) -> [CitationReference] {
        // Detect https:// URLs in the chunk
        let pattern = #"https?://[^\s\)\]\>\"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsChunk = chunk as NSString
        let matches = regex.matches(in: chunk, options: [], range: NSRange(location: 0, length: nsChunk.length))

        // URLs detected — full proximity matching and CitationReference
        // creation will be implemented in Build 18.
        _ = matches.map { nsChunk.substring(with: $0.range) }

        return []
    }
}
