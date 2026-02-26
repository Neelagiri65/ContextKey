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
        do {
            let session = LanguageModelSession()
            let fullInput = prompt + "\n\nText to analyze:\n" + text
            let response = try await session.respond(
                to: fullInput,
                generating: ExtractedFacts.self
            )
            let extracted = response.content

            let result = ExtractedFactsRaw(
                persona: extracted.persona,
                skillsAndStack: extracted.skillsAndStack,
                communicationStyle: extracted.communicationStyle,
                activeProjects: extracted.activeProjects,
                goalsAndPriorities: extracted.goalsAndPriorities,
                constraints: extracted.constraints,
                workPatterns: extracted.workPatterns
            )

            let totalFacts = result.persona.count + result.skillsAndStack.count +
                result.communicationStyle.count + result.activeProjects.count +
                result.goalsAndPriorities.count + result.constraints.count +
                result.workPatterns.count
            print("[AppleFM] Extraction succeeded: \(totalFacts) facts extracted")

            return result
        } catch {
            print("[AppleFM] Extraction failed: \(type(of: error)) - \(error.localizedDescription)")
            throw error
        }
    }
}
#endif
