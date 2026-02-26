import Foundation

// MARK: - Open Source On-Device SLM Provider

/// Uses an open-source language model running on-device via llama.cpp.
/// The model is downloaded on-demand (not bundled with the app).
/// Compatible with any iOS version.
final class OpenSourceSLMProvider: SLMProvider, @unchecked Sendable {
    let displayName = "Open Source (On-Device)"
    let isAvailable = false  // Stub — not yet implemented (llama.cpp integration TODO)

    /// Model download state
    enum ModelState: Sendable {
        case notDownloaded
        case downloading(progress: Double)
        case ready
        case error(String)
    }

    /// Current model state — observable from UI
    @MainActor var modelState: ModelState = .notDownloaded

    /// Path to the downloaded model file
    private var modelURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("slm_model.gguf")
    }

    /// Check if model is already downloaded
    var isModelDownloaded: Bool {
        FileManager.default.fileExists(atPath: modelURL.path)
    }

    // MARK: - Model Management

    /// Download the model if not already present
    @MainActor
    func downloadModelIfNeeded() async throws {
        guard !isModelDownloaded else {
            modelState = .ready
            return
        }

        modelState = .downloading(progress: 0.0)

        // TODO: Replace with actual model download URL
        // Recommended models for on-device iOS extraction:
        // - Phi-3-mini (3.8B, ~2GB GGUF Q4) — Microsoft, great at structured extraction
        // - Gemma 2B (~1.5GB GGUF Q4) — Google, efficient
        // - TinyLlama 1.1B (~700MB GGUF Q4) — smallest viable option
        //
        // The model URL should be configurable and hosted on your own CDN
        // to avoid dependency on external hosting.

        let modelDownloadURL = URL(string: "https://your-cdn.com/models/phi-3-mini-q4.gguf")!

        let (tempURL, _) = try await URLSession.shared.download(from: modelDownloadURL)
        try FileManager.default.moveItem(at: tempURL, to: modelURL)

        modelState = .ready
    }

    /// Delete the downloaded model to free space
    func deleteModel() throws {
        if FileManager.default.fileExists(atPath: modelURL.path) {
            try FileManager.default.removeItem(at: modelURL)
        }
    }

    // MARK: - SLMProvider

    func extract(from text: String, prompt: String) async throws -> ExtractedFactsRaw {
        guard isModelDownloaded else {
            throw SLMError.modelNotDownloaded
        }

        // Construct the full prompt with JSON output instruction
        let fullPrompt = """
        \(prompt)

        Respond ONLY with valid JSON in this exact format, no other text:
        {
          "persona": ["fact1", "fact2"],
          "skillsAndStack": ["fact1", "fact2"],
          "communicationStyle": ["fact1"],
          "activeProjects": ["fact1"],
          "goalsAndPriorities": ["fact1"],
          "constraints": ["fact1"],
          "workPatterns": ["fact1"]
        }

        Text to analyze:
        \(text)
        """

        // Run inference using llama.cpp binding
        let output = try await runInference(prompt: fullPrompt)

        // Parse JSON response
        return try parseExtractionJSON(output)
    }

    // MARK: - Private: Inference Engine

    /// Run inference using the downloaded GGUF model
    /// This is a placeholder — actual implementation requires llama.cpp Swift binding
    private func runInference(prompt: String) async throws -> String {
        // TODO: Integrate llama.cpp via Swift Package Manager
        // Options:
        // 1. swift-llama (https://github.com/nicklama/swift-llama) — direct llama.cpp wrapper
        // 2. LLMFarm (https://github.com/nicklama/LLMFarm) — iOS-focused
        // 3. mlx-swift (Apple's MLX for Swift) — if targeting Apple Silicon
        //
        // Implementation pattern:
        // ```
        // let model = try LlamaModel(path: modelURL.path)
        // let result = try await model.generate(
        //     prompt: prompt,
        //     maxTokens: 512,
        //     temperature: 0.1  // Low temperature for structured extraction
        // )
        // return result.text
        // ```

        throw SLMError.engineNotConfigured
    }

    /// Parse the JSON output from the open-source model
    private func parseExtractionJSON(_ jsonString: String) throws -> ExtractedFactsRaw {
        // Extract JSON from response (model might include extra text)
        guard let jsonStart = jsonString.firstIndex(of: "{"),
              let jsonEnd = jsonString.lastIndex(of: "}") else {
            throw SLMError.invalidResponse
        }

        let jsonSubstring = String(jsonString[jsonStart...jsonEnd])
        guard let data = jsonSubstring.data(using: .utf8) else {
            throw SLMError.invalidResponse
        }

        struct RawJSON: Decodable {
            var persona: [String]?
            var skillsAndStack: [String]?
            var communicationStyle: [String]?
            var activeProjects: [String]?
            var goalsAndPriorities: [String]?
            var constraints: [String]?
            var workPatterns: [String]?
        }

        let raw = try JSONDecoder().decode(RawJSON.self, from: data)

        return ExtractedFactsRaw(
            persona: raw.persona ?? [],
            skillsAndStack: raw.skillsAndStack ?? [],
            communicationStyle: raw.communicationStyle ?? [],
            activeProjects: raw.activeProjects ?? [],
            goalsAndPriorities: raw.goalsAndPriorities ?? [],
            constraints: raw.constraints ?? [],
            workPatterns: raw.workPatterns ?? []
        )
    }

    // MARK: - Errors

    enum SLMError: Error, LocalizedError {
        case modelNotDownloaded
        case engineNotConfigured
        case invalidResponse
        case inferenceError(String)

        var errorDescription: String? {
            switch self {
            case .modelNotDownloaded:
                return "The language model hasn't been downloaded yet. Please download it in Settings."
            case .engineNotConfigured:
                return "The open-source SLM engine is not yet configured. This feature is coming soon."
            case .invalidResponse:
                return "The model returned an unexpected response format."
            case .inferenceError(let msg):
                return "Inference error: \(msg)"
            }
        }
    }
}
