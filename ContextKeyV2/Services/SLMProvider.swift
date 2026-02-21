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

/// Fallback extraction using keyword + pattern matching.
/// No model needed — works on any device, any iOS version.
struct HeuristicProvider: SLMProvider {
    let displayName = "Basic Extraction"
    let isAvailable = true

    func extract(from text: String, prompt: String) async throws -> ExtractedFactsRaw {
        var result = ExtractedFactsRaw()

        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Role/persona indicators
        let roleKeywords = ["i am a", "i'm a", "i work as", "my role", "my title", "my job",
                            "i am an", "i'm an", "developer", "engineer", "designer", "manager",
                            "years of experience", "senior", "junior", "lead", "founder", "ceo", "cto"]
        // Skills/tech indicators
        let skillKeywords = ["i use", "i know", "i work with", "my stack", "swift", "python",
                             "javascript", "typescript", "react", "swiftui", "xcode", "figma",
                             "docker", "kubernetes", "aws", "firebase", "node", "rust", "go",
                             "java", "kotlin", "flutter", "vue", "angular", "django", "flask",
                             "tensorflow", "pytorch", "coreml", "langchain", "openai", "claude"]
        // Project indicators
        let projectKeywords = ["i'm building", "i am building", "working on", "my project",
                               "current project", "building a", "developing a", "creating a",
                               "my app", "our product", "our app", "the app", "this project"]
        // Goal indicators
        let goalKeywords = ["my goal", "i want to", "i'm trying", "objective", "planning to",
                            "hope to", "aim to", "target", "ship", "launch", "release",
                            "deadline", "by end of", "this quarter", "this month"]
        // Communication style
        let styleKeywords = ["prefer", "concise", "detailed", "brief", "verbose", "code-first",
                             "no fluff", "step by step", "explain", "don't explain",
                             "just give me", "show me the code", "be direct"]
        // Constraints
        let constraintKeywords = ["don't", "avoid", "never", "no cloud", "privacy", "on-device",
                                  "offline", "constraint", "limitation", "can't use", "not allowed",
                                  "budget", "free tier", "open source only"]
        // Work patterns
        let patternKeywords = ["i usually", "i typically", "my workflow", "i debug", "i review",
                               "brainstorm", "code review", "pair program", "iterate",
                               "i research", "i write", "i draft", "help me with"]

        for line in lines {
            let lower = line.lowercased()
            if roleKeywords.contains(where: { lower.contains($0) }) {
                result.persona.append(cleanFact(line))
            }
            if skillKeywords.contains(where: { lower.contains($0) }) {
                result.skillsAndStack.append(cleanFact(line))
            }
            if projectKeywords.contains(where: { lower.contains($0) }) {
                result.activeProjects.append(cleanFact(line))
            }
            if goalKeywords.contains(where: { lower.contains($0) }) {
                result.goalsAndPriorities.append(cleanFact(line))
            }
            if styleKeywords.contains(where: { lower.contains($0) }) {
                result.communicationStyle.append(cleanFact(line))
            }
            if constraintKeywords.contains(where: { lower.contains($0) }) {
                result.constraints.append(cleanFact(line))
            }
            if patternKeywords.contains(where: { lower.contains($0) }) {
                result.workPatterns.append(cleanFact(line))
            }
        }

        return result
    }

    /// Clean up extracted text — truncate long lines, strip markup
    private func cleanFact(_ text: String) -> String {
        var cleaned = text
        // Remove common markdown artifacts
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        cleaned = cleaned.replacingOccurrences(of: "**", with: "")
        // Truncate to reasonable length
        if cleaned.count > 200 {
            cleaned = String(cleaned.prefix(200)) + "..."
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
