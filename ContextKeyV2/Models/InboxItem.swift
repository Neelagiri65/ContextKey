import Foundation

// MARK: - Ingest Method

/// How content entered ContextKey
enum IngestMethod: String, Codable, Sendable {
    case fileImport    // User imported a file (JSON/ZIP export from AI tool)
    case clipboard     // User pasted from clipboard
    case manual        // User typed directly
    case onboarding    // Entered during onboarding flow
}

// MARK: - Import Mode

/// Controls how imported content affects belief scores.
/// Prevents old bulk dumps from overwhelming recent context.
enum ImportMode: String, Codable, Sendable {
    case backfill   // Lower recency impact — historical data
    case active     // Normal scoring — recent/live data

    var displayName: String {
        switch self {
        case .backfill: return "Backfill"
        case .active: return "Active"
        }
    }

    var description: String {
        switch self {
        case .backfill: return "Older history — won't overpower your current context"
        case .active: return "Recent conversations — normal impact on your profile"
        }
    }
}

// MARK: - Privacy Mode

/// Controls whether raw source text is retained
enum PrivacyMode: String, Codable, Sendable {
    case storeRaw       // Keep encrypted raw text for re-analysis and evidence
    case derivedOnly    // Only keep extracted facts, discard source text
}

// MARK: - Inbox Status

/// Processing lifecycle of an InboxItem
enum InboxStatus: String, Codable, Sendable {
    case pending      // Received but not yet processed
    case processing   // Currently being analyzed by extraction pipeline
    case processed    // Extraction complete, MemoryItems created
    case archived     // Done, can be cleaned up (raw text retained per privacy mode)
    case failed       // Extraction failed — can be retried
}

// MARK: - Inbox Item

/// A normalized container for any content entering ContextKey.
/// All input channels (import, clipboard, manual, onboarding) produce InboxItems.
/// This is the single entry point to the extraction → belief → persona pipeline.
struct InboxItem: Identifiable, Codable, Sendable {
    let id: UUID

    // --- Source ---
    var source: Platform              // Which AI tool this came from
    var ingestMethod: IngestMethod    // How it entered ContextKey
    var importMode: ImportMode        // Backfill or Active scoring

    // --- Content ---
    /// Encrypted raw text (nil when privacyMode == .derivedOnly or after cleanup)
    var rawTextCiphertext: Data?
    /// Schema version for the encrypted content (future-proofing for format changes)
    var rawTextSchemaVersion: Int?

    // --- Privacy ---
    var privacyMode: PrivacyMode

    // --- User hints ---
    /// User's suggested space for items extracted from this content (optional)
    var assignedSpace: SpaceID?

    // --- Lifecycle ---
    var status: InboxStatus
    var timestamp: Date               // When the source content was created/imported

    // --- Metadata ---
    var conversationCount: Int        // Number of conversations in this inbox item (for file imports)
    var messageCount: Int             // Total messages across conversations
    var extractedItemCount: Int       // How many MemoryItems were created from this

    // --- Error tracking ---
    var lastError: String?            // Last error message if status == .failed

    init(
        source: Platform,
        ingestMethod: IngestMethod,
        importMode: ImportMode = .active,
        rawTextCiphertext: Data? = nil,
        rawTextSchemaVersion: Int? = nil,
        privacyMode: PrivacyMode = .storeRaw,
        assignedSpace: SpaceID? = nil,
        timestamp: Date = Date(),
        conversationCount: Int = 0,
        messageCount: Int = 0
    ) {
        self.id = UUID()
        self.source = source
        self.ingestMethod = ingestMethod
        self.importMode = importMode
        self.rawTextCiphertext = rawTextCiphertext
        self.rawTextSchemaVersion = rawTextSchemaVersion
        self.privacyMode = privacyMode
        self.assignedSpace = assignedSpace
        self.status = .pending
        self.timestamp = timestamp
        self.conversationCount = conversationCount
        self.messageCount = messageCount
        self.extractedItemCount = 0
        self.lastError = nil
    }
}

// MARK: - Import Mode Auto-Detection

extension ImportMode {
    /// Auto-detect whether an import should be Backfill or Active
    /// based on the date distribution of the content.
    ///
    /// Heuristic:
    /// - If >=80% of messages are older than 30 days → Backfill
    /// - If >=60% of messages are within 30 days → Active
    /// - Otherwise → Backfill (safer default)
    static func autoDetect(messageDates: [Date], referenceDays: Int = 30) -> ImportMode {
        guard !messageDates.isEmpty else { return .backfill }

        let cutoff = Calendar.current.date(byAdding: .day, value: -referenceDays, to: Date()) ?? Date()
        let recentCount = messageDates.filter { $0 >= cutoff }.count
        let recentRatio = Double(recentCount) / Double(messageDates.count)

        if recentRatio >= 0.6 {
            return .active
        } else {
            return .backfill
        }
    }
}
