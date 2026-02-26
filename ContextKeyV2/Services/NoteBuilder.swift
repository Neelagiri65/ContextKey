import SwiftUI

// MARK: - Note Builder

/// In-memory collector for facts the user wants to copy into an AI tool.
/// Does NOT modify or mutate the underlying facts — purely additive references.
@MainActor
final class NoteBuilder: ObservableObject {
    @Published var items: [NoteItem] = []

    struct NoteItem: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let pillar: String // display name for grouping
    }

    /// Add a fact's text to the note. Deduplicates by content.
    func add(_ text: String, pillar: String) {
        guard !items.contains(where: { $0.text == text }) else { return }
        items.append(NoteItem(text: text, pillar: pillar))
    }

    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    func clear() {
        items.removeAll()
    }

    var isEmpty: Bool { items.isEmpty }

    /// Format as a clean text block ready to paste into ChatGPT/Claude/etc.
    var formattedNote: String {
        if items.isEmpty { return "" }

        // Group by pillar for readability
        var grouped: [String: [String]] = [:]
        for item in items {
            grouped[item.pillar, default: []].append(item.text)
        }

        // Sort by canonical 7-pillar order
        let pillarOrder = ContextPillar.allCases.map { $0.displayName }
        var lines: [String] = []
        for (pillar, facts) in grouped.sorted(by: {
            (pillarOrder.firstIndex(of: $0.key) ?? 99) < (pillarOrder.firstIndex(of: $1.key) ?? 99)
        }) {
            lines.append("## \(pillar)")
            for fact in facts {
                lines.append("• \(fact)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
