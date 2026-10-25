//
//  ActionRunner.swift
//  Lime
//

import AppKit
import Combine

struct HistoryItem: Identifiable {
    let id = UUID()
    let title: String
    let outputs: [URL]
    let date: Date
}

/// Runs wheel actions, reports through the HUD, and remembers recent results.
@MainActor
final class ActionRunner: ObservableObject {
    static let shared = ActionRunner()

    @Published private(set) var history: [HistoryItem] = []

    func run(_ action: LimeAction, on urls: [URL], near point: NSPoint? = nil) {
        HUD.shared.show(.working(action.title + "…"), near: point)
        Task {
            do {
                let outputs = try await action.run(urls)
                history.insert(HistoryItem(title: action.title, outputs: outputs, date: .now), at: 0)
                history = Array(history.prefix(20))
                let name = outputs.count == 1 ? outputs[0].lastPathComponent : "\(outputs.count) files"
                HUD.shared.show(.done(name, outputs), near: point)
            } catch {
                HUD.shared.show(.failed(error.localizedDescription), near: point)
            }
        }
    }
}
