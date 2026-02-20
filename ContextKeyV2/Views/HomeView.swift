import SwiftUI

// MARK: - Home View

struct HomeView: View {
    @EnvironmentObject var storageService: StorageService
    @EnvironmentObject var biometricService: BiometricService
    @State private var profile: UserContextProfile?
    @State private var showInput = false
    @State private var showDeleteConfirm = false
    @State private var copiedToClipboard = false
    @State private var showFeedback = false
    @State private var feedbackText = ""

    var body: some View {
        NavigationStack {
            Group {
                if let profile = profile {
                    contextListView(profile)
                } else {
                    ProgressView("Loading...")
                        .task { loadProfile() }
                }
            }
            .navigationTitle("Your Context")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showInput = true
                        } label: {
                            Label("Add More Context", systemImage: "plus")
                        }

                        Button {
                            showFeedback = true
                        } label: {
                            Label("Send Feedback", systemImage: "envelope")
                        }

                        Divider()

                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete All Data", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showInput) {
                InputView()
                    .environmentObject(storageService)
                    .onDisappear { loadProfile() }
            }
            .alert("Delete All Data?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    try? storageService.deleteAll()
                    profile = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently erase all your stored context. This cannot be undone.")
            }
            .sheet(isPresented: $showFeedback) {
                feedbackView
            }
        }
    }

    // MARK: - Context List

    private func contextListView(_ profile: UserContextProfile) -> some View {
        List {
            // Copy button at top
            Section {
                Button {
                    copyContext(profile)
                } label: {
                    HStack {
                        Image(systemName: copiedToClipboard ? "checkmark.circle.fill" : "doc.on.doc.fill")
                            .foregroundStyle(copiedToClipboard ? .green : .blue)
                        Text(copiedToClipboard ? "Copied!" : "Copy Context")
                            .font(.headline)
                            .foregroundStyle(copiedToClipboard ? .green : .blue)
                        Spacer()
                        Image(systemName: "faceid")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            } footer: {
                Text("FaceID required. Paste into any AI app to start with full context.")
                    .font(.caption2)
            }

            // Facts by layer
            let grouped = Dictionary(grouping: profile.facts, by: { $0.layer })

            ForEach(ContextLayer.allCases, id: \.self) { layer in
                if let facts = grouped[layer], !facts.isEmpty {
                    Section(header: Text(layerTitle(layer))) {
                        ForEach(facts) { fact in
                            FactRow(fact: fact)
                        }
                    }
                }
            }

            // Import history
            if !profile.importHistory.isEmpty {
                Section(header: Text("Import History")) {
                    ForEach(profile.importHistory.reversed(), id: \.importedAt) { record in
                        HStack {
                            Image(systemName: platformIcon(record.platform))
                            VStack(alignment: .leading) {
                                Text(record.platform.rawValue.capitalized)
                                    .font(.subheadline.bold())
                                Text("\(record.conversationCount) conversations, \(record.factsExtracted) facts")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(record.importedAt, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Feedback View

    private var feedbackView: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("What's on your mind?")
                    .font(.headline)
                    .padding(.top)

                TextEditor(text: $feedbackText)
                    .frame(maxHeight: .infinity)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                Text("App version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button("Submit") {
                    // For v1: save feedback locally. Later: email or API.
                    saveFeedbackLocally()
                    showFeedback = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.bottom)
            }
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showFeedback = false }
                }
            }
        }
    }

    // MARK: - Actions

    private func loadProfile() {
        if let loaded = try? storageService.load() {
            profile = loaded
        }
    }

    private func copyContext(_ profile: UserContextProfile) {
        Task {
            let authed = await biometricService.authenticate(reason: "Authenticate to copy your context")
            guard authed else { return }

            UIPasteboard.general.string = profile.formattedContext()
            copiedToClipboard = true

            try? await Task.sleep(for: .seconds(2))
            copiedToClipboard = false
        }
    }

    private func saveFeedbackLocally() {
        let feedback = [
            "text": feedbackText,
            "date": ISO8601DateFormatter().string(from: Date()),
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        ]

        let feedbackDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("feedback", isDirectory: true)
        try? FileManager.default.createDirectory(at: feedbackDir, withIntermediateDirectories: true)

        let feedbackFile = feedbackDir.appendingPathComponent("feedback_\(Date().timeIntervalSince1970).json")
        if let data = try? JSONSerialization.data(withJSONObject: feedback) {
            try? data.write(to: feedbackFile)
        }

        feedbackText = ""
    }

    private func layerTitle(_ layer: ContextLayer) -> String {
        switch layer {
        case .coreIdentity: return "Identity"
        case .currentContext: return "Current Context"
        case .activeContext: return "Right Now"
        }
    }

    private func platformIcon(_ platform: Platform) -> String {
        switch platform {
        case .claude: return "brain.head.profile"
        case .chatgpt: return "bubble.left.and.bubble.right.fill"
        case .perplexity: return "magnifyingglass"
        case .gemini: return "sparkles"
        }
    }
}
