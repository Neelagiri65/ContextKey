import Foundation

// MARK: - Chat Parser

/// Parses chat exports from multiple AI platforms into normalized conversations
enum ChatParser {

    enum ParseError: Error, LocalizedError {
        case invalidJSON
        case emptyExport
        case unsupportedFormat
        case fileReadError(String)

        var errorDescription: String? {
            switch self {
            case .invalidJSON: return "The file contains invalid JSON data."
            case .emptyExport: return "No conversations found in the export."
            case .unsupportedFormat: return "This file format is not supported."
            case .fileReadError(let msg): return "Could not read file: \(msg)"
            }
        }
    }

    // MARK: - Public API

    /// Parse a file URL, auto-detecting the platform based on user selection
    static func parse(fileURL: URL, platform: Platform) throws -> ParseResult {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ParseError.fileReadError(error.localizedDescription)
        }
        return try parse(data: data, platform: platform)
    }

    /// Parse raw data for a given platform
    static func parse(data: Data, platform: Platform) throws -> ParseResult {
        switch platform {
        case .claude:
            return try parseClaude(data: data)
        case .chatgpt:
            return try parseChatGPT(data: data)
        case .perplexity:
            return try parsePerplexity(data: data)
        case .gemini:
            return try parseGemini(data: data)
        }
    }

    // MARK: - Claude Parser (Verified against real export Feb 2026)

    /// Parse Claude conversations.json export
    static func parseClaude(data: Data) throws -> ParseResult {
        let decoder = JSONDecoder()
        let rawConversations: [ClaudeExportConversation]
        do {
            rawConversations = try decoder.decode([ClaudeExportConversation].self, from: data)
        } catch {
            throw ParseError.invalidJSON
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        func parseDate(_ str: String) -> Date {
            dateFormatter.date(from: str) ?? fallbackFormatter.date(from: str) ?? Date()
        }

        var conversations: [ParsedConversation] = []

        for raw in rawConversations {
            let messages = raw.chatMessages.compactMap { msg -> ParsedMessage? in
                // Skip empty messages
                guard !msg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }

                let role: MessageRole = msg.sender == "human" ? .user : .assistant

                // Determine content type from content array
                let contentType: ContentType
                if let content = msg.content, content.contains(where: { $0.type == "tool_use" }) {
                    contentType = .toolUse
                } else {
                    contentType = .text
                }

                return ParsedMessage(
                    id: UUID(uuidString: msg.uuid) ?? UUID(),
                    role: role,
                    text: msg.text,
                    createdAt: parseDate(msg.createdAt),
                    contentType: contentType
                )
            }

            // Collect file references from attachments and files
            var fileRefs: [FileReference] = []
            for msg in raw.chatMessages {
                if let attachments = msg.attachments {
                    for att in attachments {
                        if let name = att.fileName {
                            fileRefs.append(FileReference(fileName: name, fileType: att.fileType))
                        }
                    }
                }
                if let files = msg.files {
                    for file in files {
                        if let name = file.fileName {
                            fileRefs.append(FileReference(fileName: name, fileType: nil))
                        }
                    }
                }
            }

            // Skip conversations with no messages
            guard !messages.isEmpty else { continue }

            conversations.append(ParsedConversation(
                id: UUID(uuidString: raw.uuid) ?? UUID(),
                platform: .claude,
                title: raw.name ?? "Untitled",
                createdAt: parseDate(raw.createdAt),
                updatedAt: parseDate(raw.updatedAt),
                messages: messages,
                fileReferences: fileRefs
            ))
        }

        if conversations.isEmpty {
            throw ParseError.emptyExport
        }

        let totalMessages = conversations.reduce(0) { $0 + $1.messages.count }

        return ParseResult(
            platform: .claude,
            conversations: conversations,
            totalMessages: totalMessages,
            totalConversations: conversations.count
        )
    }

    /// Parse Claude memories.json — returns pre-extracted context string
    static func parseClaudeMemories(data: Data) throws -> String? {
        let decoder = JSONDecoder()
        guard let memories = try? decoder.decode([ClaudeMemory].self, from: data),
              let first = memories.first else {
            return nil
        }
        return first.conversationsMemory
    }

    /// Parse Claude users.json — returns user info
    static func parseClaudeUser(data: Data) throws -> ClaudeUser? {
        let decoder = JSONDecoder()
        guard let users = try? decoder.decode([ClaudeUser].self, from: data),
              let first = users.first else {
            return nil
        }
        return first
    }

    // MARK: - ChatGPT Parser (Based on known schema, awaiting real export)

    /// Parse ChatGPT conversations.json export
    /// Note: ChatGPT uses a tree structure — we walk from current_node up via parent pointers
    static func parseChatGPT(data: Data) throws -> ParseResult {
        let decoder = JSONDecoder()
        let rawConversations: [ChatGPTExportConversation]
        do {
            rawConversations = try decoder.decode([ChatGPTExportConversation].self, from: data)
        } catch {
            throw ParseError.invalidJSON
        }

        var conversations: [ParsedConversation] = []

        for raw in rawConversations {
            guard let mapping = raw.mapping,
                  let currentNode = raw.currentNode else { continue }

            // Walk the tree: start from currentNode, follow parent pointers, then reverse
            var orderedMessages: [ParsedMessage] = []
            var fileRefs: [FileReference] = []
            var nodeId: String? = currentNode

            while let id = nodeId, let node = mapping[id] {
                if let msg = node.message,
                   let author = msg.author?.role,
                   (author == "user" || author == "assistant"),
                   let content = msg.content {

                    let role: MessageRole = author == "user" ? .user : .assistant

                    // Extract text from parts
                    var textParts: [String] = []
                    if let parts = content.parts {
                        for part in parts {
                            if let text = part.textValue, !text.isEmpty {
                                textParts.append(text)
                            }
                            // Non-text parts (images, files) — extract reference
                            if case .object(let obj) = part {
                                if let ct = obj["content_type"]?.value as? String,
                                   ct.contains("image") {
                                    fileRefs.append(FileReference(
                                        fileName: "image_upload",
                                        fileType: ct
                                    ))
                                }
                            }
                        }
                    }

                    let text = textParts.joined(separator: "\n")
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        nodeId = node.parent
                        continue
                    }

                    let contentType: ContentType
                    if content.contentType == "code" || content.contentType == "execution_output" {
                        contentType = .code
                    } else {
                        contentType = .text
                    }

                    let createdAt: Date
                    if let ts = msg.createTime {
                        createdAt = Date(timeIntervalSince1970: ts)
                    } else {
                        createdAt = Date()
                    }

                    orderedMessages.append(ParsedMessage(
                        id: UUID(uuidString: msg.id ?? "") ?? UUID(),
                        role: role,
                        text: text,
                        createdAt: createdAt,
                        contentType: contentType
                    ))
                }
                nodeId = node.parent
            }

            // Reverse since we walked from leaf to root
            orderedMessages.reverse()

            guard !orderedMessages.isEmpty else { continue }

            let createdAt: Date
            if let ts = raw.createTime {
                createdAt = Date(timeIntervalSince1970: ts)
            } else {
                createdAt = Date()
            }

            let updatedAt: Date
            if let ts = raw.updateTime {
                updatedAt = Date(timeIntervalSince1970: ts)
            } else {
                updatedAt = createdAt
            }

            conversations.append(ParsedConversation(
                id: UUID(),
                platform: .chatgpt,
                title: raw.title ?? "Untitled",
                createdAt: createdAt,
                updatedAt: updatedAt,
                messages: orderedMessages,
                fileReferences: fileRefs
            ))
        }

        if conversations.isEmpty {
            throw ParseError.emptyExport
        }

        let totalMessages = conversations.reduce(0) { $0 + $1.messages.count }

        return ParseResult(
            platform: .chatgpt,
            conversations: conversations,
            totalMessages: totalMessages,
            totalConversations: conversations.count
        )
    }

    // MARK: - Perplexity Parser (Placeholder — needs real export to verify)

    static func parsePerplexity(data: Data) throws -> ParseResult {
        // TODO: Implement once we have a real Perplexity export
        throw ParseError.unsupportedFormat
    }

    // MARK: - Gemini Parser (Placeholder — needs real export to verify)

    static func parseGemini(data: Data) throws -> ParseResult {
        // TODO: Implement once we have a real Gemini export
        throw ParseError.unsupportedFormat
    }
}

// MARK: - Parse Result

struct ParseResult {
    let platform: Platform
    let conversations: [ParsedConversation]
    let totalMessages: Int
    let totalConversations: Int
}
