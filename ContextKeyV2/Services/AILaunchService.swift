import UIKit

// MARK: - AI Launch Service (Build 21 — Section 6.6)

/// Handles copying context cards to clipboard and launching AI tool apps.
/// Pure service layer — no UI.
enum AILaunchService {

    // MARK: - 6.6 URL Schemes

    static let urlSchemes: [Platform: String] = [
        .claude:     "claude://",
        .chatgpt:    "chatgpt://",
        .perplexity: "perplexity://",
        .gemini:     "gemini://"
    ]

    // MARK: - Web URL Fallbacks

    static let webURLs: [Platform: String] = [
        .claude:     "https://claude.ai",
        .chatgpt:    "https://chat.openai.com",
        .perplexity: "https://www.perplexity.ai",
        .gemini:     "https://gemini.google.com"
    ]

    // MARK: - Launch

    /// Copies card text to clipboard, fires haptic, and opens the AI tool.
    /// Tries native URL scheme first; falls back to web URL in Safari.
    @MainActor
    static func launch(platform: Platform, cardText: String) {
        // 1. Copy to clipboard
        UIPasteboard.general.string = cardText

        // 2. Haptic feedback — must feel instant (< 50ms per Section 10)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // 3. Try native URL scheme
        if let scheme = urlSchemes[platform],
           let schemeURL = URL(string: scheme),
           UIApplication.shared.canOpenURL(schemeURL) {
            UIApplication.shared.open(schemeURL)
            return
        }

        // 4. Fallback to web URL in Safari
        if let webString = webURLs[platform],
           let webURL = URL(string: webString) {
            UIApplication.shared.open(webURL)
        }
    }
}
