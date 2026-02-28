import SwiftUI
import SwiftData

// MARK: - Home View

struct HomeView: View {
    @EnvironmentObject var storageService: StorageService
    @EnvironmentObject var biometricService: BiometricService
    @Environment(\.modelContext) private var modelContext
    @Query private var allEntities: [CanonicalEntity]
    @State private var profile: UserContextProfile?
    @State private var showInput = false
    @State private var showDeleteConfirm = false
    @State private var showDeleteError = false
    @State private var deleteError: String?
    @State private var copiedToClipboard = false
    @State private var editingPillar: ContextPillar?
    @State private var showProviderStats = false
    @State private var selectedTab: HomeTab = .cards
    @StateObject private var noteBuilder = NoteBuilder()
    @State private var showNoteBuilder = false
    @State private var copiedFactFeedback: String?
    @State private var copyFeedbackTask: Task<Void, Never>?
    @State private var showDevToggle = false
    @State private var selectedPersonaCard: Platform?
    @State private var showStoreResetBanner = false
    @Query private var allCitations: [CitationReference]

    enum HomeTab: String, CaseIterable {
        case cards = "Cards"
        case graph = "Graph"
    }

    var body: some View {
        NavigationStack {
            Group {
                if let profile {
                    mainContentView(profile)
                } else {
                    ProgressView("Loading...")
                        .task {
                            loadProfile()
                            checkStoreReset()
                        }
                }
            }
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showInput = true
                        } label: {
                            Label("Add Context", systemImage: "plus")
                        }

                        Button {
                            copyContext()
                        } label: {
                            Label(copiedToClipboard ? "Copied!" : "Copy Context", systemImage: "doc.on.doc")
                        }
                        .disabled(profile == nil || profile?.facts.isEmpty == true)

                        if FeatureFlags.noteBuilderEnabled {
                            Button {
                                showNoteBuilder = true
                            } label: {
                                Label(
                                    noteBuilder.isEmpty ? "Note Builder" : "Note Builder (\(noteBuilder.items.count))",
                                    systemImage: "note.text"
                                )
                            }
                        }

                        Button {
                            showProviderStats = true
                        } label: {
                            Label("Provider Stats", systemImage: "chart.bar")
                        }

                        Divider()

                        Button {
                            showDevToggle = true
                        } label: {
                            let isOn = FeatureFlags.v2EnhancedExtraction
                            Label("V2 Pipeline: \(isOn ? "ON" : "OFF")", systemImage: isOn ? "bolt.fill" : "bolt.slash")
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
                InputView(storageService: storageService)
                    .onDisappear { loadProfile() }
            }
            .sheet(item: $editingPillar) { pillar in
                PillarEditView(pillar: pillar, profile: $profile, storageService: storageService, noteBuilder: noteBuilder)
            }
            .sheet(isPresented: $showProviderStats) {
                if let profile {
                    ProviderStatsView(profile: profile)
                }
            }
            .sheet(isPresented: $showNoteBuilder) {
                NoteBuilderView(noteBuilder: noteBuilder)
            }
            .sheet(item: $selectedPersonaCard) { platform in
                PersonaCardDetailView(
                    platform: platform,
                    cardText: generateCardForPlatform(platform)
                )
            }
            .alert("Delete All Data?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    do {
                        try storageService.deleteAll()
                        profile = nil
                        UserDefaults.standard.removeObject(forKey: "userName")
                        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                    } catch {
                        deleteError = "Could not delete data: \(error.localizedDescription)"
                        showDeleteError = true
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently erase all your stored context. This cannot be undone.")
            }
            .alert("Delete Failed", isPresented: $showDeleteError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "Unknown error. Please try again.")
            }
            .alert("Developer Toggle", isPresented: $showDevToggle) {
                Button("Toggle") {
                    let current = UserDefaults.standard.bool(forKey: "v2EnhancedExtraction")
                    UserDefaults.standard.set(!current, forKey: "v2EnhancedExtraction")
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                let isOn = UserDefaults.standard.bool(forKey: "v2EnhancedExtraction")
                Text("V2 Extraction is currently \(isOn ? "ON" : "OFF"). Toggle?")
            }
        }
    }

    private var greeting: String {
        let name = UserDefaults.standard.string(forKey: "userName") ?? ""
        return name.isEmpty ? "Your Context" : "Hi, \(name)"
    }

    // MARK: - Main Content

    private func mainContentView(_ profile: UserContextProfile) -> some View {
        VStack(spacing: 0) {
            // Store reset banner — shown once after data recovery
            if showStoreResetBanner {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Your data was reset due to a storage upgrade. Please reimport your conversations.")
                        .font(.caption)
                }
                .padding(12)
                .background(.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
                .padding(.top, 8)
                .onTapGesture {
                    withAnimation { showStoreResetBanner = false }
                }
            }

            // Tab picker: Cards | Graph
            Picker("View", selection: $selectedTab) {
                ForEach(HomeTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            // Content
            switch selectedTab {
            case .cards:
                cardsView(profile)
            case .graph:
                EntityGraphView(profile: profile)
            }
        }
    }

    // MARK: - Cards View

    private func cardsView(_ profile: UserContextProfile) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Summary header
                contextSummary(profile)

                // Pillar cards — full-width list
                pillarCardsSection(profile)

                // Persona cards — 2x2 grid (tap=edit, long press=copy)
                personaCardsGrid

                // AI App quick-launch bar
                aiAppBar

                // V2 Facets — grouped by facet, sorted by belief score
                facetCardsSection

                // Empty facet prompts
                if !emptyFacetsList.isEmpty {
                    emptyFacetsPromptSection
                }

                // Add context prompt if sparse
                if profile.facts.count < 5 {
                    addContextPrompt
                }
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: - Summary

    private func contextSummary(_ profile: UserContextProfile) -> some View {
        let total = profile.facts.count
        let filled = ContextPillar.allCases.filter { !profile.facts(for: $0).isEmpty }.count

        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(total)")
                    .font(.title.bold())
                Text("facts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(filled)/7")
                    .font(.title.bold())
                Text("pillars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Completeness ring
            ZStack {
                Circle()
                    .stroke(Color(.systemGray4), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: CGFloat(filled) / 7.0)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(Double(filled) / 7.0 * 100))%")
                    .font(.caption2.bold())
            }
            .frame(width: 48, height: 48)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
        .padding(.horizontal)
    }

    // MARK: - Pillar Cards (Full Width)

    private func pillarCardsSection(_ profile: UserContextProfile) -> some View {
        VStack(spacing: 10) {
            ForEach(ContextPillar.allCases, id: \.self) { pillar in
                let facts = profile.facts(for: pillar)
                PillarCardView(
                    pillar: pillar,
                    facts: facts
                )
                .onTapGesture {
                    editingPillar = pillar
                }
                .contextMenu {
                    if !facts.isEmpty {
                        Button {
                            let text = facts.map { "• \($0.content)" }.joined(separator: "\n")
                            UIPasteboard.general.string = text
                            for fact in facts {
                                BeliefEngine.applyFeedbackByText(signal: .copiedFact, factText: fact.content, modelContext: modelContext)
                            }
                        } label: {
                            Label("Copy Facts", systemImage: "doc.on.doc")
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - AI App Quick-Launch

    private var aiAppBar: some View {
        VStack(spacing: 8) {
            Text(copiedToClipboard ? "Copied! Paste into your AI app." : "Tap to copy & open")
                .font(.caption)
                .foregroundStyle(copiedToClipboard ? .blue : .secondary)
                .animation(.smooth, value: copiedToClipboard)

            HStack(spacing: 16) {
                ForEach(Platform.aiPlatforms, id: \.self) { platform in
                    Button {
                        launchAIApp(platform)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: platform.iconName)
                                .font(.title2)
                                .frame(width: 48, height: 48)
                                .background(platformColor(platform).opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            Text(platform.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
        .padding(.horizontal)
    }

    // MARK: - Add Context Prompt

    private var addContextPrompt: some View {
        Button {
            showInput = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                Text("Add more context to improve your AI identity")
                    .font(.subheadline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.blue.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    // MARK: - V2 Facet Sections

    private var visibleFacetMap: [FacetType: [CanonicalEntity]] {
        FacetService.visibleFacets(from: allEntities)
    }

    private var emptyFacetsList: [FacetType] {
        FacetService.emptyFacets(from: allEntities)
    }

    private var facetCardsSection: some View {
        let facets = visibleFacetMap
        return VStack(spacing: 10) {
            ForEach(FacetType.allCases, id: \.self) { facetType in
                if let entities = facets[facetType] {
                    facetCard(facetType, entities: entities)
                }
            }
        }
        .padding(.horizontal)
    }

    private func facetCard(_ facet: FacetType, entities: [CanonicalEntity]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: iconForFacet(facet))
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(colorForFacet(facet))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                Text(FacetService.displayName(for: facet))
                    .font(.subheadline.bold())

                Spacer()

                Text("\(entities.count)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(colorForFacet(facet))
                    .clipShape(Capsule())
            }

            ForEach(entities.prefix(4)) { entity in
                HStack(spacing: 6) {
                    Circle()
                        .fill(colorForFacet(facet).opacity(0.5))
                        .frame(width: 5, height: 5)
                    Text(entity.canonicalText)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let score = entity.beliefScore {
                        Text("\(Int(score.currentScore * 100))%")
                            .font(.system(size: 9).bold())
                            .foregroundStyle(colorForFacet(facet))
                    }
                }
            }
            if entities.count > 4 {
                Text("+\(entities.count - 4) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 11)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(colorForFacet(facet).opacity(0.2), lineWidth: 1)
        )
    }

    private var emptyFacetsPromptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Enrich your profile")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ForEach(emptyFacetsList.prefix(3), id: \.self) { facet in
                Text(FacetService.prompt(for: facet))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemGray6))
        )
        .padding(.horizontal)
    }

    // MARK: - Persona Cards Grid (2x2)

    private var personaCardsGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                personaCard(for: .claude)
                personaCard(for: .chatgpt)
            }
            HStack(spacing: 10) {
                personaCard(for: .perplexity)
                personaCard(for: .gemini)
            }
        }
        .padding(.horizontal)
    }

    private func personaCard(for platform: Platform) -> some View {
        let cardText = generateCardForPlatform(platform)
        let isEmpty = cardText == "Import more conversations to generate your context card."

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: platform.iconName)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(platformColor(platform))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(platform.displayName)
                    .font(.caption.bold())

                Spacer()
            }

            Text(isEmpty ? "Import conversations to build this card." : cardText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(platformColor(platform).opacity(0.2), lineWidth: 1)
        )
        .onTapGesture {
            selectedPersonaCard = platform
        }
        .onLongPressGesture {
            // Long press = silent copy + haptic, no app launch
            UIPasteboard.general.string = cardText
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            BeliefEngine.applyContextCardCopiedToAll(modelContext: modelContext)
            copiedToClipboard = true
            scheduleCopyFeedbackReset()
        }
    }

    private func iconForFacet(_ facet: FacetType) -> String {
        switch facet {
        case .professionalIdentity: return "person.fill"
        case .technicalCapability:  return "hammer.fill"
        case .activeProjects:       return "folder.fill"
        case .goalsMotivations:     return "target"
        case .workingStyle:         return "slider.horizontal.3"
        case .valuesConstraints:    return "shield.fill"
        case .domainKnowledge:      return "globe"
        case .currentContext:       return "clock.fill"
        }
    }

    private func colorForFacet(_ facet: FacetType) -> Color {
        switch facet {
        case .professionalIdentity: return .blue
        case .technicalCapability:  return .purple
        case .activeProjects:       return .orange
        case .goalsMotivations:     return .red
        case .workingStyle:         return .green
        case .valuesConstraints:    return .gray
        case .domainKnowledge:      return .brown
        case .currentContext:       return .teal
        }
    }

    // MARK: - Actions

    private func loadProfile() {
        do {
            profile = try storageService.load()
        } catch StorageService.StorageError.noProfileFound {
            // No profile yet — start fresh
            profile = UserContextProfile()
        } catch {
            // Decryption or other error — show empty but log
            print("[HomeView] Failed to load profile: \(error)")
            profile = UserContextProfile()
        }
    }

    private func checkStoreReset() {
        if UserDefaults.standard.bool(forKey: "storeWasReset") {
            showStoreResetBanner = true
            UserDefaults.standard.removeObject(forKey: "storeWasReset")
        }
    }

    private func copyContext() {
        guard let profile else { return }
        UIPasteboard.general.string = profile.formattedContext()
        BeliefEngine.applyContextCardCopiedToAll(modelContext: modelContext)
        copiedToClipboard = true
        scheduleCopyFeedbackReset()
    }

    private func generateCardForPlatform(_ platform: Platform) -> String {
        let facets = FacetService.visibleFacets(from: allEntities)
        return NarrationService.generateCard(
            for: platform,
            facets: facets,
            citations: allCitations
        )
    }

    private func launchAIApp(_ platform: Platform) {
        let cardText = generateCardForPlatform(platform)
        BeliefEngine.applyContextCardCopiedToAll(modelContext: modelContext)
        AILaunchService.launch(platform: platform, cardText: cardText)
        copiedToClipboard = true
        scheduleCopyFeedbackReset()
    }

    private func scheduleCopyFeedbackReset() {
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            copiedToClipboard = false
        }
    }

    private func platformColor(_ platform: Platform) -> Color {
        switch platform {
        case .claude: return .orange
        case .chatgpt: return .green
        case .perplexity: return .blue
        case .gemini: return .purple
        case .manual: return .gray
        }
    }
}

// MARK: - Pillar Card View (Full Width, Rich)

struct PillarCardView: View {
    let pillar: ContextPillar
    let facts: [ContextFact]

    private var color: Color {
        switch pillar.color {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "gray": return .gray
        case "teal": return .teal
        default: return .blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(spacing: 8) {
                Image(systemName: pillar.iconName)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                Text(pillar.displayName)
                    .font(.subheadline.bold())

                Spacer()

                if facts.isEmpty {
                    Text("Empty")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                } else {
                    Text("\(facts.count)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(color)
                        .clipShape(Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Facts list
            if facts.isEmpty {
                Text("Tap to add \(pillar.displayName.lowercased()) info")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(facts.prefix(4)) { fact in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(color.opacity(0.5))
                                .frame(width: 5, height: 5)

                            Text(fact.content)
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)

                            if fact.frequency > 2 {
                                Text("\(fact.frequency)x")
                                    .font(.system(size: 9).bold())
                                    .foregroundStyle(color)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(color.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    if facts.count > 4 {
                        Text("+\(facts.count - 4) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 11)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(facts.isEmpty ? Color(.systemGray5) : color.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Persona Card Detail View

struct PersonaCardDetailView: View {
    let platform: Platform
    let cardText: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(cardText)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("\(platform.displayName) Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = cardText
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
        }
    }
}

// MARK: - Entity Relation Graph View

struct EntityGraphView: View {
    let profile: UserContextProfile
    @State private var selectedNode: GraphNode?
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    // Related pillar pairs (conceptually linked)
    private let relatedPairs: [(Int, Int)] = [
        (0, 1), // Persona ↔ Skills
        (1, 3), // Skills ↔ Active Projects
        (3, 4), // Active Projects ↔ Goals
        (4, 5), // Goals ↔ Constraints
        (6, 1), // Work Patterns ↔ Skills
        (0, 2), // Persona ↔ Communication Style
    ]

    var body: some View {
        let hasFacts = profile.facts.count > 0
        VStack(spacing: 0) {
            if hasFacts {
                graphCanvas
                if let selected = selectedNode {
                    nodeDetailPanel(selected)
                }
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "circle.grid.cross")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Add some context to see your graph")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .animation(.smooth, value: selectedNode?.id)
    }

    // MARK: - Graph Canvas (Pannable + Zoomable)

    private var graphCanvas: some View {
        GeometryReader { geo in
            graphContent(size: geo.size)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(dragGesture)
                .gesture(magnificationGesture)
                .onTapGesture { selectedNode = nil }
        }
        .clipped()
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale: CGFloat = lastScale * value.magnification
                scale = min(max(newScale, 0.5), 3.0)
            }
            .onEnded { _ in
                lastScale = scale
            }
    }

    private func graphContent(size: CGSize) -> some View {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius: Double = min(size.width, size.height) * 0.35
        let nodes = pillarNodes
        let positions = computePositions(center: center, radius: radius, count: nodes.count)

        return ZStack {
            // Hub lines (center to each node)
            connectionLines(center: center, positions: positions)
            // Cross-pillar relationship lines
            crossPillarLines(positions: positions, nodes: nodes)
            // Center + pillar nodes
            centerNodeLayer(center: center)
            pillarNodesLayer(nodes: nodes, positions: positions)
        }
    }

    private func connectionLines(center: CGPoint, positions: [CGPoint]) -> some View {
        ForEach(0..<positions.count, id: \.self) { index in
            Path { path in
                path.move(to: center)
                path.addLine(to: positions[index])
            }
            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        }
    }

    private func crossPillarLines(positions: [CGPoint], nodes: [GraphNode]) -> some View {
        ForEach(0..<relatedPairs.count, id: \.self) { i in
            let pair = relatedPairs[i]
            let fromIdx = pair.0
            let toIdx = pair.1
            // Only draw if both pillars have facts
            if fromIdx < nodes.count && toIdx < nodes.count
                && nodes[fromIdx].count > 0 && nodes[toIdx].count > 0 {
                Path { path in
                    path.move(to: positions[fromIdx])
                    path.addLine(to: positions[toIdx])
                }
                .stroke(
                    nodes[fromIdx].color.opacity(0.12),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
            }
        }
    }

    private func centerNodeLayer(center: CGPoint) -> some View {
        CenterNodeView()
            .position(center)
    }

    private func pillarNodesLayer(nodes: [GraphNode], positions: [CGPoint]) -> some View {
        ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
            let isSelected: Bool = selectedNode?.id == node.id
            PillarNodeView(node: node, isSelected: isSelected)
                .position(positions[index])
                .onTapGesture {
                    withAnimation(.smooth) {
                        selectedNode = isSelected ? nil : node
                    }
                }
        }
    }

    private func computePositions(center: CGPoint, radius: Double, count: Int) -> [CGPoint] {
        var result: [CGPoint] = []
        for index in 0..<count {
            let angle: Double = (2.0 * Double.pi / Double(count)) * Double(index) - Double.pi / 2.0
            let x: Double = center.x + radius * cos(angle)
            let y: Double = center.y + radius * sin(angle)
            result.append(CGPoint(x: x, y: y))
        }
        return result
    }

    // MARK: - Detail Panel

    @ViewBuilder
    private func nodeDetailPanel(_ node: GraphNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            nodeDetailHeader(node)
            nodeDetailFacts(node)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, y: -4)
        )
        .padding(.horizontal)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func nodeDetailHeader(_ node: GraphNode) -> some View {
        HStack {
            Image(systemName: node.icon)
                .foregroundStyle(node.color)
            Text(node.label)
                .font(.headline)
            Spacer()
            Button { selectedNode = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func nodeDetailFacts(_ node: GraphNode) -> some View {
        if node.facts.isEmpty {
            Text("No data yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(node.facts.prefix(5)) { fact in
                factRow(fact: fact, color: node.color)
            }
            if node.facts.count > 5 {
                Text("+\(node.facts.count - 5) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func factRow(fact: ContextFact, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(fact.content).font(.caption).lineLimit(2)
            Spacer()
            if fact.frequency > 1 {
                Text("\(fact.frequency)x")
                    .font(.system(size: 9).bold())
                    .foregroundStyle(color)
            }
        }
    }

    // MARK: - Data

    private var pillarNodes: [GraphNode] {
        ContextPillar.allCases.map { pillar in
            let facts = profile.facts(for: pillar)
            return GraphNode(
                id: pillar.rawValue,
                label: pillar.displayName,
                icon: pillar.iconName,
                color: colorForPillar(pillar),
                count: facts.count,
                facts: facts
            )
        }
    }

    private func colorForPillar(_ pillar: ContextPillar) -> Color {
        switch pillar.color {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "gray": return .gray
        case "teal": return .teal
        default: return .blue
        }
    }
}

// MARK: - Center Node View

private struct CenterNodeView: View {
    var body: some View {
        let name = UserDefaults.standard.string(forKey: "userName") ?? "You"
        VStack(spacing: 4) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.blue)
            Text(name)
                .font(.caption.bold())
                .lineLimit(1)
        }
        .frame(width: 72, height: 72)
        .background(
            Circle()
                .fill(Color.blue.opacity(0.1))
                .shadow(color: .blue.opacity(0.2), radius: 8)
        )
    }
}

// MARK: - Pillar Node View (Graph)

private struct PillarNodeView: View {
    let node: GraphNode
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: node.icon)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(node.color)
                .clipShape(Circle())

            Text(node.label)
                .font(.system(size: 9).bold())
                .lineLimit(1)
                .frame(maxWidth: 60)

            Text("\(node.count)")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground))
                .shadow(color: node.color.opacity(isSelected ? 0.4 : 0.1),
                        radius: isSelected ? 6 : 3)
        )
        .scaleEffect(isSelected ? 1.15 : 1.0)
    }
}

// MARK: - Graph Data Models

struct GraphNode: Identifiable {
    let id: String
    let label: String
    let icon: String
    let color: Color
    let count: Int
    let facts: [ContextFact]
}

// MARK: - Pillar Edit View

struct PillarEditView: View {
    let pillar: ContextPillar
    @Binding var profile: UserContextProfile?
    let storageService: StorageService
    @ObservedObject var noteBuilder: NoteBuilder
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var newFactText = ""
    @State private var saveError: String?
    @State private var copyFeedback: String?
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                if let profile {
                    let facts = profile.facts(for: pillar)

                    if facts.isEmpty {
                        Section {
                            Text("No facts for this pillar yet.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        // Copy All button
                        Section {
                            Button {
                                let text = facts.map { "• \($0.content)" }.joined(separator: "\n")
                                UIPasteboard.general.string = text
                                for fact in facts {
                                    BeliefEngine.applyFeedbackByText(signal: .copiedFact, factText: fact.content, modelContext: modelContext)
                                }
                                copyFeedback = "Copied \(facts.count) facts"
                                clearFeedback()
                            } label: {
                                Label(
                                    copyFeedback ?? "Copy All \(pillar.displayName) Facts",
                                    systemImage: copyFeedback != nil ? "checkmark" : "doc.on.doc"
                                )
                            }

                            if FeatureFlags.noteBuilderEnabled {
                                Button {
                                    for fact in facts {
                                        noteBuilder.add(fact.content, pillar: pillar.displayName)
                                    }
                                    copyFeedback = "Added \(facts.count) to Note"
                                    clearFeedback()
                                } label: {
                                    Label("Add All to Note", systemImage: "note.text.badge.plus")
                                }
                            }
                        }

                        Section(header: Text("Facts (\(facts.count))")) {
                            ForEach(facts) { fact in
                                factRow(fact)
                            }
                            .onDelete { indexSet in
                                deleteFacts(at: indexSet, from: facts)
                            }
                        }
                    }

                    Section(header: Text("Add Fact")) {
                        HStack {
                            TextField(pillar.promptHint, text: $newFactText)

                            Button {
                                addFact()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                            .disabled(newFactText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }

                    if let saveError {
                        Section {
                            Text(saveError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(pillar.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func factRow(_ fact: ContextFact) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(fact.content)
                    .font(.body)
                HStack(spacing: 8) {
                    if fact.frequency > 1 {
                        Text("Seen \(fact.frequency)x")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    Text("Confidence: \(Int(fact.confidence * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = fact.content
                BeliefEngine.applyFeedbackByText(signal: .copiedFact, factText: fact.content, modelContext: modelContext)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            if FeatureFlags.noteBuilderEnabled {
                Button {
                    noteBuilder.add(fact.content, pillar: pillar.displayName)
                } label: {
                    Label("Add to Note", systemImage: "note.text.badge.plus")
                }
            }
        }
    }

    private func clearFeedback() {
        feedbackTask?.cancel()
        feedbackTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copyFeedback = nil
        }
    }

    private func deleteFacts(at offsets: IndexSet, from facts: [ContextFact]) {
        guard var currentProfile = profile else { return }
        for offset in offsets {
            BeliefEngine.applyFeedbackByText(signal: .explicitDismiss, factText: facts[offset].content, modelContext: modelContext)
        }
        let idsToDelete = offsets.map { facts[$0].id }
        currentProfile.facts.removeAll { idsToDelete.contains($0.id) }
        currentProfile.lastUpdated = Date()
        do {
            try storageService.save(currentProfile)
            profile = currentProfile
            saveError = nil
        } catch {
            saveError = "Failed to save: \(error.localizedDescription)"
        }
    }

    private func addFact() {
        guard var currentProfile = profile else { return }
        let trimmed = newFactText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let source = ContextSource(
            platform: .manual,
            conversationCount: 0,
            lastConversationDate: Date()
        )

        let fact = ContextFact(
            content: trimmed,
            layer: pillar == .activeProjects || pillar == .goalsAndPriorities || pillar == .workPatterns
                ? .currentContext : .coreIdentity,
            pillar: pillar,
            confidence: 1.0,
            sources: [source]
        )

        currentProfile.facts.append(fact)
        currentProfile.lastUpdated = Date()
        do {
            try storageService.save(currentProfile)
            profile = currentProfile
            newFactText = ""
            saveError = nil
        } catch {
            saveError = "Failed to save: \(error.localizedDescription)"
        }
    }
}

// MARK: - Provider Stats View

struct ProviderStatsView: View {
    let profile: UserContextProfile
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(profile.importHistory.reversed(), id: \.importedAt) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.platform.displayName)
                                .font(.headline)
                            Text("\(record.factsExtracted) facts from \(record.conversationCount) conversations")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(record.importedAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(record.qualityLabel)
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(qualityColor(record.qualityLabel).opacity(0.12))
                            .foregroundStyle(qualityColor(record.qualityLabel))
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 4)
                }

                if profile.importHistory.isEmpty {
                    Text("No imports yet. Add context to see provider statistics.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Provider Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func qualityColor(_ label: String) -> Color {
        switch label {
        case "Excellent": return .green
        case "Good": return .blue
        case "Fair": return .orange
        default: return .gray
        }
    }
}

// MARK: - Note Builder View

struct NoteBuilderView: View {
    @ObservedObject var noteBuilder: NoteBuilder
    @Environment(\.dismiss) var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Group {
                if noteBuilder.isEmpty {
                    emptyState
                } else {
                    noteList
                }
            }
            .navigationTitle("Note Builder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if !noteBuilder.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            UIPasteboard.general.string = noteBuilder.formattedNote
                            copied = true
                            Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                copied = false
                            }
                        } label: {
                            Label(copied ? "Copied!" : "Copy Note", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Your note is empty")
                .font(.headline)
            Text("Long-press any fact in a pillar card and tap \"Add to Note\" to build a note you can paste into any AI tool.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var noteList: some View {
        List {
            Section(header: Text("\(noteBuilder.items.count) items")) {
                ForEach(noteBuilder.items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.text)
                            .font(.body)
                        Text(item.pillar)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = item.text
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                }
                .onDelete { offsets in
                    noteBuilder.remove(at: offsets)
                }
                .onMove { source, destination in
                    noteBuilder.move(from: source, to: destination)
                }
            }

            Section {
                Button(role: .destructive) {
                    noteBuilder.clear()
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
            }

            // Preview section
            Section(header: Text("Preview")) {
                Text(noteBuilder.formattedNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - ContextPillar Identifiable (for sheet)

extension ContextPillar: Identifiable {
    public var id: String { rawValue }
}
