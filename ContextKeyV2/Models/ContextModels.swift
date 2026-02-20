import Foundation
import FoundationModels

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

enum Platform: String, Codable, CaseIterable {
    case claude
    case chatgpt
    case perplexity
    case gemini
}

struct FileReference: Codable {
    let fileName: String
    let fileType: String?
}

// MARK: - Extracted Context (Output of SLM)

/// A single fact extracted about the user
struct ContextFact: Identifiable, Codable {
    let id: UUID
    var content: String
    var layer: ContextLayer
    var category: ContextCategory
    var confidence: Double               // 0.0 - 1.0
    var sources: [ContextSource]
    var lastSeenDate: Date
    var createdAt: Date

    init(
        content: String,
        layer: ContextLayer,
        category: ContextCategory,
        confidence: Double = 0.5,
        sources: [ContextSource] = [],
        lastSeenDate: Date = Date()
    ) {
        self.id = UUID()
        self.content = content
        self.layer = layer
        self.category = category
        self.confidence = confidence
        self.sources = sources
        self.lastSeenDate = lastSeenDate
        self.createdAt = Date()
    }
}

enum ContextLayer: String, Codable, CaseIterable {
    case coreIdentity    // Changes rarely: name, expertise, career
    case currentContext   // Changes monthly: job, projects, tech stack
    case activeContext    // Changes daily: current focus, blockers
}

enum ContextCategory: String, Codable, CaseIterable {
    case role
    case skill
    case project
    case preference
    case goal
    case interest
    case background
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

    /// Generate a formatted context string for pasting into AI apps
    func formattedContext() -> String {
        var sections: [String] = []
        sections.append("## About Me")

        let grouped = Dictionary(grouping: facts, by: { $0.layer })

        if let core = grouped[.coreIdentity], !core.isEmpty {
            let items = core.map { "- \($0.content)" }.joined(separator: "\n")
            sections.append("### Identity\n\(items)")
        }

        if let current = grouped[.currentContext], !current.isEmpty {
            let items = current.map { "- \($0.content)" }.joined(separator: "\n")
            sections.append("### Current Context\n\(items)")
        }

        if let active = grouped[.activeContext], !active.isEmpty {
            let items = active.map { "- \($0.content)" }.joined(separator: "\n")
            sections.append("### Right Now\n\(items)")
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
}

// MARK: - SLM Extraction Types (Apple Foundation Models)

/// Structured output for SLM extraction via @Generable
@Generable
struct ExtractedFacts {
    @Guide(description: "The user's professional role or job title, e.g. 'Senior iOS Developer' or 'Product Manager'")
    var role: String?

    @Guide(description: "Technical skills, tools, or frameworks the user demonstrates knowledge of, e.g. ['Swift', 'SwiftUI', 'Python']")
    var skills: [String]

    @Guide(description: "Projects or products the user is actively working on")
    var projects: [String]

    @Guide(description: "Communication or AI interaction preferences the user expresses, e.g. 'prefers concise answers with code examples'")
    var preferences: [String]

    @Guide(description: "Goals or objectives the user mentions wanting to achieve")
    var goals: [String]

    @Guide(description: "Background information like previous roles, education, or career history")
    var background: [String]

    @Guide(description: "Current interests or topics the user is exploring")
    var interests: [String]
}

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
    let citations: [String]?
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
