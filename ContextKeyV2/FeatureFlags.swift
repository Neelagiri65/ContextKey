import Foundation

// MARK: - Feature Flags

/// Compile-time feature flags for gating unstable features.
/// Set to `false` to disable a feature entirely — no UI, no background tasks.
struct FeatureFlags {
    /// Voice transcription (Speech + AVFoundation). Disabled due to iOS 26 beta instability.
    static let voiceTranscribeEnabled = false

    /// Note Builder — clipboard-like collector for facts to paste into AI tools.
    static let noteBuilderEnabled = true

    /// V2 enhanced extraction pipeline (Section 2.3+). When false, V2SLMCaller.call()
    /// throws modelUnavailable and the existing v1 extraction path runs unchanged.
    static let v2EnhancedExtraction = false
}
