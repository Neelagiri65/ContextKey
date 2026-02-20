# ContextKey V2 — Test Matrix

## Layer 1: File Format Parsing (14 tests)

### TEST-PARSE-001: Parse ChatGPT conversations.json with 1 conversation
- **Given:** A valid ChatGPT export with 1 simple text-only conversation
- **When:** ChatParser.parseChatGPT(data:) is called
- **Then:** Returns 1 Conversation with correct title, timestamp, messages

### TEST-PARSE-002: Parse ChatGPT export with 100+ conversations
- **Given:** A real-sized ChatGPT export
- **When:** Parser is called
- **Then:** All conversations parsed, no crashes, completes in <5s

### TEST-PARSE-003: Parse ChatGPT conversation with image upload references
- **Given:** A conversation where user uploaded images
- **When:** Parser encounters image metadata
- **Then:** Extracts file type as "image", captures surrounding message text, no crash on missing bytes

### TEST-PARSE-004: Parse ChatGPT conversation with code interpreter output
- **Given:** A conversation with code execution blocks
- **When:** Parser encounters code blocks
- **Then:** Extracts code as text content, identifies language if present

### TEST-PARSE-005: Parse ChatGPT conversation with PDF/file upload
- **Given:** A conversation where user uploaded a document
- **When:** Parser encounters file metadata
- **Then:** Extracts filename, file type, and surrounding discussion text

### TEST-PARSE-006: Parse Claude export JSON with text conversations
- **Given:** A valid Claude data export
- **When:** ChatParser.parseClaude(data:) is called
- **Then:** Returns conversations with correct structure

### TEST-PARSE-007: Parse Claude export with artifacts (code, documents)
- **Given:** A Claude export containing artifact blocks
- **When:** Parser encounters artifacts
- **Then:** Extracts artifact content as text, tags artifact type

### TEST-PARSE-008: Parse Claude export with image uploads
- **Given:** A Claude conversation with uploaded images
- **When:** Parser encounters image references
- **Then:** Captures surrounding text, logs image metadata, no crash

### TEST-PARSE-009: Parse Perplexity export
- **Given:** A Perplexity data export
- **When:** ChatParser.parsePerplexity(data:) is called
- **Then:** Extracts search queries, AI responses, and citation URLs

### TEST-PARSE-010: Parse Gemini Takeout export
- **Given:** A Google Takeout Gemini export
- **When:** ChatParser.parseGemini(data:) is called
- **Then:** Extracts conversations with correct structure

### TEST-PARSE-011: Handle corrupted/malformed JSON gracefully
- **Given:** An invalid or truncated JSON file
- **When:** Any parser is called
- **Then:** Returns a clear ParseError, no crash

### TEST-PARSE-012: Handle empty export file
- **Given:** A valid JSON but with 0 conversations
- **When:** Parser is called
- **Then:** Returns empty array, UI shows "No conversations found"

### TEST-PARSE-013: Handle mixed content conversation
- **Given:** A conversation with text + image + code + file upload
- **When:** Parser is called
- **Then:** All content types extracted appropriately, nothing lost

### TEST-PARSE-014: File type detection from picker
- **Given:** User picks a .json, .zip, or .tar.gz file
- **When:** App receives the file
- **Then:** Routes through correct parser based on platform selection

---

## Layer 2: SLM Extraction (10 tests)

### TEST-SLM-001: Extract identity from simple conversation
- **Given:** A conversation where user says "I'm a senior iOS developer"
- **When:** ExtractionService processes it
- **Then:** ExtractedContext.role == "Senior iOS Developer"

### TEST-SLM-002: Extract skills from technical conversation
- **Given:** A conversation discussing SwiftUI, Core Data, and Combine
- **When:** ExtractionService processes it
- **Then:** ExtractedContext.skills contains ["SwiftUI", "Core Data", "Combine"]

### TEST-SLM-003: Extract projects from conversation
- **Given:** A conversation about "building a fitness tracking app"
- **When:** ExtractionService processes it
- **Then:** ExtractedContext.projects contains a project mention

### TEST-SLM-004: Extract preferences from conversation
- **Given:** User says "I prefer concise answers with code examples"
- **When:** ExtractionService processes it
- **Then:** ExtractedContext.preferences captures this

### TEST-SLM-005: Handle conversation with no extractable context
- **Given:** A trivial conversation ("What's the weather?")
- **When:** ExtractionService processes it
- **Then:** Returns empty/minimal ExtractedContext, no crash

### TEST-SLM-006: Process multiple conversations and deduplicate
- **Given:** 50 conversations where user mentions "SwiftUI" in 30 of them
- **When:** ExtractionService processes all and deduplicates
- **Then:** "SwiftUI" appears once with high confidence + attribution count

### TEST-SLM-007: Handle conflicting information across conversations
- **Given:** User says "I'm a designer" in Jan, "I'm a product manager" in Dec
- **When:** ExtractionService processes both
- **Then:** Most recent role is primary, older role noted as previous

### TEST-SLM-008: Attribute extracted context to source
- **Given:** Context extracted from a Claude conversation
- **When:** Extraction completes
- **Then:** Each fact has source_platform, conversation_count, last_seen_date

### TEST-SLM-009: Process conversation with code blocks
- **Given:** A conversation full of Python code
- **When:** ExtractionService processes it
- **Then:** Identifies "Python" as a skill, extracts project context

### TEST-SLM-010: SLM processing stays within resource bounds
- **Given:** 500 conversations totaling 2MB of text
- **When:** Full extraction pipeline runs
- **Then:** Completes within 60s, memory under 200MB, no UI freeze

---

## Layer 3: Biometric + Copy (5 tests)

### TEST-BIO-001: FaceID gates app access on launch
- **Given:** App is opened after background
- **When:** App launches
- **Then:** FaceID prompt before any content is shown

### TEST-BIO-002: FaceID gates copy action
- **Given:** User taps "Copy Context"
- **When:** FaceID triggered
- **Then:** Context copied only after successful auth

### TEST-BIO-003: FaceID failure shows retry
- **Given:** FaceID fails
- **When:** Auth fails
- **Then:** "Try Again" button, clipboard NOT modified

### TEST-BIO-004: Fallback to passcode
- **Given:** Device without FaceID
- **When:** Auth needed
- **Then:** Falls back to device passcode

### TEST-BIO-005: Copied text is well-formatted for AI consumption
- **Given:** User has extracted context
- **When:** Context is copied
- **Then:** Clipboard contains structured text that works as first message to any AI

---

## Layer 4: Storage (4 tests)

### TEST-STORE-001: Save extracted context encrypted
- **Given:** Extraction complete
- **When:** User taps Save
- **Then:** Persisted with AES-256-GCM encryption

### TEST-STORE-002: Load context on app relaunch
- **Given:** Context previously saved
- **When:** App relaunches → FaceID succeeds
- **Then:** Home screen shows saved context

### TEST-STORE-003: Re-import merges with existing
- **Given:** User imports new chats with existing context
- **When:** New extraction completes
- **Then:** New data merges (deduped), user reviews

### TEST-STORE-004: Delete all data
- **Given:** User wants to wipe data
- **When:** "Delete All Data" with confirmation
- **Then:** All stored context permanently erased

---

## Layer 5: Voice (7 tests)

### TEST-VOICE-001: Record and transcribe voice input
- **Given:** User taps record and speaks for 30 seconds
- **When:** Recording stops
- **Then:** On-device transcription returns accurate text

### TEST-VOICE-002: SLM extracts context from voice transcript
- **Given:** Transcribed text "I'm a designer working on a fitness app"
- **When:** ExtractionService processes it
- **Then:** Role, project, and skills extracted correctly

### TEST-VOICE-003: Voice works offline
- **Given:** Device in airplane mode
- **When:** User records and processes voice
- **Then:** Transcription and extraction both work

### TEST-VOICE-004: Voice-to-intent combines stored context + new request
- **Given:** Stored context + user speaks "help me with SwiftUI layouts"
- **When:** App processes voice intent
- **Then:** Output combines full profile + specific request

### TEST-VOICE-005: Live transcription shows text as user speaks
- **Given:** User is recording
- **When:** Words are spoken
- **Then:** Text appears in real-time on screen

### TEST-VOICE-006: Handle background noise gracefully
- **Given:** Noisy environment
- **When:** Speech recognition confidence is low
- **Then:** Flags low-confidence segments for user review

### TEST-VOICE-007: Support long recordings (up to 5 minutes)
- **Given:** User speaks for 5 minutes
- **When:** Recording completes
- **Then:** Full transcription processed without memory issues

---

## Layer 6: End-to-End (5 tests)

### TEST-E2E-001: Full flow — ChatGPT import to copy
- **Given:** A real ChatGPT export file
- **When:** Import → SLM → review → save → copy
- **Then:** Clipboard contains meaningful context summary

### TEST-E2E-002: Full flow — Claude import to copy
- **Given:** A real Claude export file
- **When:** Same flow
- **Then:** Same result

### TEST-E2E-003: Multi-platform import
- **Given:** Both ChatGPT AND Claude exports
- **When:** Both processed
- **Then:** Context merged, deduplicated, attributed to both

### TEST-E2E-004: Copied context improves AI response
- **Given:** Context copied from ContextKey
- **When:** Pasted as first message in ChatGPT/Claude
- **Then:** AI acknowledges context, responds accordingly (manual)

### TEST-E2E-005: App works fully offline
- **Given:** No internet connection
- **When:** User imports, processes, copies
- **Then:** Everything works (on-device SLM, local storage)
