# ContextKey V2 — Research Findings

## 1. Chat Export Format Schemas

### ChatGPT (conversations.json)

**Export method:** Settings > Data Controls > Export Data → zip via email

**IMPORTANT:** The mapping is a TREE, not a flat list. Walk from `current_node` up via `parent` pointers, then reverse.

```json
[
  {
    "title": "Conversation Title",
    "create_time": 1693000000.0,
    "update_time": 1693000500.0,
    "mapping": {
      "<message_uuid>": {
        "id": "<message_uuid>",
        "message": {
          "author": { "role": "user|assistant|system|tool" },
          "create_time": 1693000000.0,
          "content": {
            "content_type": "text|multimodal_text|code|execution_output",
            "parts": ["message text or mixed array"]
          }
        },
        "parent": "<parent_uuid>",
        "children": ["<child_uuid>"]
      }
    },
    "current_node": "<leaf_uuid>",
    "conversation_id": "<uuid>"
  }
]
```

**Content types:**
- `text` → parts is array of strings
- `multimodal_text` → mixed array of strings and image objects
- `code` → Code Interpreter input/output
- `execution_output` → Code Interpreter results

**Image uploads:** Referenced as `asset_pointer: "file-service://file-XXX"` — binary NOT included.
**File uploads:** Same — reference only, no bytes.

---

### Claude (VERIFIED from real export — Feb 2026)

**Export method:** Settings > Account > Export Data → download link via email

**Export contains 4 files:**
- `conversations.json` — all conversations
- `memories.json` — Claude's memory about the user (GOLD MINE for context)
- `projects.json` — project definitions with docs
- `users.json` — account info

**conversations.json structure (VERIFIED):**

```json
[
  {
    "uuid": "<conversation_uuid>",
    "name": "Conversation Title",
    "summary": "",
    "created_at": "2026-02-11T09:08:52.683560Z",
    "updated_at": "2026-02-11T09:08:52.683560Z",
    "account": { "uuid": "<account_uuid>" },
    "chat_messages": [
      {
        "uuid": "<message_uuid>",
        "text": "Message content here",
        "content": [
          {
            "start_timestamp": null,
            "stop_timestamp": null,
            "flags": null,
            "type": "text",       // also: "tool_use"
            "text": "Same content",
            "citations": null
          }
        ],
        "sender": "human|assistant",
        "created_at": "2026-02-11T09:08:52.992325Z",
        "updated_at": "2026-02-11T09:08:52.992325Z",
        "attachments": [],        // image attachments with extracted_content
        "files": []               // uploaded files: {"file_name": "doc.pdf"}
      }
    ]
  }
]
```

**memories.json structure (VERIFIED — extremely valuable):**
```json
[{
  "conversations_memory": "Full structured memory text about the user...",
  "account_uuid": "<uuid>"
}]
```
This contains Claude's own summary of the user — work context, personal context,
top of mind, brief history. This is PRE-EXTRACTED context we can use directly.

**Content types found:** `text`, `tool_use`
**Files:** `{"file_name": "document.pdf"}` — name only, no bytes
**Attachments:** Can contain `extracted_content` for images

**Real stats from test export:** 32 conversations, ~350 total messages across all conversations.

---

### Perplexity (UPDATED — Feb 2026 research)

**Export method:** Per-thread export only (PDF, Markdown, or DOCX). No bulk JSON self-serve export.

**Key findings:**
- Thread-level export via UI button: PDF, Markdown, or DOCX
- NO account-wide bulk JSON export available self-serve
- GDPR/Right to Access requires support/privacy channel request
- Delivered package format for bulk export NOT publicly documented

**Parser strategy:**
1. **Primary:** Parse per-thread Markdown export
2. **Secondary:** PDF/DOCX as lower-fidelity fallback
3. **Future:** Implement guarded JSON adapter that auto-detects unknown structures

**Provisional normalized record:**
```json
{
  "platform": "perplexity",
  "thread_id": "string",
  "thread_title": "string",
  "message_id": "string",
  "role": "user|assistant|system",
  "content": "string",
  "created_at": "ISO-8601|string|nullable",
  "sources": [{"title": "string", "url": "string"}],
  "attachments": [{"name": "string", "type": "string", "path": "string"}]
}
```

**Sources:**
- https://www.perplexity.ai/help-center/en/articles/10354769-what-is-a-thread
- https://www.perplexity.ai/help-center/en/articles/11564568-gdpr-compliance-at-perplexity

---

### Gemini (UPDATED — Feb 2026 research via Google Takeout)

**Export method:** Google Takeout (Gemini Privacy Hub → Export)

**Archive structure:** Zip/tgz archive under `Takeout/` directory with `archive_browser.html`

**Key finding:** Gemini conversations are exported as **My Activity records**, not custom conversation JSON.

**Discovery rules for parser:**
1. Walk zip recursively under `Takeout/`
2. Match files named `MyActivity.json` (and `.html` for fallback)
3. Prioritize paths containing `Gemini` or `Gemini Apps`
4. Parse records as array of My Activity objects

**My Activity JSON schema (Google Data Portability docs):**
```json
{
  "header": "string",
  "title": "string",
  "titleUrl": "string",
  "description": "string",
  "time": "ISO-8601 timestamp",
  "products": ["string"],
  "activityControls": ["string"],
  "subtitles": [{"name": "string", "url": "string"}],
  "details": [{"name": "string", "value": "string"}],
  "attachments": [{"mimeType": "string", "name": "string", "url": "string"}]
}
```

**Message-bearing fields:**
- Timestamp: `time`
- Primary text: `title`, `description`, `details[]`
- Links: `titleUrl`, `subtitles[].url`
- Attachments/media: `attachments[]`
- Product tags: `products[]`, `activityControls[]`

**Confidence:** High on transport/format, Medium on exact file path naming in zip.

**Sources:**
- https://support.google.com/gemini/answer/13594961
- https://support.google.com/accounts/answer/3024190
- https://developers.google.com/data-portability/schema-reference/myactivity

---

## 2. SLM Options for On-Device iOS

### Tier 1: Apple Foundation Models (Primary — iOS 26+)

- **Size:** 0 MB (pre-installed on device, ~3B params estimated)
- **License:** Apple proprietary (free to use via framework)
- **API:** `@Generable` macro for structured output
- **Pros:** Zero app size impact, Neural Engine optimized, official Apple support
- **Cons:** iOS 26+ only, limited context window, English-primary
- **Best for:** Structured extraction via `@Generable` types

### Tier 2: Open-Source SLM Fallback Options

| Model | Size (quantized) | License | iOS Viable | Notes |
|-------|-----------------|---------|------------|-------|
| **Llama 3.2 1B** | ~700MB (Q4) | Llama 3.2 Community | Yes | Best small model for extraction. Meta's latest tiny model. |
| **Llama 3.2 3B** | ~1.8GB (Q4) | Llama 3.2 Community | Yes | Better quality, still fits on modern iPhones |
| **Phi-3 mini (3.8B)** | ~2.2GB (Q4) | MIT | Yes | Strong reasoning, MIT license is cleanest |
| **Gemma 2 2B** | ~1.4GB (Q4) | Gemma license | Yes | Google's small model, good at classification |
| **SmolLM 1.7B** | ~1GB (Q4) | Apache 2.0 | Yes | Smallest viable option, HuggingFace |
| **Qwen 2.5 1.5B** | ~900MB (Q4) | Apache 2.0 | Yes | Strong multilingual, Apache license |

**Recommended for fallback:** Llama 3.2 1B or SmolLM 1.7B
- Both under 1GB quantized
- Can be downloaded on-demand (not bundled)
- Good enough for text extraction tasks

### Tier 3: No Model (NaturalLanguage framework — any iOS)

- Apple's `NaturalLanguage` framework for entity recognition, tokenization
- Pattern matching / regex for structured extraction
- Zero model download, works on any iOS version
- Lower quality but functional

### iOS Inference Frameworks

| Framework | Description | iOS Support |
|-----------|-------------|-------------|
| **MLX Swift** | Apple's ML framework for Apple Silicon | macOS primarily, iOS limited |
| **llama.cpp** | C++ inference, Swift bindings available | iOS yes (via Swift package) |
| **swift-transformers** | HuggingFace's Swift inference library | iOS yes |
| **CoreML** | Apple's ML runtime | iOS yes (convert models via coremltools) |

**Recommended runtime:** `llama.cpp` via Swift package — most mature, widest model support, well-tested on iOS.

### Ranked SLM Recommendations (for on-demand download fallback)

| Rank | Model | Size (INT4) | License | Why |
|------|-------|-------------|---------|-----|
| 1 | **Phi-3.5 mini** | ~2.2GB | MIT | Best extraction quality in 3-4B class, official CoreML weights |
| 2 | **Llama 3.2 3B** | ~1.8GB | Llama Community | Apple co-developed CoreML, excellent quality |
| 3 | **Qwen 2.5 3B** | ~1.8GB | Apache 2.0 | True Apache license, strong at structured JSON output |
| 4 | **Llama 3.2 1B** | ~0.7GB | Llama Community | Ultra-lightweight, decent for simple extraction |
| 5 | **SmolLM2 1.7B** | ~1.0GB | Apache 2.0 | Smallest viable option with acceptable quality |

**Key constraint:** iOS enforces ~2-4GB memory limit for foreground apps. INT4 quantization is essential. Must test on real devices.

**Recommended inference stack:** `llama.cpp` (MIT, broadest model support, Metal GPU acceleration) + `swift-transformers` (tokenizer support)

**Important for lightweight app goal:** These models are NOT bundled — downloaded on-demand only if user opts in. App ships at <25MB with Apple Foundation Models (primary) or NaturalLanguage framework (minimum) handling extraction.

---

## 3. External Inspirations

| App/Tool | Relevant Idea | Applicable to ContextKey? |
|----------|--------------|--------------------------|
| **TypingMind** | "Profiles" for persistent context injection across AI models | Yes — same core concept |
| **Pieces for Developers** | Captures context from workflow, local-first | Yes — local-first philosophy matches |
| **LangChain Memory** | Entity memory, summary memory patterns | Maybe — dedup/merge patterns useful |
| **Obsidian + AI** | Knowledge base that AI can access | Inspiration for context layering |

**Key insight from research:** No existing app does exactly what ContextKey v2 does — import from multiple AI platforms, extract on-device, create a portable identity. The closest are unified frontends (TypingMind) but they require API keys and don't extract context from existing conversations.

---

## 4. Website (nativerse-ventures.com) Current State

- Single-page static site (HTML/CSS/JS, no framework)
- Hosted on Vercel
- Messaging: "Your AI memory. Portable. Private. Instant."
- Shows v1 features (copy-paste workflow, Face ID, profile builder)
- Has email waitlist (Formspree), TestFlight QR code
- Pages: index, beta (redirect to TestFlight), privacy, terms
- Founder: Srinathprasanna, Nativerse Ventures
- **Action needed:** Full messaging rewrite for v2 AFTER app is finalized

---

## 5. Confidence Levels

| Finding | Confidence | Action |
|---------|-----------|--------|
| ChatGPT export format | High | Parser built, awaiting real export |
| Claude export format | **VERIFIED** | Parser built & tested against real 5.5MB export |
| Perplexity export format | Medium | Thread-level Markdown export only, no bulk JSON |
| Gemini export format | Medium-High | Google Takeout My Activity JSON, schema documented |
| Apple Foundation Models API | Medium-High | Verify against latest iOS 26 beta SDK |
| Open-source SLM options | High | Well-documented models |
| Privacy Policy | **DONE** | Saved as PRIVACY_POLICY.md |
