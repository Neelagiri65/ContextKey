import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Parsed Conversation (Platform-Agnostic)

/// A normalized conversation from any platform export
struct ParsedConversation: Identifiable, Codable {
    let id: UUID
    let platform: Platform
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let messages: [ParsedMessage]
    let fileReferences: [FileReference]
}

struct ParsedMessage: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    let text: String
    let createdAt: Date
    let contentType: ContentType
}

enum MessageRole: String, Codable {
    case user
    case assistant
}

enum ContentType: String, Codable {
    case text
    case code
    case toolUse
}

enum Platform: String, Codable, CaseIterable, Identifiable {
    case claude
    case chatgpt
    case perplexity
    case gemini
    case manual

    var id: String { rawValue }

    /// Display name for UI
    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        case .perplexity: return "Perplexity"
        case .gemini: return "Gemini"
        case .manual: return "Manual"
        }
    }

    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .claude: return "brain.head.profile"
        case .chatgpt: return "bubble.left.and.bubble.right"
        case .perplexity: return "magnifyingglass"
        case .gemini: return "sparkles"
        case .manual: return "pencil"
        }
    }

    /// URL scheme for quick-launch
    var urlScheme: String? {
        switch self {
        case .chatgpt: return "chatgpt://"
        case .claude: return "claude://"
        case .gemini: return "gemini://"
        case .perplexity: return "perplexity://"
        case .manual: return nil
        }
    }

    /// Only the AI platforms (excludes .manual)
    static var aiPlatforms: [Platform] {
        [.chatgpt, .claude, .gemini, .perplexity]
    }
}

struct FileReference: Codable {
    let fileName: String
    let fileType: String?
}

// MARK: - The 7-Pillar Context Framework

/// The 7 context pillars — grounded in RISEN, CO-STAR, RODES prompt engineering research
enum ContextPillar: String, Codable, CaseIterable {
    case persona            // Name, role, expertise level, industry
    case skillsAndStack     // Tools, languages, frameworks, domains
    case communicationStyle  // Tone, verbosity, format preferences
    case activeProjects     // What you're building NOW
    case goalsAndPriorities // Objectives, success criteria
    case constraints        // What to avoid, boundaries
    case workPatterns       // How you use AI — coding, writing, research

    var displayName: String {
        switch self {
        case .persona: return "Persona"
        case .skillsAndStack: return "Skills & Stack"
        case .communicationStyle: return "Communication Style"
        case .activeProjects: return "Active Projects"
        case .goalsAndPriorities: return "Goals & Priorities"
        case .constraints: return "Constraints"
        case .workPatterns: return "Work Patterns"
        }
    }

    var iconName: String {
        switch self {
        case .persona: return "person.fill"
        case .skillsAndStack: return "wrench.and.screwdriver.fill"
        case .communicationStyle: return "text.bubble.fill"
        case .activeProjects: return "hammer.fill"
        case .goalsAndPriorities: return "target"
        case .constraints: return "shield.fill"
        case .workPatterns: return "arrow.triangle.branch"
        }
    }

    var color: String {
        switch self {
        case .persona: return "blue"
        case .skillsAndStack: return "purple"
        case .communicationStyle: return "green"
        case .activeProjects: return "orange"
        case .goalsAndPriorities: return "red"
        case .constraints: return "gray"
        case .workPatterns: return "teal"
        }
    }

    /// Description shown as placeholder in guided input
    var promptHint: String {
        switch self {
        case .persona: return "Your role, title, expertise level, and industry"
        case .skillsAndStack: return "Tools, languages, frameworks you use"
        case .communicationStyle: return "How you prefer AI to respond"
        case .activeProjects: return "What you're currently building or working on"
        case .goalsAndPriorities: return "What you're trying to achieve"
        case .constraints: return "Things to avoid, boundaries, limitations"
        case .workPatterns: return "How you use AI day-to-day"
        }
    }
}

// MARK: - Extracted Context (Output of SLM)

/// A single fact extracted about the user
struct ContextFact: Identifiable, Codable {
    let id: UUID
    var content: String
    var layer: ContextLayer
    var pillar: ContextPillar
    var confidence: Double               // 0.0 - 1.0
    var frequency: Int                   // How many times this fact appeared
    var sources: [ContextSource]
    var lastSeenDate: Date
    var createdAt: Date

    init(
        content: String,
        layer: ContextLayer,
        pillar: ContextPillar,
        confidence: Double = 0.5,
        frequency: Int = 1,
        sources: [ContextSource] = [],
        lastSeenDate: Date = Date()
    ) {
        self.id = UUID()
        self.content = content
        self.layer = layer
        self.pillar = pillar
        self.confidence = confidence
        self.frequency = frequency
        self.sources = sources
        self.lastSeenDate = lastSeenDate
        self.createdAt = Date()
    }

    // Backward-compatible decoding (handles old profiles without frequency/pillar)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        layer = try container.decode(ContextLayer.self, forKey: .layer)
        confidence = try container.decode(Double.self, forKey: .confidence)
        sources = try container.decode([ContextSource].self, forKey: .sources)
        lastSeenDate = try container.decode(Date.self, forKey: .lastSeenDate)
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        // New fields with backward-compatible defaults
        frequency = (try? container.decode(Int.self, forKey: .frequency)) ?? 1

        // Migrate old 'category' to new 'pillar'
        if let pillarValue = try? container.decode(ContextPillar.self, forKey: .pillar) {
            pillar = pillarValue
        } else if let oldCategory = try? container.decode(String.self, forKey: .legacyCategory) {
            pillar = ContextPillar.fromLegacyCategory(oldCategory)
        } else {
            pillar = .persona
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, content, layer, pillar, confidence, frequency, sources, lastSeenDate, createdAt
        case legacyCategory = "category"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encode(layer, forKey: .layer)
        try container.encode(pillar, forKey: .pillar)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(sources, forKey: .sources)
        try container.encode(lastSeenDate, forKey: .lastSeenDate)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

extension ContextPillar {
    /// Migrate old ContextCategory values to new pillars
    static func fromLegacyCategory(_ category: String) -> ContextPillar {
        switch category {
        case "role": return .persona
        case "skill": return .skillsAndStack
        case "project": return .activeProjects
        case "preference": return .communicationStyle
        case "goal": return .goalsAndPriorities
        case "interest": return .workPatterns
        case "background": return .persona
        default: return .persona
        }
    }
}

enum ContextLayer: String, Codable, CaseIterable {
    case coreIdentity    // Changes rarely: name, expertise, career
    case currentContext   // Changes monthly: job, projects, tech stack
    case activeContext    // Changes daily: current focus, blockers
}

struct ContextSource: Codable {
    let platform: Platform
    let conversationCount: Int
    let lastConversationDate: Date
}

// MARK: - User Context Profile (Stored on device)

/// The complete context profile stored locally
struct UserContextProfile: Codable {
    var facts: [ContextFact]
    var rawMemory: String?              // Claude's memories.json content (pre-extracted)
    var importHistory: [ImportRecord]
    var lastUpdated: Date
    var createdAt: Date

    init() {
        self.facts = []
        self.rawMemory = nil
        self.importHistory = []
        self.lastUpdated = Date()
        self.createdAt = Date()
    }

    /// Facts for a specific pillar, sorted by frequency (descending)
    func facts(for pillar: ContextPillar) -> [ContextFact] {
        facts.filter { $0.pillar == pillar }
            .sorted { $0.frequency > $1.frequency }
    }

    /// Count of facts per pillar
    var pillarCounts: [ContextPillar: Int] {
        Dictionary(grouping: facts, by: { $0.pillar })
            .mapValues { $0.count }
    }

    /// Generate a formatted context string for pasting into AI apps
    /// Targets 300-500 tokens — compact enough for any AI's system prompt
    func formattedContext() -> String {
        var sections: [String] = []
        sections.append("## About Me")

        for pillar in ContextPillar.allCases {
            let pillarFacts = facts(for: pillar)
            guard !pillarFacts.isEmpty else { continue }

            let items = pillarFacts.map { fact in
                if fact.frequency > 2 {
                    return "- \(fact.content) (frequently mentioned)"
                } else {
                    return "- \(fact.content)"
                }
            }.joined(separator: "\n")

            sections.append("### \(pillar.displayName)\n\(items)")
        }

        return sections.joined(separator: "\n\n")
    }
}

struct ImportRecord: Codable {
    let platform: Platform
    let conversationCount: Int
    let messageCount: Int
    let importedAt: Date
    let factsExtracted: Int

    /// Facts per message ratio
    var extractionRate: Double {
        guard messageCount > 0 else { return 0 }
        return Double(factsExtracted) / Double(messageCount)
    }

    /// Human-readable quality label
    var qualityLabel: String {
        switch extractionRate {
        case 0.5...: return "Excellent"
        case 0.2..<0.5: return "Good"
        case 0.05..<0.2: return "Fair"
        default: return "Low"
        }
    }
}

// MARK: - SLM Extraction Types (Apple Foundation Models)

/// Structured output for SLM extraction via @Generable — aligned with 7-pillar framework
/// Only available on iOS 26+ where FoundationModels is present
#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct ExtractedFacts {
    @Guide(description: "Professional role, job title, expertise level, industry, years of experience. E.g. 'Senior iOS Developer with 8 years in fintech'")
    var persona: [String]

    @Guide(description: "Technical skills, tools, languages, frameworks, platforms the user uses. E.g. 'Swift', 'SwiftUI', 'Python', 'CoreML'")
    var skillsAndStack: [String]

    @Guide(description: "Communication preferences: how user likes AI to respond — tone (formal/casual), response length (concise/detailed), format (code-first, bullet points, explanations), interaction style")
    var communicationStyle: [String]

    @Guide(description: "Current projects, products, or initiatives the user is actively working on")
    var activeProjects: [String]

    @Guide(description: "Goals, objectives, priorities, success criteria the user mentions wanting to achieve")
    var goalsAndPriorities: [String]

    @Guide(description: "Constraints, boundaries, things to avoid, limitations the user mentions. E.g. 'privacy-first', 'no cloud processing', 'iOS only'")
    var constraints: [String]

    @Guide(description: "How the user works with AI: coding help, writing, research, email drafting, brainstorming, code review, data analysis, content creation")
    var workPatterns: [String]
}
#endif

// MARK: - Import/Export Format Models (Raw JSON Structures)

/// Raw Claude export conversation structure
struct ClaudeExportConversation: Codable {
    let uuid: String
    let name: String?
    let summary: String?
    let createdAt: String
    let updatedAt: String
    let account: ClaudeAccount?
    let chatMessages: [ClaudeMessage]

    enum CodingKeys: String, CodingKey {
        case uuid, name, summary, account
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case chatMessages = "chat_messages"
    }
}

struct ClaudeAccount: Codable {
    let uuid: String
}

struct ClaudeMessage: Codable {
    let uuid: String
    let text: String
    let content: [ClaudeContent]?
    let sender: String
    let createdAt: String
    let updatedAt: String
    let attachments: [ClaudeAttachment]?
    let files: [ClaudeFile]?

    enum CodingKeys: String, CodingKey {
        case uuid, text, content, sender, attachments, files
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ClaudeContent: Codable {
    let type: String?
    let text: String?

    // Citations can be null, an array of strings, or an array of objects — ignore for our purposes
    enum CodingKeys: String, CodingKey {
        case type, text
    }
}

struct ClaudeAttachment: Codable {
    let fileName: String?
    let fileType: String?
    let fileSize: Int?
    let extractedContent: String?

    enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case fileType = "file_type"
        case fileSize = "file_size"
        case extractedContent = "extracted_content"
    }
}

struct ClaudeFile: Codable {
    let fileName: String?

    enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
    }
}

struct ClaudeMemory: Codable {
    let conversationsMemory: String
    let accountUuid: String

    enum CodingKeys: String, CodingKey {
        case conversationsMemory = "conversations_memory"
        case accountUuid = "account_uuid"
    }
}

struct ClaudeUser: Codable {
    let uuid: String
    let fullName: String?
    let emailAddress: String?

    enum CodingKeys: String, CodingKey {
        case uuid
        case fullName = "full_name"
        case emailAddress = "email_address"
    }
}

/// Raw ChatGPT export conversation structure
struct ChatGPTExportConversation: Codable {
    let title: String?
    let createTime: Double?
    let updateTime: Double?
    let mapping: [String: ChatGPTNode]?
    let currentNode: String?
    let conversationId: String?

    enum CodingKeys: String, CodingKey {
        case title, mapping
        case createTime = "create_time"
        case updateTime = "update_time"
        case currentNode = "current_node"
        case conversationId = "conversation_id"
    }
}

struct ChatGPTNode: Codable {
    let id: String?
    let message: ChatGPTMessage?
    let parent: String?
    let children: [String]?
}

struct ChatGPTMessage: Codable {
    let id: String?
    let author: ChatGPTAuthor?
    let createTime: Double?
    let content: ChatGPTContent?

    enum CodingKeys: String, CodingKey {
        case id, author, content
        case createTime = "create_time"
    }
}

struct ChatGPTAuthor: Codable {
    let role: String?
}

struct ChatGPTContent: Codable {
    let contentType: String?
    let parts: [ChatGPTPartWrapper]?

    enum CodingKeys: String, CodingKey {
        case contentType = "content_type"
        case parts
    }
}

/// ChatGPT parts can be strings or objects (for images/files)
enum ChatGPTPartWrapper: Codable {
    case text(String)
    case object([String: AnyCodable])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .text(str)
        } else if let obj = try? container.decode([String: AnyCodable].self) {
            self = .object(obj)
        } else {
            self = .text("")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let str):
            try container.encode(str)
        case .object(let obj):
            try container.encode(obj)
        }
    }

    var textValue: String? {
        if case .text(let str) = self { return str }
        return nil
    }
}

/// Type-erased Codable wrapper for handling mixed JSON types
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) { value = str }
        else if let int = try? container.decode(Int.self) { value = int }
        else if let double = try? container.decode(Double.self) { value = double }
        else if let bool = try? container.decode(Bool.self) { value = bool }
        else if container.decodeNil() { value = NSNull() }
        else { value = "" }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let str = value as? String { try container.encode(str) }
        else if let int = value as? Int { try container.encode(int) }
        else if let double = value as? Double { try container.encode(double) }
        else if let bool = value as? Bool { try container.encode(bool) }
        else { try container.encodeNil() }
    }
}
