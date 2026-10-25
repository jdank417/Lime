//
//  MainWindow.swift
//  Lime
//

import AppKit
import SwiftUI

/// Lime's one regular window (Home, Settings, About), with the standard window buttons.
/// Built in AppKit rather than as a SwiftUI hidden-title-bar window: there, clicks on the window
/// buttons fell through to the wallpaper and macOS revealed the desktop.
@MainActor
final class MainWindow {
    static let shared = MainWindow()

    private var window: LimeMainWindow?

    func show(tab: ContentView.Tab = .home) {
        let window: LimeMainWindow
        if let existing = self.window {
            window = existing
            NotificationCenter.default.post(name: .limeShowTab, object: tab)
        } else {
            window = makeWindow(tab: tab)
            self.window = window
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    private func makeWindow(tab: ContentView.Tab) -> LimeMainWindow {
        let size = NSSize(width: 560, height: 660)
        let window = LimeMainWindow(contentRect: NSRect(origin: .zero, size: size),
                                    styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                    backing: .buffered, defer: false)
        window.title = "Lime"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: ContentView(initialTab: tab, close: { [weak self] in self?.close() }))
        host.sizingOptions = []
        window.contentView = host
        window.center()
        return window
    }
}

final class LimeMainWindow: NSWindow {
    /// Esc closes it, like a panel.
    override func cancelOperation(_ sender: Any?) { close() }
}

extension Notification.Name {
    static let limeShowTab = Notification.Name("LimeShowTab")
}
