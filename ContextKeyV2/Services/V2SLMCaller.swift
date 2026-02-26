import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - V2 SLM Error

enum SLMError: Error, LocalizedError {
    case modelUnavailable
    case timeout
    case jsonParsingFailed

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "The language model is not available on this device."
        case .timeout:
            return "The language model took too long to respond."
        case .jsonParsingFailed:
            return "Could not parse the model's response."
        }
    }
}

// MARK: - Raw Extraction Candidate

/// A single extraction candidate returned by the SLM before any post-processing.
struct RawExtractionCandidate: Sendable {
    var text: String
    var entityType: EntityType
    var speakerAttribution: AttributionType
    var confidence: Double
}

// MARK: - Language Model Session Protocol (Testability)

/// Abstracts the language model call so V2SLMCaller can be unit tested with mocks.
/// Production implementation wraps Apple's LanguageModelSession.
/// Test implementation returns canned strings.
protocol LanguageModelSessionProtocol: Sendable {
    func respond(to prompt: String) async throws -> String
}

// MARK: - Production Implementation

#if canImport(FoundationModels)
@available(iOS 26.0, *)
struct AppleLanguageModelSession: LanguageModelSessionProtocol {
    func respond(to prompt: String) async throws -> String {
        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        return response.content
    }
}
#endif

// MARK: - V2 SLM Caller (Section 2.3)

/// Standalone caller that sends one chunk + priming topics to the SLM
/// and returns raw extraction candidates. Does NOT apply post-processing.
///
/// Gated by `FeatureFlags.v2EnhancedExtraction`. When the flag is false,
/// `call()` throws `SLMError.modelUnavailable` so the existing pipeline is never disrupted.
struct V2SLMCaller {

    let session: LanguageModelSessionProtocol

    /// Timeout in seconds for a single SLM call.
    static let timeoutSeconds: TimeInterval = 30

    // MARK: - Public API

    /// Call the SLM with a single text chunk and priming topics.
    ///
    /// - Parameters:
    ///   - chunk: Speaker-tagged text chunk from ConversationPreProcessor.
    ///   - primingTopics: Named entities from NLTagger for prompt priming.
    /// - Returns: Array of raw extraction candidates (may be empty).
    /// - Throws: `SLMError.modelUnavailable` if feature flag is off or model unavailable,
    ///           `SLMError.timeout` if response takes >30 seconds.
    func call(chunk: String, primingTopics: [String]) async throws -> [RawExtractionCandidate] {
        // Feature flag gate — existing pipeline is never disrupted
        guard FeatureFlags.v2EnhancedExtraction else {
            throw SLMError.modelUnavailable
        }

        let prompt = buildPrompt(chunk: chunk, primingTopics: primingTopics)

        // First attempt with full structured prompt
        let responseText: String
        do {
            responseText = try await callWithTimeout(prompt: prompt)
        } catch let error as SLMError {
            throw error
        } catch {
            throw SLMError.modelUnavailable
        }

        // Try parsing the response as JSON
        if let candidates = parseJSON(responseText) {
            return candidates
        }

        // Retry with simplified prompt asking for plain list
        let retryPrompt = buildRetryPrompt(chunk: chunk)
        let retryText: String
        do {
            retryText = try await callWithTimeout(prompt: retryPrompt)
        } catch {
            // Retry failed entirely — try manual parse of original response
            return parseManualFallback(responseText)
        }

        // Try parsing retry response as JSON
        if let candidates = parseJSON(retryText) {
            return candidates
        }

        // Last resort: manual parse of retry response
        return parseManualFallback(retryText)
    }

    // MARK: - Prompt Construction

    private func buildPrompt(chunk: String, primingTopics: [String]) -> String {
        let topicsLine: String
        if primingTopics.isEmpty {
            topicsLine = ""
        } else {
            topicsLine = "\nPriming context — entities detected in this conversation: \(primingTopics.joined(separator: ", "))\n"
        }

        return """
        You are an identity extraction engine. Analyze the following conversation text and extract \
        factual statements about the USER (not the assistant). For each fact, classify it.
        \(topicsLine)
        Return a JSON array where each element has these fields:
        - "text": the extracted fact as a concise statement
        - "entityType": one of: skill, tool, project, goal, preference, identity, context, domain
        - "speakerAttribution": one of: userExplicit, userImplied, assistantSuggested, ambiguous
        - "confidence": a number between 0.0 and 1.0

        Rules:
        - Only extract facts about the USER, not the assistant
        - [USER] lines are direct user statements (userExplicit)
        - Facts inferred from user questions or decisions are userImplied
        - Facts stated by [ASSISTANT] that user didn't confirm are assistantSuggested
        - Be specific, not generic. "Uses SwiftUI for iOS development" not "knows programming"
        - Return [] if no user facts are found
        - Return ONLY the JSON array, no other text

        Text to analyze:
        \(chunk)
        """
    }

    private func buildRetryPrompt(chunk: String) -> String {
        return """
        Extract facts about the USER from this text. Return a JSON array.
        Each item: {"text": "...", "entityType": "skill|tool|project|goal|preference|identity|context|domain", \
        "speakerAttribution": "userExplicit|userImplied|assistantSuggested|ambiguous", "confidence": 0.0-1.0}
        Return [] if no facts found. Return ONLY the JSON array.

        Text:
        \(chunk)
        """
    }

    // MARK: - Timeout Wrapper

    private func callWithTimeout(prompt: String) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await self.session.respond(to: prompt)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(Self.timeoutSeconds))
                throw SLMError.timeout
            }

            // First task to complete wins
            guard let result = try await group.next() else {
                throw SLMError.timeout
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - JSON Parsing

    /// Attempt to parse response as a JSON array of extraction candidates.
    private func parseJSON(_ text: String) -> [RawExtractionCandidate]? {
        // Find the JSON array in the response (model might include extra text)
        guard let arrayStart = text.firstIndex(of: "["),
              let arrayEnd = text.lastIndex(of: "]") else {
            return nil
        }

        let jsonSubstring = String(text[arrayStart...arrayEnd])
        guard let data = jsonSubstring.data(using: .utf8) else {
            return nil
        }

        struct CandidateJSON: Decodable {
            var text: String
            var entityType: String
            var speakerAttribution: String?
            var confidence: Double?
        }

        guard let items = try? JSONDecoder().decode([CandidateJSON].self, from: data) else {
            return nil
        }

        // Empty array is valid — not a parsing failure
        if items.isEmpty { return [] }

        return items.compactMap { item -> RawExtractionCandidate? in
            guard let entityType = EntityType(rawValue: item.entityType),
                  !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            let attribution = item.speakerAttribution.flatMap { AttributionType(rawValue: $0) } ?? .ambiguous

            return RawExtractionCandidate(
                text: item.text,
                entityType: entityType,
                speakerAttribution: attribution,
                confidence: item.confidence ?? 0.5
            )
        }
    }

    /// Last-resort line-by-line parsing when JSON fails entirely.
    /// Looks for lines that look like facts and returns them with minimal classification.
    private func parseManualFallback(_ text: String) -> [RawExtractionCandidate] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count >= 5 }
            // Skip lines that look like JSON syntax or instructions
            .filter { !$0.hasPrefix("{") && !$0.hasPrefix("}") && !$0.hasPrefix("[") && !$0.hasPrefix("]") }

        // If nothing useful found, return empty (not an error)
        guard !lines.isEmpty else { return [] }

        return lines.prefix(20).map { line in
            // Strip common list prefixes
            var cleaned = line
            if cleaned.hasPrefix("- ") { cleaned = String(cleaned.dropFirst(2)) }
            if cleaned.hasPrefix("• ") { cleaned = String(cleaned.dropFirst(2)) }
            if let dotRange = cleaned.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                cleaned = String(cleaned[dotRange.upperBound...])
            }

            return RawExtractionCandidate(
                text: cleaned,
                entityType: .context, // Default — post-processing will reclassify
                speakerAttribution: .ambiguous,
                confidence: 0.3
            )
        }
    }
}
