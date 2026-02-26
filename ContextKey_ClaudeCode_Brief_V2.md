# ContextKey — Claude Code Master Brief (Updated)
## 5-Layer Identity Graph Architecture: Builds 18 → 21

---

> **How to use this brief:** Read it completely before writing any code. Every section maps to a specific build. Do not skip ahead. Do not implement Build N+1 before Build N passes all tests. When in doubt, re-read the relevant section rather than inferring intent.

---

## SECTION 0: CURRENT STATE (as of Build 19, TestFlight)

### What has already been built (DO NOT rebuild these)

The following files exist and are committed to main. Do not recreate, do not overwrite:

**Data models — `ContextKeyV2/Models/V2Models.swift`**
- `RawExtraction` — SLM output with full metadata
- `ImportedConversation` — tracks every pasted conversation
- `CanonicalEntity` — deduplicated, merged identity node with `@Relationship(deleteRule: .nullify) var beliefScore: BeliefScore?` and `var citationIds: [UUID]`
- `BeliefScore` — mathematical confidence score
- `ContextCard` — generated output record
- `CitationReference` — URL citations with entity relationships
- `FacetAssignment`, `MergeDecision`, `FacetSnapshot` structs

**Enums — `ContextKeyV2/Models/V2Enums.swift`**
- `EntityType` (8 cases), `AttributionType` (4 cases), `FacetType` (8 cases), `ExtractionStatus` (4 cases), `MergeDecisionType` (2 cases)

**Migration — `ContextKeyV2/Migration/V2Migration.swift`**
- `runV2Migration(existingFacts:modelContext:)` — guarded by `hasRunV2Migration` UserDefaults flag
- `mapPillarToEntityType()`, `mapEntityTypeToFacet(_, sourcePillar:)`, `halfLifeDays(for:)` helpers

**Services — extraction pipeline**
- `ContextKeyV2/Services/ConversationPreProcessor.swift` — speaker tagging, NLTagger metadata, overlapping chunks (8000-char chunks, 2000-char overlap)
- `ContextKeyV2/Services/V2SLMCaller.swift` — SLM caller with retry, timeout, `LanguageModelSessionProtocol` for testability
- `ContextKeyV2/Services/V2PostProcessor.swift` — length filter, entity verification, deduplication, citation URL stub
- `ContextKeyV2/Services/ReconciliationService.swift` — STUB ONLY, reconcile() is no-op
- `ContextKeyV2/Services/ExtractionService.swift` — V2 gate at lines 217-225, existing v1 path unchanged below

**Feature flags — `ContextKeyV2/FeatureFlags.swift`**
- `enhancedExtraction` — controls V2 pipeline (currently toggleable via ... menu in HomeView)

**Tests — 10 passing**
- `V2MigrationTests.swift`, `ConversationPreProcessorTests.swift`, `V2SLMCallerTests.swift`, `V2PostProcessorTests.swift`

### What the user currently sees (the problem)
Raw extracted fact strings with no formatting, no ranking, no narrative. "Uses Swift." "Building ContextKey." These are database contents, not context cards. The user cannot use these directly. This is correct and expected — the narration layer (Build 21) has not been built yet. The remaining builds fix this.

### Product understanding (read before building anything)

**Who uses this and why:**
ContextKey solves a specific daily frustration: AI tools — Claude, ChatGPT, Gemini, Perplexity — each start every conversation with a blank slate. Memory features are either paywalled or platform-locked. A free ChatGPT user has no persistent context whatsoever. A paid Claude user has memory that works only in Claude. Every time a user switches tools, they re-explain themselves from scratch.

ContextKey is the identity layer that sits between the user and every AI tool simultaneously. One paste at the start of any conversation, on any tool, free or paid, and the AI immediately knows who they are.

**The three user moments:**
1. "I'm about to start an AI conversation" — 80% of opens. Needs to be under 5 seconds.
2. "I want to update my context" — 15% of opens. Import a conversation or edit a fact.
3. "I'm curious about my profile" — 5% of opens. Browse and explore.

The entire UI must optimise for Moment 1. Everything else is secondary.

**AI tools already sync across devices:**
Claude.ai, ChatGPT, Gemini all sync conversations in real time across phone and desktop. This means: user pastes context on phone → switches to desktop → context is already there. ContextKey does not need to be a sync layer. It needs to be the context builder. Cross-device sync is a future consideration, not a current requirement.

**Dynamic entities, not static facts:**
A fact string "Uses Swift" is dead. A `CanonicalEntity` for "Swift" that has: 12 corroborating conversations over 8 months, links to 3 Apple documentation citations, connections to the ContextKey project entity and the iOS developer identity entity, a belief score of 0.94 — that is living context an AI can reason with. Every architectural decision must serve this goal.

---

## SECTION 1: DATA MODEL ADDITIONS (Build 18)

The following additions are needed before Build 18 services are implemented. Add these to existing model files without breaking anything.

### 1.1 Add to `BeliefScore`

Add one new field for external citation corroboration:

```swift
var externalCorroboration: Double  // 0.0 to 1.0. Boosted when entity has linked citations from authoritative domains. Default 0.0.
```

This is separate from `attributionWeight` (which tracks how the user stated a fact) and `userFeedbackDelta` (which tracks user actions). External corroboration tracks whether third-party sources back the fact up.

### 1.2 Add to `CanonicalEntity`

```swift
var pendingAliasCandidates: [PendingAliasCandidate]  // Tier B merge candidates awaiting auto-promotion
```

Add `PendingAliasCandidate` as a new struct:

```swift
struct PendingAliasCandidate: Codable {
    var extractionId: UUID
    var candidateEntityId: UUID
    var coOccurrenceCount: Int
    var firstSeen: Date
}
```

### 1.3 Add `hasMergeConflict` flag to `CanonicalEntity`

```swift
var hasMergeConflict: Bool  // True if new data suggests a previous merge may have been wrong. Default false.
```

---

## SECTION 2: CITATION EXTRACTION — COMPLETE IMPLEMENTATION (Build 18)

The `extractCitations` stub in `V2PostProcessor` currently returns an empty array. Build 18 implements it fully.

### 2.1 URL Detection

```swift
func extractCitations(
    from chunk: String, 
    nearEntities: [RawExtractionCandidate],
    conversationId: UUID
) -> [CitationReference] {
    
    // Step 1: Find all URLs in chunk
    let urlPattern = #"https?://[^\s<>"{}|\\^\[\]`]+"#
    let regex = try? NSRegularExpression(pattern: urlPattern)
    let range = NSRange(chunk.startIndex..., in: chunk)
    let matches = regex?.matches(in: chunk, range: range) ?? []
    
    var citations: [CitationReference] = []
    
    for match in matches {
        guard let range = Range(match.range, in: chunk) else { continue }
        let url = String(chunk[range])
        let domain = extractDomain(from: url)
        
        // Step 2: Find entities within 200-char proximity window
        let matchStart = chunk.distance(from: chunk.startIndex, to: range.lowerBound)
        let windowStart = max(0, matchStart - 200)
        let windowEnd = min(chunk.count, matchStart + url.count + 200)
        
        let windowRange = chunk.index(chunk.startIndex, offsetBy: windowStart)..<chunk.index(chunk.startIndex, offsetBy: windowEnd)
        let window = String(chunk[windowRange])
        
        // Step 3: Match entities in window
        let relatedIds = nearEntities.compactMap { candidate -> UUID? in
            let significantWords = candidate.text.lowercased()
                .components(separatedBy: .whitespaces)
                .filter { $0.count > 3 }
            return significantWords.contains { window.lowercased().contains($0) } ? candidate.id : nil
        }
        
        // Step 4: Calculate proximity score (closer = higher score)
        let proximityScore = relatedIds.isEmpty ? 0.1 : 0.5 + (Double(relatedIds.count) * 0.1)
        
        let citation = CitationReference(
            url: url,
            domain: domain,
            title: nil,  // Not fetched — on-device privacy
            citedInConversationId: conversationId,
            relatedEntityIds: relatedIds,
            proximityScore: min(proximityScore, 1.0),
            firstCitedDate: Date(),
            citedCount: 1
        )
        citations.append(citation)
    }
    
    return citations
}

private func extractDomain(from url: String) -> String {
    guard let urlObj = URL(string: url),
          let host = urlObj.host else { return url }
    // Strip www. prefix
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
}
```

### 2.2 Citation Deduplication Across Conversations

When a new citation is created, check if the same URL has been cited before. If yes, increment `citedCount` on the existing record rather than creating a duplicate. Run this check in ReconciliationService after citation extraction.

### 2.3 Citation → BeliefScore Boost

After citation reconciliation, apply external corroboration boost:

```swift
func applyCorroborationBoost(to entityId: UUID, citationDomain: String, modelContext: ModelContext) {
    // Authoritative domains get higher boost
    let authorityDomains: [String: Double] = [
        "developer.apple.com": 0.15,
        "docs.swift.org": 0.15,
        "github.com": 0.10,
        "arxiv.org": 0.12,
        "stackoverflow.com": 0.08,
        "medium.com": 0.05
    ]
    
    let boost = authorityDomains[citationDomain] ?? 0.05
    
    // Fetch BeliefScore for entity, add to externalCorroboration
    // Cap externalCorroboration at 0.3 total
}
```

---

## SECTION 3: RECONCILIATION SERVICE — FULL IMPLEMENTATION (Build 18)

Replace the stub in `ReconciliationService.swift` completely.

### 3.1 Entry Point

```swift
func reconcile(extractions: [RawExtraction], modelContext: ModelContext) async throws {
    // Run in order: citations first, then entity reconciliation
    try await reconcileCitations(from: extractions, modelContext: modelContext)
    try await reconcileEntities(extractions: extractions, modelContext: modelContext)
    try await processPendingAliasCandidates(modelContext: modelContext)
}
```

### 3.2 Entity Reconciliation — Three-Tier Strategy

**Tier A — Exact Match (run first):**

```swift
func tierAMatch(
    extractionText: String, 
    existingEntities: [CanonicalEntity]
) -> CanonicalEntity? {
    let normalised = extractionText.lowercased().trimmingCharacters(in: .whitespaces)
    return existingEntities.first { entity in
        entity.canonicalText.lowercased() == normalised ||
        entity.aliases.contains { $0.lowercased() == normalised }
    }
}
```

On Tier A match:
- Add `RawExtraction.id` to `CanonicalEntity.supportingExtractionIds`
- Update `lastSeenDate`
- Increment support count signal for belief engine
- Do NOT trigger belief recalculation yet — batch at end

**Tier B — Co-occurrence Alias Detection:**

For extractions with no Tier A match:
1. Look at all other extractions from the same `sourceConversationId`
2. Find any `CanonicalEntity` that appears in that conversation's extractions
3. If the new extraction is a generic reference ("my app", "this project", "it", "the tool") AND a named entity appears within 5 messages in the raw conversation:
   - Create or increment a `PendingAliasCandidate`
4. When `PendingAliasCandidate.coOccurrenceCount >= 2`: auto-promote to alias
5. When `coOccurrenceCount == 1` AND entity types match: queue for user review (Tier C)

Generic reference detection:

```swift
func isGenericReference(_ text: String) -> Bool {
    let genericPhrases = ["my app", "this project", "the app", "my project", 
                          "it", "this tool", "the tool", "my work", "this"]
    return genericPhrases.contains(text.lowercased().trimmingCharacters(in: .whitespaces))
}
```

**Tier C — User Review Queue:**

```swift
struct MergeSuggestion: Codable {
    var entityAText: String
    var entityBText: String
    var entityAId: UUID
    var entityBId: UUID
    var suggestedAt: Date
    var snoozedUntil: Date?
}
```

Store pending merge suggestions in UserDefaults (small data, no SwiftData needed).

Rules:
- Max 2 suggestions shown per day
- SKIP → snooze for 7 days
- NO → store `MergeDecision(.kept_separate)`, never suggest again
- YES → merge: add alias, link extractions, store `MergeDecision(.merged)`

**Merge compatibility check (run before ANY merge attempt):**

```swift
func mergeCompatible(_ typeA: EntityType, _ typeB: EntityType) -> Bool {
    let incompatible: Set<Set<EntityType>> = [
        [.skill, .identity],
        [.project, .identity],
        [.tool, .goal],
        [.project, .company]
    ]
    return !incompatible.contains([typeA, typeB])
}
```

### 3.3 Immutability Rule

Once merged, entities stay merged. New data can trigger new merges but never auto-splits. If conflict detected: set `hasMergeConflict = true` and queue for user review.

### 3.4 Batch Processing

Never load all `CanonicalEntity` records at once. Process in batches of 50:

```swift
for batch in extractions.chunked(into: 50) {
    let entityTexts = Set(batch.map { $0.text.lowercased() })
    // Fetch only entities relevant to this batch
    // Process batch
    // Save
}
```

### 3.5 Build 18 Test Suite

All tests must pass before proceeding to Build 19:

- [ ] Tier A: importing same fact twice creates only one CanonicalEntity
- [ ] Tier A: importing alias of existing entity links to existing entity, not creates new
- [ ] Tier B: "my app" + "ContextKey" in same conversation creates PendingAliasCandidate
- [ ] Tier B: same pair in second conversation auto-promotes to alias
- [ ] Tier C: merge suggestion queues correctly, max 2 per day enforced
- [ ] Tier C: YES decision merges entities, NO decision prevents future suggestion
- [ ] Type incompatibility: skill + identity never suggested as merge candidates
- [ ] Citation deduplication: same URL in two conversations increments citedCount, not duplicates
- [ ] Batch constraint: reconciliation of 200 extractions never loads all CanonicalEntities at once
- [ ] Immutability: merged entities cannot be auto-split by new data

---

## SECTION 4: BELIEF ENGINE — FULL IMPLEMENTATION (Build 19)

### 4.1 The Formula

```swift
func calculateBeliefScore(for entity: CanonicalEntity, score: BeliefScore) -> Double {
    
    // 1. Support factor (logarithmically dampened, per-conversation capped)
    let supportFactor = log(1.0 + Double(score.supportCount))
    
    // 2. Recency factor (exponential decay with entity-type-specific half-life)
    let daysSince = Date().timeIntervalSince(score.lastCorroboratedDate) / 86400.0
    let recencyFactor = pow(0.5, daysSince / score.halfLifeDays)
    
    // 3. Attribution weight
    let attributionWeights: [AttributionType: Double] = [
        .userExplicit: 1.0, .userImplied: 0.7,
        .assistantSuggested: 0.2, .ambiguous: 0.1
    ]
    let attributionWeight = attributionWeights[
        entity.supportingExtractionIds.isEmpty ? .ambiguous : .userExplicit
    ] ?? 0.1
    
    // 4. External corroboration (from citations)
    let corroborationBoost = min(score.externalCorroboration, 0.3)
    
    // 5. User feedback delta
    let feedbackDelta = min(score.userFeedbackDelta, 0.3)
    
    // 6. Base confidence
    let baseConfidence = 0.5  // Default — refined by extraction quality
    
    // 7. Raw score
    let rawScore = baseConfidence 
        * (supportFactor / 5.0) 
        * recencyFactor 
        * attributionWeight 
        + corroborationBoost 
        + feedbackDelta
    
    // 8. Stability floor
    let floor = score.stabilityFloorActive ? 0.4 : 0.0
    
    return min(max(rawScore, floor), 1.0)
}
```

### 4.2 Half-Life Values (unchanged from brief)

```swift
static let halfLifeByType: [EntityType: Double] = [
    .identity: 730.0, .capability: 180.0, .project: 90.0,
    .preference: 365.0, .context: 14.0, .goal: 180.0,
    .domain: 365.0, .tool: 180.0, .skill: 180.0
]
```

### 4.3 Implicit Feedback Signals

```swift
enum UserFeedbackSignal {
    case copiedFact         // +0.15
    case longPressedCard    // +0.15 (new — long press = intent to use)
    case includedInCard     // +0.20
    case contextCardCopied  // +0.10 per entity in copied card
    case viewedThreeTimes   // +0.05
    case explicitConfirm    // +0.25
    case explicitDismiss    // -0.40
}
```

Note: `longPressedCard` is new — corresponds to the long-press copy interaction in Build 21 UI.

### 4.4 Visibility Threshold

Only entities with `BeliefScore.currentScore >= 0.45` appear in the UI. Entities below threshold exist in the database but are hidden. They re-emerge if new corroboration arrives.

### 4.5 When to Run

- On import completion: recalculate affected entities only
- On user feedback: recalculate single entity immediately
- On app open if >24h since last run: decay-only pass, skip if change < 0.05
- Never in background

### 4.6 Build 19 Test Suite

- [ ] Entity with supportCount=1, daysSince=0, attribution=.userExplicit → score > 0.5
- [ ] Same entity after 1 half-life → score approximately halved
- [ ] Entity with supportCount >= 3 → stabilityFloorActive = true → score never < 0.4
- [ ] Entity with 200 support count → score not dramatically higher than entity with 20 (log dampening)
- [ ] Context type entity last seen 30 days ago → score < 0.15 (14-day half-life)
- [ ] Identity type entity last seen 30 days ago → score > 0.70 (730-day half-life)
- [ ] Long press signal → belief score increases by ~0.15
- [ ] Explicit dismiss → belief score decreases by 0.40
- [ ] Entity with 3 linked authoritative citations → externalCorroboration > 0
- [ ] Belief engine recalculation on app open after 24h → scores updated
- [ ] Home screen sorted by belief score descending after Build 19

---

## SECTION 5: FACET FORMATION (Build 20)

### 5.1 Entity Type → Facet Assignment Map (unchanged)

```swift
static let entityTypeToFacets: [EntityType: [(FacetType, Double)]] = [
    .skill:      [(.technicalCapability, 1.0), (.professionalIdentity, 0.3)],
    .tool:       [(.technicalCapability, 0.9), (.currentContext, 0.2)],
    .project:    [(.activeProjects, 1.0), (.currentContext, 0.5)],
    .goal:       [(.goalsMotivations, 1.0), (.currentContext, 0.4)],
    .preference: [(.workingStyle, 1.0), (.valuesConstraints, 0.3)],
    .identity:   [(.professionalIdentity, 1.0)],
    .context:    [(.currentContext, 1.0), (.activeProjects, 0.3)],
    .domain:     [(.domainKnowledge, 1.0), (.professionalIdentity, 0.3)]
]
```

### 5.2 Facet Visibility Rule

Show a facet only if it has >= 2 entities with beliefScore >= 0.45. Empty facets are hidden with a gentle prompt: "Import a conversation about [facet topic] to enrich your profile."

### 5.3 Build 20 Test Suite

- [ ] Facet with 0 entities → not shown
- [ ] Facet with 1 entity → not shown
- [ ] Facet with 2+ entities above threshold → shown
- [ ] Skill entity appears in technicalCapability facet (primary)
- [ ] Constraints pillar facts appear in valuesConstraints facet (not workingStyle)

---

## SECTION 6: CONTEXT CARD NARRATION (Build 21)

This is the hero feature. Everything built in Builds 18-20 feeds into this.

### 6.1 Interaction Model (CRITICAL — implement exactly as specified)

- **Single tap** on a persona card → opens edit mode for that card's entities
- **Long press** on a persona card → silent copy to clipboard with haptic feedback (UIImpactFeedbackGenerator, .medium weight). No alert, no confirmation. Just copy and a subtle haptic.
- **Tap AI tool icon** (Claude, ChatGPT, Perplexity, Gemini) → pastes the most recently long-pressed card into that tool and opens the app via URL scheme. If no card has been long-pressed in this session, copies the default Quick card first.

### 6.2 Platform-Specific Card Architecture

Each AI tool gets a different card composition from the same underlying entity graph:

**Claude card:**
```
[Developer Identity facet — top 3 entities]
[Technical Capability facet — top 5 entities]  
[Active Projects facet — top 2 entities]
[Working Style facet — top 2 entities]
Format: Natural prose. No headers. ~150 words.
```

**ChatGPT card:**
```
[Professional Identity facet — top 3 entities]
[Goals & Motivations facet — top 3 entities]
[Values & Constraints facet — top 2 entities]
[Working Style facet — top 2 entities]
Format: Structured with plain text headers. ~200 words.
```

**Perplexity card:**
```
[Domain Knowledge facet — top 4 entities]
[Active Projects facet — top 2 entities]
[Top 3 citation domains from CitationReference]
Format: Compact, factual. Max 120 words.
Note: Include top citation domains because Perplexity 
is a research tool — telling it what sources you've 
already consulted prevents redundant retrieval.
```

**Gemini card:**
```
[Professional Identity facet — top 3 entities]
[Technical Capability facet — top 3 entities]
[Goals & Motivations facet — top 2 entities]
Format: Concise structured text. ~150 words.
```

### 6.3 Template-Based Generation (v1 — no SLM)

Do NOT use the SLM for narration in Build 21. Use deterministic templates. This prevents hallucination and ensures every sentence in the card traces to a real entity.

```swift
func generateCard(for platform: Platform, facets: [FacetType: [CanonicalEntity]]) -> String {
    switch platform {
    case .claude:
        return generateClaudeCard(facets: facets)
    case .chatgpt:
        return generateChatGPTCard(facets: facets)
    case .perplexity:
        return generatePerplexityCard(facets: facets)
    case .gemini:
        return generateGeminiCard(facets: facets)
    case .manual:
        return generateDefaultCard(facets: facets)
    }
}
```

Each platform generator reads the top-scored entities from its assigned facets and fills a natural language template. No SLM involvement. Every output word maps directly to an entity.

### 6.4 Card Quality Validation

After generation, verify every substantive claim in the card maps to a `CanonicalEntity` with `beliefScore >= 0.45`. If any claim cannot be traced: remove it. Never show a claim that isn't backed by a real, scored entity.

```swift
func validateCard(_ cardText: String, against entities: [CanonicalEntity]) -> String {
    // For v1 (template-based): this always passes because templates only include entities
    // For v2 (SLM narration): implement claim extraction and verification
    return cardText
}
```

### 6.5 Citation Domains on Cards

For Perplexity cards specifically, append a citation section:

```swift
func topCitationDomains(limit: Int = 3) -> [String] {
    // Fetch all CitationReference objects
    // Group by domain, sum citedCount
    // Return top N by total count
}
```

Format on card: "Sources I've already consulted: developer.apple.com, docs.swift.org, github.com/apple"

### 6.6 URL Schemes for AI Tool Integration

```swift
static let urlSchemes: [Platform: String] = [
    .claude:      "claude://",
    .chatgpt:     "chatgpt://",
    .perplexity:  "perplexity://",
    .gemini:      "gemini://"
]

// Fallback to web URLs if app not installed:
static let webURLs: [Platform: String] = [
    .claude:      "https://claude.ai",
    .chatgpt:     "https://chat.openai.com",
    .perplexity:  "https://www.perplexity.ai",
    .gemini:      "https://gemini.google.com"
]
```

When user taps an AI tool icon:
1. Copy the relevant card to clipboard
2. Apply haptic feedback
3. Try to open via URL scheme
4. If URL scheme fails (app not installed): open web URL in Safari

### 6.7 App Connection Bar

Update the home screen AI tool bar to include all four tools:
- Claude (existing)
- ChatGPT (existing)  
- Perplexity (ADD)
- Gemini (ADD)

Each icon shows a subtle indicator if the user has imported conversations from that platform.

### 6.8 Build 21 Test Suite

- [ ] Long press on persona card → clipboard contains card text → haptic fires
- [ ] Single tap on persona card → edit mode opens
- [ ] Tap Claude icon → clipboard contains Claude-formatted card → claude:// URL opens
- [ ] Tap ChatGPT icon → clipboard contains ChatGPT-formatted card
- [ ] Tap Perplexity icon → card contains citation domains section
- [ ] Tap Gemini icon → clipboard contains Gemini-formatted card
- [ ] Claude card is natural prose, no markdown headers
- [ ] ChatGPT card has plain text section headers
- [ ] Perplexity card is <= 120 words
- [ ] Every claim in every card traces to a CanonicalEntity with score >= 0.45
- [ ] If AI app not installed: web URL opens in Safari
- [ ] Card regenerates when user switches platform selection
- [ ] Long press signal applies +0.15 belief boost to all entities in the copied card

---

## SECTION 7: HOME SCREEN REDESIGN (Build 21)

### 7.1 Layout Hierarchy

The home screen must reflect the product's purpose. Current state: 7 pillar cards of equal weight. Target state:

```
┌─────────────────────────────────┐
│  [Name] — [Role]                │  ← Identity headline (from professionalIdentity facet)
│  Last updated: [X] days ago     │  ← Freshness indicator
│                                 │
│  ┌─────────┐ ┌─────────┐        │  ← Persona cards (tap=edit, long press=copy)
│  │ Claude  │ │ChatGPT  │        │
│  │  card   │ │  card   │        │
│  └─────────┘ └─────────┘        │
│  ┌─────────┐ ┌─────────┐        │
│  │Perplexty│ │ Gemini  │        │
│  │  card   │ │  card   │        │
│  └─────────┘ └─────────┘        │
│                                 │
│  [Claude] [ChatGPT] [Perplexity] [Gemini]  │  ← Tap to copy+open
│                                 │
│  ▼ Your Identity Details        │  ← Collapsed by default
│  [Facet cards scroll below]     │
└─────────────────────────────────┘
```

### 7.2 Freshness Indicator

```swift
func freshnessLabel(lastUpdated: Date) -> (String, Color) {
    let days = Calendar.current.dateComponents([.day], from: lastUpdated, to: Date()).day ?? 0
    switch days {
    case 0...7:   return ("Updated recently", .green)
    case 8...30:  return ("Updated \(days) days ago", .yellow)
    default:      return ("Getting stale — import a recent conversation", .orange)
    }
}
```

### 7.3 Profile Completeness

Show a subtle completeness indicator — not a progress bar, just a line:

"6 of 8 identity dimensions populated"

Tapping it shows which facets are empty and suggests what kind of conversation to import to fill them.

---

## SECTION 8: MIGRATION WIRING (Build 18)

The migration function exists but is not wired to app launch. Wire it in Build 18.

In `ContextKeyV2App.swift`, in the `init()` or `onAppear` of the root view:

```swift
Task {
    guard !UserDefaults.standard.bool(forKey: "hasRunV2Migration") else { return }
    
    do {
        let profile = try storageService.loadProfile()
        let context = modelContainer.mainContext
        try runV2Migration(existingFacts: profile.facts, modelContext: context)
    } catch {
        // Migration failure is non-fatal — log and continue
        // User's existing data is safe in the old storage layer
        print("[V2Migration] Failed: \(error). Old data preserved.")
    }
}
```

Show a brief spinner ("Upgrading your profile...") during migration. Hide it when done or on failure. Never block app launch.

---

## SECTION 9: ERROR HANDLING MATRIX (all builds)

| Scenario | Required Response |
|---|---|
| Apple Intelligence unavailable | Fall back to NLTagger, show "Basic extraction mode" indicator |
| SLM returns invalid JSON | Retry once, then return empty array, log chunk ID |
| SLM timeout >30s | Skip chunk, continue with remaining chunks, mark ImportedConversation as partial |
| SwiftData migration fails | Log error, continue with old data, never block launch |
| Reconciliation crash | Leave RawExtractions orphaned (not lost), retry on next import |
| Belief engine returns NaN | Clamp to 0.5, log entity ID and offending values |
| No populated facets | Show empty state: "Import a conversation to build your context" |
| Card generation produces empty string | Show fallback: "Import more conversations to generate your context card" |
| AI app URL scheme fails | Open web URL in Safari silently |
| Long press copy fails | Show brief error toast: "Copy failed — try again" |

---

## SECTION 10: PERFORMANCE CONSTRAINTS (all builds)

| Operation | Hard Limit |
|---|---|
| App launch to first contentful render | < 500ms |
| Home screen load with cards | < 200ms |
| Single belief score recalculation | < 5ms |
| Full belief engine run (100 entities) | < 500ms |
| Context card generation (template) | < 100ms |
| Long press to haptic + copy | < 50ms (must feel instant) |
| Tap AI icon to app open | < 200ms |
| Reconciliation of 50 extractions | < 2 seconds |
| Migration (all existing facts) | < 5 seconds (show spinner) |

---

## SECTION 11: DO NOT BUILD IN BUILDS 18-21

- ❌ SLM-based free-form narration (template narration must be validated first)
- ❌ Cloud sync or iCloud backup
- ❌ Browser extension (future product)
- ❌ QR code cross-device relay
- ❌ Fetching/scraping citation URLs (store reference only)
- ❌ Semantic search (NLEmbedding — save for later)
- ❌ Multiple profiles
- ❌ Sharing context cards with other users
- ❌ Export to PDF or markdown
- ❌ Widget or Live Activity
- ❌ Any external API calls

---

## SECTION 12: BUILD SEQUENCE SUMMARY

```
Build 18 (current):
  - Wire V2 migration to app launch
  - Full ReconciliationService (Tier A, B, C)
  - Full citation extraction (Section 2)
  - Citation deduplication and corroboration boost
  - Add BeliefScore.externalCorroboration field
  - All 10 reconciliation tests pass
  - Commit + TestFlight

Build 19:
  - Full BeliefEngine implementation
  - Home screen sorted by belief score
  - Facts below 0.45 hidden
  - Implicit feedback signals wired
  - All 11 belief engine tests pass
  - Commit + TestFlight

Build 20:
  - FacetService implementation
  - Onboarding shows live card preview (card builds as user answers)
  - Facet cards replace pillar cards
  - Empty facet handling with contextual prompts
  - All 5 facet tests pass
  - Commit + TestFlight

Build 21:
  - NarrationService (template-based)
  - Home screen redesign (Section 7)
  - Platform-specific persona cards (Section 6.2)
  - Long press = copy, tap = edit, icon tap = paste+open
  - Perplexity and Gemini added to app bar
  - Citation domains on Perplexity cards
  - All 13 Build 21 tests pass
  - Commit + TestFlight
```

---

## SECTION 13: DEFINITION OF COMPLETE

This brief is complete when:

1. A user opens ContextKey, pastes a conversation from any AI tool, and sees a persona card generated for that tool within 30 seconds
2. Long pressing a Claude card copies natural prose context ready to paste into Claude
3. Long pressing a ChatGPT card copies structured context formatted for ChatGPT Custom Instructions
4. Long pressing a Perplexity card copies compact research-oriented context including citation domains
5. Tapping the Claude icon copies the Claude card and opens the Claude app in one action
6. After 3-5 imports over 1-2 weeks, the cards stabilise and accurately reflect who the user is without them manually curating anything
7. Facts that are no longer relevant (old projects, stale context) naturally fade from the cards through belief decay without the user deleting anything
8. All 44 test items across Builds 18-21 pass
9. No crash occurs under any scenario in Section 9
10. All performance limits in Section 10 are met

---

*Updated brief — incorporates all product discussions including citation architecture, platform-specific card design, interaction model, dynamic entity philosophy, and market positioning.*
