//
//  LimeApp.swift
//  Lime
//
//  Created by Jason Dank on 10/25/26.
//

import SwiftUI

@main
struct LimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Lime", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarContent()
        } label: {
            Image(nsImage: LimeMark.menuBarImage)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let wheel = WheelController()
    private let monitor = DragMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["enabled": true])

        monitor.isEnabled = { UserDefaults.standard.bool(forKey: "enabled") }
        monitor.onStart = { [wheel] urls, mode, location in wheel.show(urls: urls, mode: mode, at: location) }
        monitor.onModeChange = { [wheel] mode in wheel.setMode(mode) }
        monitor.onEnd = { [wheel] in wheel.dragEnded() }
        monitor.start()

        NSApp.activate()
    }

    /// Reopening Lime from Finder or Spotlight brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSApp.windows.first { $0.identifier?.rawValue == "main" }?.makeKeyAndOrderFront(nil) }
        return true
    }
}

struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @AppStorage("enabled") private var enabled = true
    @ObservedObject private var runner = ActionRunner.shared

    var body: some View {
        Toggle("Lime Enabled", isOn: $enabled)
        Divider()
        if !runner.history.isEmpty {
            Section("Recent") {
                ForEach(runner.history.prefix(5)) { item in
                    Button(item.outputs.first?.lastPathComponent ?? item.title) {
                        NSWorkspace.shared.activateFileViewerSelecting(item.outputs)
                    }
                }
            }
            Divider()
        }
        Button("Open Lime…") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Button("Quit Lime") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
