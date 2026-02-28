import Foundation
import Testing
@testable import ContextKeyV2

// MARK: - Mock Language Model Session

/// Returns a canned response string for testing V2SLMCaller without Apple Intelligence.
struct MockLanguageModelSession: LanguageModelSessionProtocol, @unchecked Sendable {
    let responses: [String]
    private let callCounter = Counter()

    /// Tracks how many times respond() was called (for verifying retry logic).
    var callCount: Int { callCounter.value }

    init(responses: [String]) {
        self.responses = responses
    }

    /// Convenience: single response for all calls.
    init(response: String) {
        self.responses = [response]
    }

    func respond(to prompt: String) async throws -> String {
        let index = callCounter.incrementAndGet() - 1
        if index < responses.count {
            return responses[index]
        }
        return responses.last ?? ""
    }
}

/// Thread-safe counter for tracking mock call counts.
private final class Counter: @unchecked Sendable {
    private var _value = 0
    private let lock = NSLock()

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    @discardableResult
    func incrementAndGet() -> Int {
        lock.lock()
        defer { lock.unlock() }
        _value += 1
        return _value
    }
}

// MARK: - Tests

@Suite("V2SLMCaller Tests")
struct V2SLMCallerTests {

    // MARK: - Test 1: Plain text response parses into unclassified candidates

    @Test("Plain text response parses into unclassified candidates")
    func plainTextParsesIntoCandidates() {
        let response = """
        I am an iOS developer
        I use Swift and SwiftUI daily
        Building an app called ContextKey
        """

        let mock = MockLanguageModelSession(response: response)
        let caller = V2SLMCaller(session: mock)
        let candidates = caller.parsePlainTextLines(response)

        #expect(candidates.count == 3)
        #expect(candidates[0].text == "I am an iOS developer")
        #expect(candidates[1].text == "I use Swift and SwiftUI daily")
        #expect(candidates[2].text == "Building an app called ContextKey")

        // All candidates should be unclassified
        for candidate in candidates {
            #expect(candidate.entityType == nil, "Candidates should have nil entityType")
            #expect(candidate.speakerAttribution == .userExplicit)
            #expect(candidate.confidence == 0.5)
        }
    }

    // MARK: - Test 2: Empty response returns no candidates

    @Test("Empty or garbage response returns no candidates")
    func emptyResponseReturnsNoCandidates() {
        let mock = MockLanguageModelSession(response: "")
        let caller = V2SLMCaller(session: mock)
        let candidates = caller.parsePlainTextLines("")

        #expect(candidates.isEmpty)

        // Also test whitespace-only
        let whitespace = caller.parsePlainTextLines("   \n  \n\n  ")
        #expect(whitespace.isEmpty)

        // Also test short junk (< 5 chars)
        let short = caller.parsePlainTextLines("OK\nHi\nYes")
        #expect(short.isEmpty)
    }

    // MARK: - Test 3: parsePlainTextLines strips list prefixes

    @Test("parsePlainTextLines strips bullet and number prefixes")
    func stripsListPrefixes() {
        let response = """
        - I am an iOS developer
        • I use Swift daily
        1. Building ContextKey app
        """

        let mock = MockLanguageModelSession(response: response)
        let caller = V2SLMCaller(session: mock)
        let candidates = caller.parsePlainTextLines(response)

        #expect(candidates.count == 3)
        #expect(candidates[0].text == "I am an iOS developer")
        #expect(candidates[1].text == "I use Swift daily")
        #expect(candidates[2].text == "Building ContextKey app")
    }
}
