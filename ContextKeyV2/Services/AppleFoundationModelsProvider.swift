import Foundation
#if canImport(FoundationModels)
import FoundationModels

// MARK: - Apple Foundation Models Provider (iOS 26+)

/// Uses Apple's built-in on-device language model via FoundationModels framework.
/// Zero app size cost — the model is pre-installed on the device.
@available(iOS 26.0, *)
final class AppleFoundationModelsProvider: SLMProvider, @unchecked Sendable {
    let displayName = "Apple Intelligence"
    let isAvailable = true

    func extract(from text: String, prompt: String) async throws -> ExtractedFactsRaw {
        let session = LanguageModelSession()
        let response = try await session.respond(
            to: prompt + "\n\n" + text,
            generating: ExtractedFacts.self
        )
        let extracted = response.content

        return ExtractedFactsRaw(
            persona: extracted.persona,
            skillsAndStack: extracted.skillsAndStack,
            communicationStyle: extracted.communicationStyle,
            activeProjects: extracted.activeProjects,
            goalsAndPriorities: extracted.goalsAndPriorities,
            constraints: extracted.constraints,
            workPatterns: extracted.workPatterns
        )
    }
}
#endif
