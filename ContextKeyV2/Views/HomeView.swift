import SwiftUI

// MARK: - Home View

struct HomeView: View {
    @EnvironmentObject var storageService: StorageService
    @EnvironmentObject var biometricService: BiometricService
    @State private var profile: UserContextProfile?
    @State private var showInput = false
    @State private var showDeleteConfirm = false
    @State private var copiedToClipboard = false
    @State private var editingPillar: ContextPillar?
    @State private var showProviderStats = false
    @State private var selectedTab: HomeTab = .cards

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
                        .task { loadProfile() }
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

                        Button {
                            showProviderStats = true
                        } label: {
                            Label("Provider Stats", systemImage: "chart.bar")
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
            .sheet(item: $editingPillar) { pillar in
                PillarEditView(pillar: pillar, profile: $profile, storageService: storageService)
            }
            .sheet(isPresented: $showProviderStats) {
                if let profile {
                    ProviderStatsView(profile: profile)
                }
            }
            .alert("Delete All Data?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    try? storageService.deleteAll()
                    profile = nil
                    UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently erase all your stored context. This cannot be undone.")
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

                // AI App quick-launch
                aiAppBar

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
                PillarCardView(
                    pillar: pillar,
                    facts: profile.facts(for: pillar)
                )
                .onTapGesture {
                    editingPillar = pillar
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - AI App Quick-Launch

    private var aiAppBar: some View {
        VStack(spacing: 8) {
            Text("Open in AI App")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
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

    // MARK: - Actions

    private func loadProfile() {
        if let loaded = try? storageService.load() {
            profile = loaded
        } else {
            profile = UserContextProfile()
        }
    }

    private func copyContext() {
        guard let profile else { return }
        Task {
            let authed = await biometricService.authenticate(reason: "Copy your context")
            guard authed else { return }
            UIPasteboard.general.string = profile.formattedContext()
            copiedToClipboard = true
            try? await Task.sleep(for: .seconds(2))
            copiedToClipboard = false
        }
    }

    private func launchAIApp(_ platform: Platform) {
        Task {
            let authed = await biometricService.authenticate(reason: "Copy context to \(platform.displayName)")
            guard authed else { return }

            guard let profile else { return }
            UIPasteboard.general.string = profile.formattedContext()

            if let scheme = platform.urlScheme, let url = URL(string: scheme) {
                await UIApplication.shared.open(url)
            }
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

// MARK: - Entity Relation Graph View

struct EntityGraphView: View {
    let profile: UserContextProfile
    @State private var selectedNode: GraphNode?

    var body: some View {
        VStack(spacing: 0) {
            graphCanvas
            if let selected = selectedNode {
                nodeDetailPanel(selected)
            }
        }
        .animation(.smooth, value: selectedNode?.id)
    }

    // MARK: - Graph Canvas

    private var graphCanvas: some View {
        GeometryReader { geo in
            graphContent(size: geo.size)
        }
    }

    private func graphContent(size: CGSize) -> some View {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius: Double = min(size.width, size.height) * 0.35
        let nodes = pillarNodes
        let positions = computePositions(center: center, radius: radius, count: nodes.count)

        return ZStack {
            connectionLines(center: center, positions: positions)
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
            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        }
    }

    private func centerNodeLayer(center: CGPoint) -> some View {
        CenterNodeView()
            .position(center)
            .onTapGesture { selectedNode = nil }
    }

    private func pillarNodesLayer(nodes: [GraphNode], positions: [CGPoint]) -> some View {
        ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
            let isSelected = selectedNode?.id == node.id
            PillarNodeView(node: node, isSelected: isSelected)
                .position(positions[index])
                .onTapGesture {
                    selectedNode = isSelected ? nil : node
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

struct GraphConnection: Identifiable {
    let id: String
    let fromId: String
    let toId: String
    let color: Color
}

// MARK: - Pillar Edit View

struct PillarEditView: View {
    let pillar: ContextPillar
    @Binding var profile: UserContextProfile?
    let storageService: StorageService
    @Environment(\.dismiss) var dismiss
    @State private var newFactText = ""

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
                        Section(header: Text("Facts")) {
                            ForEach(facts) { fact in
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

    private func deleteFacts(at offsets: IndexSet, from facts: [ContextFact]) {
        guard var currentProfile = profile else { return }
        let idsToDelete = offsets.map { facts[$0].id }
        currentProfile.facts.removeAll { idsToDelete.contains($0.id) }
        currentProfile.lastUpdated = Date()
        try? storageService.save(currentProfile)
        profile = currentProfile
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
        try? storageService.save(currentProfile)
        profile = currentProfile
        newFactText = ""
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

// MARK: - ContextPillar Identifiable (for sheet)

extension ContextPillar: Identifiable {
    public var id: String { rawValue }
}
