import SwiftUI
import UniformTypeIdentifiers

// MARK: - Import View

struct ImportView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedPlatform: Platform?
    @State private var showFilePicker = false
    @State private var isProcessingFile = false
    @State private var errorMessage: String?

    let onComplete: (ParseResult, String?) -> Void  // (parseResult, claudeMemory?)

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Select your AI platform")
                    .font(.headline)
                    .padding(.top)

                Text("You'll need to export your data from the platform first.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    PlatformCard(
                        name: "Claude",
                        icon: "brain.head.profile",
                        instruction: "Settings > Account > Export Data",
                        color: .orange,
                        isSelected: selectedPlatform == .claude
                    ) {
                        selectedPlatform = .claude
                    }

                    PlatformCard(
                        name: "ChatGPT",
                        icon: "bubble.left.and.bubble.right.fill",
                        instruction: "Settings > Data Controls > Export",
                        color: .green,
                        isSelected: selectedPlatform == .chatgpt
                    ) {
                        selectedPlatform = .chatgpt
                    }

                    PlatformCard(
                        name: "Perplexity",
                        icon: "magnifyingglass",
                        instruction: "Coming soon",
                        color: .blue,
                        isSelected: selectedPlatform == .perplexity,
                        isDisabled: true
                    ) {
                        // Disabled for now
                    }

                    PlatformCard(
                        name: "Gemini",
                        icon: "sparkles",
                        instruction: "Coming soon",
                        color: .purple,
                        isSelected: selectedPlatform == .gemini,
                        isDisabled: true
                    ) {
                        // Disabled for now
                    }
                }
                .padding(.horizontal)

                Spacer()

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Button {
                    showFilePicker = true
                } label: {
                    if isProcessingFile {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    } else {
                        Text("Select export file")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPlatform == nil || selectedPlatform == .perplexity || selectedPlatform == .gemini || isProcessingFile)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Import chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.json, .zip],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
        }
    }

    // MARK: - File Handling

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first, let platform = selectedPlatform else { return }
            processFile(url: url, platform: platform)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func processFile(url: URL, platform: Platform) {
        isProcessingFile = true
        errorMessage = nil

        Task {
            do {
                // Attempt security scoped access — retry once on failure
                var accessing = url.startAccessingSecurityScopedResource()
                if !accessing {
                    try await Task.sleep(for: .milliseconds(500))
                    accessing = url.startAccessingSecurityScopedResource()
                }
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }

                guard accessing else {
                    throw ImportError.fileAccessDenied
                }

                var parseResult: ParseResult
                var claudeMemory: String?

                // Check if it's a directory (unzipped archive) or file
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

                if isDir.boolValue {
                    // Directory — look for conversations.json inside
                    if let convURL = findFile(named: "conversations.json", in: url) {
                        parseResult = try ChatParser.parse(fileURL: convURL, platform: platform)
                    } else {
                        throw ImportError.conversationsNotFound
                    }

                    // Also try to parse memories.json if Claude
                    if platform == .claude {
                        if let memURL = findFile(named: "memories.json", in: url),
                           let memData = try? Data(contentsOf: memURL) {
                            claudeMemory = try? ChatParser.parseClaudeMemories(data: memData)
                        }
                    }
                } else {
                    // Single JSON file
                    parseResult = try ChatParser.parse(fileURL: url, platform: platform)
                }

                await MainActor.run {
                    dismiss()
                    onComplete(parseResult, claudeMemory)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessingFile = false
                }
            }
        }
    }

    /// Recursively find a file by name in a directory
    private func findFile(named fileName: String, in directory: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.lastPathComponent == fileName {
                return fileURL
            }
        }
        return nil
    }

    enum ImportError: Error, LocalizedError {
        case fileAccessDenied
        case conversationsNotFound

        var errorDescription: String? {
            switch self {
            case .fileAccessDenied:
                return "Could not access the file. Please try selecting it again."
            case .conversationsNotFound:
                return "No conversations.json found in the archive. Make sure you're using the correct export file."
            }
        }
    }
}

// MARK: - Platform Card

struct PlatformCard: View {
    let name: String
    let icon: String
    let instruction: String
    let color: Color
    var isSelected: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(isDisabled ? .secondary : color)
                    .frame(width: 40, height: 40)
                    .background((isDisabled ? Color.gray : color).opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(isDisabled ? .secondary : .primary)
                    Text(instruction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding(14)
            .background(isSelected ? Color.blue.opacity(0.08) : Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1)
    }
}
