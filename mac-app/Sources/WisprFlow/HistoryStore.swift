import Combine
import Foundation

/// One past dictation.
struct HistoryItem: Codable, Hashable {
    let text: String
    let date: Date
}

/// Keeps the recent dictation history, persisted to UserDefaults so it survives
/// relaunches. Newest first, capped at `maxItems`.
///
/// (The cleaned text also lives in Postgres via the agno run, but a small local
/// history keeps the menu-bar list instant and available offline.)
final class HistoryStore: ObservableObject {
    private let key = "speak.history.v1"
    private let maxItems = 20
    @Published private(set) var items: [HistoryItem] = []

    init() { load() }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.insert(HistoryItem(text: trimmed, date: Date()), at: 0)
        if items.count > maxItems { items = Array(items.prefix(maxItems)) }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data)
        else { return }
        items = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
