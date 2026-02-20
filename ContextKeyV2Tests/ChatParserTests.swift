import XCTest
@testable import ContextKeyV2

final class ChatParserTests: XCTestCase {

    // MARK: - TEST-PARSE-006: Parse Claude export JSON with text conversations

    func testParseClaudeConversations() throws {
        let json = """
        [
          {
            "uuid": "test-uuid-1",
            "name": "Test Conversation",
            "summary": "",
            "created_at": "2026-02-11T09:08:52.683560Z",
            "updated_at": "2026-02-11T09:08:52.683560Z",
            "account": {"uuid": "account-1"},
            "chat_messages": [
              {
                "uuid": "msg-1",
                "text": "I'm a senior iOS developer working on SwiftUI apps",
                "content": [{"type": "text", "text": "I'm a senior iOS developer working on SwiftUI apps", "citations": null}],
                "sender": "human",
                "created_at": "2026-02-11T09:08:52.992325Z",
                "updated_at": "2026-02-11T09:08:52.992325Z",
                "attachments": [],
                "files": []
              },
              {
                "uuid": "msg-2",
                "text": "That's great! As a senior iOS developer...",
                "content": [{"type": "text", "text": "That's great!", "citations": null}],
                "sender": "assistant",
                "created_at": "2026-02-11T09:09:12.445904Z",
                "updated_at": "2026-02-11T09:09:12.445904Z",
                "attachments": [],
                "files": []
              }
            ]
          }
        ]
        """.data(using: .utf8)!

        let result = try ChatParser.parseClaude(data: json)

        XCTAssertEqual(result.totalConversations, 1)
        XCTAssertEqual(result.totalMessages, 2)
        XCTAssertEqual(result.platform, .claude)
        XCTAssertEqual(result.conversations.first?.title, "Test Conversation")
        XCTAssertEqual(result.conversations.first?.messages.first?.role, .user)
        XCTAssertEqual(result.conversations.first?.messages.first?.text, "I'm a senior iOS developer working on SwiftUI apps")
    }

    // MARK: - TEST-PARSE-008: Parse Claude export with file references

    func testParseClaudeWithFiles() throws {
        let json = """
        [
          {
            "uuid": "test-uuid-2",
            "name": "File Upload Test",
            "summary": "",
            "created_at": "2026-02-11T09:08:52.683560Z",
            "updated_at": "2026-02-11T09:08:52.683560Z",
            "account": {"uuid": "account-1"},
            "chat_messages": [
              {
                "uuid": "msg-3",
                "text": "Here is my resume",
                "content": [{"type": "text", "text": "Here is my resume", "citations": null}],
                "sender": "human",
                "created_at": "2026-02-11T09:08:52.992325Z",
                "updated_at": "2026-02-11T09:08:52.992325Z",
                "attachments": [],
                "files": [{"file_name": "resume.pdf"}]
              }
            ]
          }
        ]
        """.data(using: .utf8)!

        let result = try ChatParser.parseClaude(data: json)

        XCTAssertEqual(result.conversations.first?.fileReferences.count, 1)
        XCTAssertEqual(result.conversations.first?.fileReferences.first?.fileName, "resume.pdf")
    }

    // MARK: - TEST-PARSE-011: Handle corrupted JSON

    func testParseClaudeInvalidJSON() {
        let badData = "this is not json".data(using: .utf8)!

        XCTAssertThrowsError(try ChatParser.parseClaude(data: badData)) { error in
            XCTAssertTrue(error is ChatParser.ParseError)
        }
    }

    // MARK: - TEST-PARSE-012: Handle empty export

    func testParseClaudeEmptyConversations() {
        let json = "[]".data(using: .utf8)!

        XCTAssertThrowsError(try ChatParser.parseClaude(data: json)) { error in
            if let parseError = error as? ChatParser.ParseError {
                XCTAssertEqual(parseError.errorDescription, "No conversations found in the export.")
            }
        }
    }

    // MARK: - Claude memories.json parsing

    func testParseClaudeMemories() throws {
        let json = """
        [{"conversations_memory": "User is a developer working on iOS apps", "account_uuid": "test-uuid"}]
        """.data(using: .utf8)!

        let memory = try ChatParser.parseClaudeMemories(data: json)
        XCTAssertNotNil(memory)
        XCTAssertTrue(memory!.contains("developer"))
    }

    // MARK: - TEST-PARSE-001: Parse ChatGPT basic conversation

    func testParseChatGPTBasicConversation() throws {
        let json = """
        [
          {
            "title": "SwiftUI Question",
            "create_time": 1693000000.0,
            "update_time": 1693000500.0,
            "mapping": {
              "root": {
                "id": "root",
                "message": null,
                "parent": null,
                "children": ["msg1"]
              },
              "msg1": {
                "id": "msg1",
                "message": {
                  "id": "msg1",
                  "author": {"role": "user"},
                  "create_time": 1693000100.0,
                  "content": {
                    "content_type": "text",
                    "parts": ["How do I build a list in SwiftUI?"]
                  }
                },
                "parent": "root",
                "children": ["msg2"]
              },
              "msg2": {
                "id": "msg2",
                "message": {
                  "id": "msg2",
                  "author": {"role": "assistant"},
                  "create_time": 1693000200.0,
                  "content": {
                    "content_type": "text",
                    "parts": ["You can use List in SwiftUI like this..."]
                  }
                },
                "parent": "msg1",
                "children": []
              }
            },
            "current_node": "msg2",
            "conversation_id": "conv-1"
          }
        ]
        """.data(using: .utf8)!

        let result = try ChatParser.parseChatGPT(data: json)

        XCTAssertEqual(result.totalConversations, 1)
        XCTAssertEqual(result.totalMessages, 2)
        XCTAssertEqual(result.platform, .chatgpt)
        XCTAssertEqual(result.conversations.first?.title, "SwiftUI Question")
        XCTAssertEqual(result.conversations.first?.messages.first?.role, .user)
        XCTAssertEqual(result.conversations.first?.messages.first?.text, "How do I build a list in SwiftUI?")
    }

    // MARK: - Real Claude Export Integration Test

    func testParseRealClaudeExport() throws {
        // Try multiple paths to find TestFixtures
        let candidatePaths = [
            // Source tree path (when running from Xcode with source tree access)
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("TestFixtures")
                .appendingPathComponent("claude_export")
                .appendingPathComponent("conversations.json"),
            // Project root path
            URL(fileURLWithPath: ProcessInfo.processInfo.environment["PROJECT_DIR"] ?? "")
                .appendingPathComponent("TestFixtures")
                .appendingPathComponent("claude_export")
                .appendingPathComponent("conversations.json"),
            // Hardcoded project path as last resort
            URL(fileURLWithPath: "/Users/srinathprasannancs/ContextKeyV2/TestFixtures/claude_export/conversations.json")
        ]

        guard let fixturesURL = candidatePaths.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            // Skip if no real export available
            return
        }

        let data = try Data(contentsOf: fixturesURL)
        let result = try ChatParser.parseClaude(data: data)

        XCTAssertGreaterThan(result.totalConversations, 0, "Should parse at least some conversations")
        XCTAssertGreaterThan(result.totalMessages, 0, "Should have messages")

        // Verify all conversations have the expected structure
        for conv in result.conversations {
            XCTAssertEqual(conv.platform, .claude)
            XCTAssertFalse(conv.messages.isEmpty, "Conversation '\(conv.title)' should have messages")
            for msg in conv.messages {
                XCTAssertFalse(msg.text.isEmpty, "Message should have text")
                XCTAssertTrue(msg.role == .user || msg.role == .assistant)
            }
        }
    }
}
