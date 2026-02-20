import Foundation

// MARK: - SLM Provider Protocol

/// Abstraction layer for on-device language models.
/// Allows the app to use Apple Foundation Models (iOS 26+) or open-source alternatives.
protocol SLMProvider: Sendable {
    /// Human-readable name for UI display
    var displayName: String { get }

    /// Whether this provider is available on the current device
    var isAvailable: Bool { get }

    /// Extract structured facts from text using the provider's language model
    func extract(from text: String, prompt: String) async throws -> ExtractedFactsRaw
}

/// Provider-agnostic extraction result — plain strings, no @Generable dependency
struct ExtractedFactsRaw: Sendable {
    var persona: [String]
    var skillsAndStack: [String]
    var communicationStyle: [String]
    var activeProjects: [String]
    var goalsAndPriorities: [String]
    var constraints: [String]
    var workPatterns: [String]

    init(
        persona: [String] = [],
        skillsAndStack: [String] = [],
        communicationStyle: [String] = [],
        activeProjects: [String] = [],
        goalsAndPriorities: [String] = [],
        constraints: [String] = [],
        workPatterns: [String] = []
    ) {
        self.persona = persona
        self.skillsAndStack = skillsAndStack
        self.communicationStyle = communicationStyle
        self.activeProjects = activeProjects
        self.goalsAndPriorities = goalsAndPriorities
        self.constraints = constraints
        self.workPatterns = workPatterns
    }
}

// MARK: - Available SLM Engine Enum

/// The SLM engines the user can choose from
enum SLMEngine: String, Codable, CaseIterable, Sendable {
    case appleFoundationModels  // iOS 26+ only, zero app size cost
    case onDeviceOpenSource     // Any iOS, downloads model on demand

    var displayName: String {
        switch self {
        case .appleFoundationModels: return "Apple Intelligence"
        case .onDeviceOpenSource: return "Open Source (On-Device)"
        }
    }

    var subtitle: String {
        switch self {
        case .appleFoundationModels: return "Built into iOS 26+, no download needed"
        case .onDeviceOpenSource: return "Works on any iOS, downloads a small model"
        }
    }

    var iconName: String {
        switch self {
        case .appleFoundationModels: return "apple.logo"
        case .onDeviceOpenSource: return "cpu"
        }
    }

    /// Check if this engine is available on the current device
    var isAvailable: Bool {
        switch self {
        case .appleFoundationModels:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                return true
            }
            #endif
            return false
        case .onDeviceOpenSource:
            return true // Always available (model downloaded on demand)
        }
    }

    /// Get the available engines for this device
    static var availableEngines: [SLMEngine] {
        allCases.filter { $0.isAvailable }
    }
}

// MARK: - SLM Provider Factory

/// Creates the appropriate SLM provider based on user selection
enum SLMProviderFactory {
    @MainActor
    static func create(for engine: SLMEngine) -> any SLMProvider {
        switch engine {
        case .appleFoundationModels:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                return AppleFoundationModelsProvider()
            }
            #endif
            // Fallback if somehow selected on older iOS
            return HeuristicProvider()
        case .onDeviceOpenSource:
            return OpenSourceSLMProvider()
        }
    }
}

// MARK: - Heuristic Provider (Minimum Tier — Always Works)

/// Fallback extraction using NaturalLanguage framework + pattern matching.
/// No model needed — works on any device, any iOS version.
struct HeuristicProvider: SLMProvider {
    let displayName = "Basic Extraction"
    let isAvailable = true

    func extract(from text: String, prompt: String) async throws -> ExtractedFactsRaw {
        // Simple keyword-based extraction as absolute fallback
        var result = ExtractedFactsRaw()

        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Look for role/title indicators
        let roleKeywords = ["i am a", "i'm a", "i work as", "my role", "my title", "my job"]
        let skillKeywords = ["i use", "i know", "i work with", "my stack", "using swift", "using python"]
        let projectKeywords = ["i'm building", "i am building", "working on", "my project", "current project"]
        let goalKeywords = ["my goal", "i want to", "i'm trying", "objective", "planning to"]

        for line in lines {
            let lower = line.lowercased()
            if roleKeywords.contains(where: { lower.contains($0) }) {
                result.persona.append(line)
            }
            if skillKeywords.contains(where: { lower.contains($0) }) {
                result.skillsAndStack.append(line)
            }
            if projectKeywords.contains(where: { lower.contains($0) }) {
                result.activeProjects.append(line)
            }
            if goalKeywords.contains(where: { lower.contains($0) }) {
                result.goalsAndPriorities.append(line)
            }
        }

        return result
    }
}
