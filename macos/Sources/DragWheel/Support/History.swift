import Foundation
import Combine

struct HistoryItem: Identifiable {
    let id = UUID()
    let date = Date()
    let source: URL
    let output: URL?
    let action: ActionID
    let error: String?
}

/// The most recent results, shown in the menu bar and the converter window.
@MainActor
final class History: ObservableObject {
    static let shared = History()
    @Published private(set) var items: [HistoryItem] = []

    func record(_ outcomes: [Outcome]) {
        let new = outcomes.map { outcome -> HistoryItem in
            switch outcome.result {
            case .success(let url): return HistoryItem(source: outcome.source, output: url, action: outcome.action, error: nil)
            case .failure(let error): return HistoryItem(source: outcome.source, output: nil, action: outcome.action, error: error.localizedDescription)
            }
        }
        items = Array((new.reversed() + items).prefix(30))
    }

    func clear() { items.removeAll() }
}
