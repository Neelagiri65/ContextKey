# ContextKey V2 — Project Knowledge Base

> This file is the single source of truth for the entire project.
> It survives context compaction. Read this FIRST on every session.

---

## Vision

ContextKey is a **portable, private AI identity** that belongs to the user.
It extracts who you are from your existing AI conversations (or voice, or text),
stores it encrypted on-device, and lets you carry that context into any AI tool.

**Core philosophy:** The app adapts to the user. The user never adapts to the app.

---

## User Journey (3 screens)

### Screen 1: Input (user's choice — all equal)
- **Speak it** — Record a voice note, on-device transcription
- **Import chats** — Upload exports from ChatGPT, Claude, Perplexity, Gemini
- **Type it** — Free-form text entry

### Screen 2: Review
- SLM processes input on-device (Apple Foundation Models)
- Shows extracted context as editable cards
- Each fact attributed: source, date, confidence
- User has final say — keep / edit / discard

### Screen 3: Home
- Your context, displayed cleanly in 3 layers:
  - **Core Identity** (changes rarely): name, expertise, career
  - **Current Context** (changes monthly): job, projects, tech stack
  - **Active Context** (changes daily): current focus, blockers
- **Copy Context** button → FaceID → clipboard
- **Add more context** → back to Screen 1 (any method)

---

## Architecture

### On-Device Only (Zero Cloud Dependency)

All processing uses Apple Neural Engine. No API keys. No token costs. Works offline.

| Framework | Purpose |
|-----------|---------|
| `Speech` | Voice → text transcription |
| `AVFoundation` | Audio recording |
| `FoundationModels` | SLM extraction, classification, dedup (iOS 26) |
| `NaturalLanguage` | Language analysis, entity recognition |
| `Vision` | OCR for images/screenshots in exports |
| `PDFKit` | Text extraction from PDF attachments |
| `LocalAuthentication` | FaceID/TouchID |
| `CryptoKit` | AES-256-GCM encryption |
| `UniformTypeIdentifiers` | File format detection |

### Context Layers

```
Core Identity    → high frequency across chats, stable facts
Current Context  → recent, project-specific, evolving
Active Context   → this week, volatile, session-specific
```

The SLM classifies extracted facts into layers based on frequency, recency, and content type.

### Non-Text Content Handling

| Content Type | Strategy |
|-------------|----------|
| Text messages | Parse directly → SLM |
| Code blocks | Parse as text → SLM identifies tech stack |
| File names & types | Metadata → signals user's domain |
| Image references | Capture surrounding discussion text |
| Expired URLs | Skip gracefully |
| PDFs (if bytes available) | PDFKit → text → SLM |
| Inline images (if base64) | Vision OCR → text → SLM |

---

## File Structure (~12 files)

```
ContextKeyV2/
├── CLAUDE.md                    ← This file (project knowledge base)
├── ContextKeyV2.xcodeproj/
├── ContextKeyV2/
│   ├── ContextKeyV2App.swift    ← Entry point
│   ├── ContentView.swift        ← FaceID gate → router
│   ├── Views/
│   │   ├── InputView.swift      ← 3 equal input methods
│   │   ├── VoiceRecorderView.swift ← Record + live transcription
│   │   ├── ImportView.swift     ← File picker + platform guides
│   │   ├── ProcessingView.swift ← SLM progress + review/edit
│   │   └── HomeView.swift       ← Context display + copy
│   ├── Services/
│   │   ├── ChatParser.swift     ← Parse all 4 platform exports
│   │   ├── ExtractionService.swift ← Foundation Models SLM pipeline
│   │   ├── VoiceService.swift   ← AVFoundation + Speech
│   │   ├── BiometricService.swift ← FaceID wrapper
│   │   └── StorageService.swift ← Encrypted local persistence
│   └── Models/
│       └── ContextModels.swift  ← All data models
├── ContextKeyV2Tests/
│   ├── ChatParserTests.swift
│   ├── ExtractionServiceTests.swift
│   ├── VoiceServiceTests.swift
│   ├── StorageServiceTests.swift
│   └── EndToEndTests.swift
└── TestFixtures/
    ├── chatgpt_sample_export.json
    ├── claude_sample_export.json
    ├── perplexity_sample_export.json
    └── gemini_sample_export.json
```

---

## Test Cases (40 total)

See TESTS.md for the complete test matrix organized by layer:
- Layer 1: File Format Parsing (14 tests)
- Layer 2: SLM Extraction (10 tests)
- Layer 3: Biometric + Copy (5 tests)
- Layer 4: Storage (4 tests)
- Layer 5: Voice (7 tests)
- Layer 6: End-to-End (5 tests)

---

## Versioning Strategy

| Version | What it contains |
|---------|-----------------|
| v0.1.0 | Project scaffold, models, empty screens |
| v0.2.0 | ChatParser (ChatGPT + Claude parsing working) |
| v0.3.0 | ExtractionService (SLM extraction working) |
| v0.4.0 | Voice input (record + transcribe working) |
| v0.5.0 | Full UI wired up (3 screens complete) |
| v0.6.0 | FaceID + encrypted storage |
| v0.7.0 | Manual text input path |
| v0.8.0 | Perplexity + Gemini parsing |
| v0.9.0 | Polish + edge cases |
| v1.0.0 | TestFlight beta release |

Each version = git tag. Each version = testable milestone. Easy rollback.

### Git Branching
- `main` — stable, tagged versions only
- `develop` — integration branch
- `feature/*` — individual features

---

## Beta Testing Strategy

### TestFlight Distribution
- Push v1.0.0 to App Store Connect
- Invite friends & family via TestFlight
- Capture feedback through built-in mechanism

### Feedback Capture (Built into app)
- Simple "Send Feedback" button on Home screen
- Captures: what they were doing, what went wrong, device info
- Stored locally + optional email send
- Each feedback tagged with app version

### Feedback Triage
- Friction points → bug fixes (next patch version)
- Feature requests → evaluate against "does it add value?" principle
- Weight by frequency (multiple users report same issue = priority)

---

## Website (nativerse-ventures.com)

To be updated AFTER app is finalized and tested.
Alignment tasks tracked separately.

---

## Design Principles (Non-Negotiable)

1. **User chooses** — never push one input method over another
2. **On-device only** — no data leaves the device without explicit user action
3. **FaceID is the gate** — single biometric unlock, not a barrier
4. **Add features only if they add maximum value** — when in doubt, leave it out
5. **Testable** — if you can't test it easily, simplify it
6. **Portable** — user's context is THEIR property, exportable, deletable
7. **Works offline** — airplane mode is not an edge case
8. **Lightweight** — app must be small to download (<25MB target). Never bundle large models.

## SLM Strategy (Tiered)

The app must stay lightweight. SLM strategy:

| Tier | Approach | App Size Impact | Availability |
|------|----------|----------------|--------------|
| **Primary** | Apple Foundation Models | 0 MB (pre-installed on device) | iOS 26+ |
| **Fallback** | Open-source SLM (on-demand download) | 0 MB at install, downloads when needed | iOS 17+ |
| **Minimum** | NaturalLanguage framework + heuristics | 0 MB (system framework) | iOS 17+ |

- Primary: Use Apple Foundation Models @Generable for structured extraction (zero cost to app size)
- Fallback: If Apple FM unavailable, offer optional download of a small open-source SLM (user consents)
- Minimum: Basic extraction using Apple NaturalLanguage framework (entity recognition, tokenization)
  + pattern matching. Works on any device, no model needed.

The app ALWAYS works with the Minimum tier. SLM tiers are enhancements, not requirements.

---

## Smart Nudges (Trust Through Value, Not Monitoring)

The app NEVER monitors the user. Instead, we use Apple's OS-level intelligence:
- **App Intents**: "Copy My Context" as Siri/Shortcuts action — iOS learns when to suggest
- **NSUserActivity**: Register activities so iOS predicts usage patterns
- **Siri Suggestions**: iOS surfaces ContextKey at the right time (e.g., before user opens ChatGPT)
- **Live Activities**: Subtle "Context ready" nudge after updates — not a nag

Implementation: Requires App Intents framework + NSUserActivity donation. Add in v0.8.0 or v0.9.0.

## Future: Peer-to-Peer Context Sharing (Post v1.0)

FireChat-style via Apple MultipeerConnectivity framework:
- Bluetooth + WiFi Direct, no internet
- Share context profile with nearby person (interview, collaboration)
- Encrypted, FaceID-gated on both ends
- NOT in v1.0 scope. Revisit after launch + beta feedback.

---

## Mistakes from V1 (Do NOT Repeat)

1. ❌ 43 Swift files — too many to maintain and test
2. ❌ Gamification bolted on — XP/streaks didn't match the use case
3. ❌ 9 profile sub-edit views — over-engineered data entry
4. ❌ Share extension + Widget + Keyboard — too many targets to debug
5. ❌ No proper versioning — couldn't roll back
6. ❌ Lost context during development — no CLAUDE.md, no knowledge base
7. ❌ Tested too late — should have had test cases from the start

---

## Current Status

- [ ] Project scaffold created
- [ ] Research: export formats (in progress)
- [ ] Research: external inspirations (in progress)
- [ ] Research: website current state (in progress)
- [ ] Models defined
- [ ] ChatParser built + tested
- [ ] ExtractionService built + tested
- [ ] VoiceService built + tested
- [ ] UI screens built
- [ ] FaceID + Storage built + tested
- [ ] End-to-end tested
- [ ] TestFlight submitted
- [ ] Beta feedback collected
- [ ] Website updated
