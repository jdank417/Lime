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

/// Runs wheel actions, reports through the island, and remembers recent results.
@MainActor
final class ActionRunner: ObservableObject {
    static let shared = ActionRunner()

    @Published private(set) var history: [HistoryItem] = []

    func run(_ action: LimeAction, on urls: [URL]) {
        // Tools with a window show their own progress until Apply; the island takes over after.
        if !action.interactive {
            let detail = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
            Island.shared.working(action.title + "…", detail: detail)
        }
        Task {
            do {
                let outputs = try await action.run(urls)
                guard !outputs.isEmpty else {
                    if !action.interactive { Island.shared.hide() }
                    return
                }
                history.insert(HistoryItem(title: action.title, outputs: outputs, date: .now), at: 0)
                history = Array(history.prefix(20))
                Island.shared.done(outputs)
                if Prefs.soundWhenDone { NSSound(named: "Glass")?.play() }
                if Prefs.revealWhenDone { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
            } catch is CancellationError {
                if !action.interactive { Island.shared.hide() }
            } catch {
                Island.shared.failed(error.localizedDescription)
            }
        }
    }
}
