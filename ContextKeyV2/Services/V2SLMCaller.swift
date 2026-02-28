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
    var entityType: EntityType?   // nil = unclassified, ReconciliationService will classify
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

        let prompt = buildPrompt(chunk: chunk)

        let responseText: String
        do {
            responseText = try await callWithTimeout(prompt: prompt)
        } catch let error as SLMError {
            throw error
        } catch {
            throw SLMError.modelUnavailable
        }

        return parsePlainTextLines(responseText)
    }

    // MARK: - Prompt Construction

    private func buildPrompt(chunk: String) -> String {
        return """
        You are extracting facts about a person from their own messages.

        Rules:
        - Only extract facts that directly describe the person who wrote these messages
        - A fact can be a role, skill, project, goal, preference, constraint, experience, or value
        - Each fact must be a complete standalone statement
        - Do not infer — only extract what is explicitly stated
        - Do not extract facts about other people, tools, or the world in general
        - Return one fact per line, nothing else

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

    // MARK: - Plain Text Parsing

    /// Parse plain text response: one fact per line.
    /// Each line becomes an unclassified RawExtractionCandidate.
    /// entityType is nil — classification happens in ReconciliationService.
    func parsePlainTextLines(_ text: String) -> [RawExtractionCandidate] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count >= 5 }
            .filter { !$0.hasPrefix("{") && !$0.hasPrefix("[") }
            .prefix(20)
            .map { line in
                var cleaned = line
                if cleaned.hasPrefix("- ") { cleaned = String(cleaned.dropFirst(2)) }
                if cleaned.hasPrefix("• ") { cleaned = String(cleaned.dropFirst(2)) }
                if let dotRange = cleaned.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                    cleaned = String(cleaned[dotRange.upperBound...])
                }

                return RawExtractionCandidate(
                    text: cleaned,
                    entityType: nil,
                    speakerAttribution: .userExplicit,
                    confidence: 0.5
                )
            }
    }
}
