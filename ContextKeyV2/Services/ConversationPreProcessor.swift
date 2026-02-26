import Foundation
import NaturalLanguage

// MARK: - Conversation Pre-Processor (Section 2.2)

/// Output of the pre-processing pipeline. Ready to be fed into the SLM caller (Section 2.3).
struct PreProcessedConversation {
    let taggedText: String           // Speaker-tagged text ([USER] / [ASSISTANT] markers)
    let primingTopics: [String]      // Named entities extracted via NLTagger
    let chunks: [String]             // Overlapping text chunks for SLM consumption
    let estimatedDate: Date?         // Date parsed from content, if any
    let detectedPlatform: Platform   // Auto-detected from conversation patterns
}

/// Standalone pre-processor that takes raw pasted text and produces
/// speaker-tagged, chunked, NLTagger-primed output for the SLM pipeline.
///
/// Does NOT call any SLM or Apple Intelligence API — pure text processing only.
enum ConversationPreProcessor {

    // MARK: - Constants

    /// Target chunk size in characters (~2000 tokens at 4 chars/token).
    static let chunkSize = 8000

    /// Number of overlapping characters between consecutive chunks (~500 tokens).
    /// Ensures entities near chunk boundaries aren't lost.
    static let overlapSize = 2000

    // MARK: - Public API

    /// Run the full pre-processing pipeline on raw input text.
    static func process(_ rawText: String) -> PreProcessedConversation {
        let platform = detectPlatform(rawText)
        let taggedText = tagSpeakers(rawText, platform: platform)
        let primingTopics = extractPrimingTopics(rawText)
        let chunks = createOverlappingChunks(taggedText, chunkSize: chunkSize, overlapSize: overlapSize)
        let estimatedDate = extractDate(rawText)

        return PreProcessedConversation(
            taggedText: taggedText,
            primingTopics: primingTopics,
            chunks: chunks,
            estimatedDate: estimatedDate,
            detectedPlatform: platform
        )
    }

    // MARK: - Step A: Platform Detection & Speaker Tagging

    /// Detect platform from raw text patterns.
    /// Priority order: ChatGPT → Claude → Perplexity → manual.
    static func detectPlatform(_ text: String) -> Platform {
        // 1. ChatGPT: "You said:" + "ChatGPT said:"
        if text.contains("You said:") && text.contains("ChatGPT said:") {
            return .chatgpt
        }

        // 2. Claude: "Human:" + "Assistant:"
        if text.contains("Human:") && text.contains("Assistant:") {
            return .claude
        }

        // 3. Perplexity: "Sources:" or numbered citations like [1], [2]
        if text.contains("Sources:") || text.range(of: #"\[\d+\]"#, options: .regularExpression) != nil {
            return .perplexity
        }

        // 4. Default: manual (typed text, single speaker)
        return .manual
    }

    /// Tag speaker turns with normalized [USER] and [ASSISTANT] markers.
    static func tagSpeakers(_ text: String, platform: Platform) -> String {
        switch platform {
        case .chatgpt:
            return tagChatGPTSpeakers(text)
        case .claude:
            return tagClaudeSpeakers(text)
        case .perplexity, .gemini, .manual:
            // Single-speaker: entire text attributed to user
            return "[USER]\n\(text)"
        }
    }

    /// ChatGPT format: "You said:\n..." / "ChatGPT said:\n..."
    private static func tagChatGPTSpeakers(_ text: String) -> String {
        // Split on speaker markers, preserving the marker text for identification
        let pattern = #"(?:^|\n)(You said:|ChatGPT said:)\n?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return "[USER]\n\(text)"
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        guard !matches.isEmpty else {
            return "[USER]\n\(text)"
        }

        var tagged = ""
        for (i, match) in matches.enumerated() {
            let markerRange = match.range(at: 1)
            let marker = nsText.substring(with: markerRange)

            // Content starts after the full match
            let contentStart = match.range.upperBound
            let contentEnd: Int
            if i + 1 < matches.count {
                contentEnd = matches[i + 1].range.location
            } else {
                contentEnd = nsText.length
            }

            let content = nsText.substring(with: NSRange(location: contentStart, length: contentEnd - contentStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if content.isEmpty { continue }

            let tag = marker.hasPrefix("You said") ? "[USER]" : "[ASSISTANT]"
            if !tagged.isEmpty { tagged += "\n" }
            tagged += "\(tag)\n\(content)"
        }

        return tagged.isEmpty ? "[USER]\n\(text)" : tagged
    }

    /// Claude format: "Human: ..." / "Assistant: ..."
    /// If no markers found, treat as single-speaker user text.
    private static func tagClaudeSpeakers(_ text: String) -> String {
        let pattern = #"(?:^|\n)(Human:|Assistant:)\s?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return "[USER]\n\(text)"
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        guard !matches.isEmpty else {
            // No markers — flat copy-paste from Claude web UI
            return "[USER]\n\(text)"
        }

        var tagged = ""
        for (i, match) in matches.enumerated() {
            let markerRange = match.range(at: 1)
            let marker = nsText.substring(with: markerRange)

            let contentStart = match.range.upperBound
            let contentEnd: Int
            if i + 1 < matches.count {
                contentEnd = matches[i + 1].range.location
            } else {
                contentEnd = nsText.length
            }

            let content = nsText.substring(with: NSRange(location: contentStart, length: contentEnd - contentStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if content.isEmpty { continue }

            let tag = marker.hasPrefix("Human") ? "[USER]" : "[ASSISTANT]"
            if !tagged.isEmpty { tagged += "\n" }
            tagged += "\(tag)\n\(content)"
        }

        return tagged.isEmpty ? "[USER]\n\(text)" : tagged
    }

    // MARK: - Step B: Metadata Extraction (NLTagger only)

    /// Extract named entities using NLTagger for SLM priming.
    /// Returns deduplicated entity strings (person names, place names, organization names).
    static func extractPrimingTopics(_ text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        var topics: Set<String> = []
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]

        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                             unit: .word,
                             scheme: .nameType,
                             options: options) { tag, tokenRange in
            guard let tag = tag else { return true }

            switch tag {
            case .personalName, .placeName, .organizationName:
                let entity = String(text[tokenRange])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if entity.count >= 2 {
                    topics.insert(entity)
                }
            default:
                break
            }

            return true
        }

        return Array(topics).sorted()
    }

    // MARK: - Step C: Overlapping Chunks

    /// Split text into overlapping chunks for SLM consumption.
    ///
    /// Each chunk is at most `chunkSize` characters. Consecutive chunks
    /// share `overlapSize` characters so entities near boundaries aren't split.
    ///
    /// - Parameters:
    ///   - text: The full (speaker-tagged) text to chunk.
    ///   - chunkSize: Maximum characters per chunk.
    ///   - overlapSize: Characters shared between consecutive chunks.
    /// - Returns: Array of text chunks. Single-element array if text fits in one chunk.
    static func createOverlappingChunks(_ text: String, chunkSize: Int, overlapSize: Int) -> [String] {
        guard text.count > chunkSize else {
            return [text]
        }

        var chunks: [String] = []
        var startIndex = text.startIndex

        while startIndex < text.endIndex {
            // Calculate end index for this chunk
            let endIndex: String.Index
            if let idx = text.index(startIndex, offsetBy: chunkSize, limitedBy: text.endIndex) {
                endIndex = idx
            } else {
                endIndex = text.endIndex
            }

            let chunk = String(text[startIndex..<endIndex])
            chunks.append(chunk)

            // If we've reached the end, stop
            if endIndex == text.endIndex { break }

            // Advance by (chunkSize - overlapSize) to create overlap
            let advance = chunkSize - overlapSize
            if let nextStart = text.index(startIndex, offsetBy: advance, limitedBy: text.endIndex) {
                startIndex = nextStart
            } else {
                break
            }
        }

        return chunks
    }

    // MARK: - Date Extraction

    /// Attempt to extract a date from the conversation text.
    /// Uses NSDataDetector for natural language date references.
    private static func extractDate(_ text: String) -> Date? {
        // Only scan a reasonable prefix — dates are usually near the top
        let scanPrefix = String(text.prefix(2000))

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }

        let nsText = scanPrefix as NSString
        let results = detector.matches(in: scanPrefix, options: [], range: NSRange(location: 0, length: nsText.length))

        // Return the first detected date
        return results.first?.date
    }
}
