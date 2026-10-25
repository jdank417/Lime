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
    @AppStorage(Prefs.Key.showMenuBarIcon) private var showMenuBarIcon = true

    var body: some Scene {
        // The main window is AppKit-managed (see MainWindow), so the menu bar item is the only scene.
        MenuBarExtra(isInserted: $showMenuBarIcon) {
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
        Prefs.registerDefaults()

        monitor.isEnabled = { UserDefaults.standard.bool(forKey: Prefs.Key.enabled) }
        monitor.onStart = { [wheel] urls, mode, location in wheel.show(urls: urls, mode: mode, at: location) }
        monitor.onModeChange = { [wheel] mode in wheel.setMode(mode) }
        monitor.onEnd = { [wheel] in wheel.dragEnded() }
        monitor.start()

        // Opened at login, Lime stays quietly in the menu bar; opened by hand, it shows its window.
        if !launchedAtLogin { MainWindow.shared.show() }
    }

    /// Opening Lime again from Finder or Spotlight brings the window back, even with the menu bar icon hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindow.shared.show()
        return true
    }

    private var launchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

struct MenuBarContent: View {
    @AppStorage(Prefs.Key.enabled) private var enabled = true
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
        Button("Open Lime…") { MainWindow.shared.show() }
        Button("Settings…") { MainWindow.shared.show(tab: .settings) }
            .keyboardShortcut(",")
        Button("About Lime") { MainWindow.shared.show(tab: .about) }
        Divider()
        Button("Quit Lime") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
