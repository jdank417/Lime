//
//  ContentView.swift
//  Lime
//
//  Created by Jason Dank on 10/25/26.
//

import SwiftUI

/// The main window: Home, Settings and About under one close button.
struct ContentView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case home = "Home", settings = "Settings", about = "About"
        var id: String { rawValue }
    }

    var close: () -> Void
    @State private var tab: Tab

    init(initialTab: Tab = .home, close: @escaping () -> Void = {}) {
        self.close = close
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Picker("Section", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 270)
                // The standard red, yellow and green buttons sit at the top left; this just gives ⌘W.
                Button("Close", action: close)
                    .keyboardShortcut("w", modifiers: .command)
                    .hidden()
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            Rectangle().fill(Theme.ink.opacity(0.12)).frame(height: 1)

            ScrollView {
                Group {
                    switch tab {
                    case .home: HomeTab(openSettings: { tab = .settings })
                    case .settings: SettingsTab()
                    case .about: AboutTab()
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 560, height: 660)
        .foregroundStyle(Theme.ink)
        .tint(Theme.limeDeep)
        .background(LimeWindowBackground())
        .onReceive(NotificationCenter.default.publisher(for: .limeShowTab)) { note in
            if let requested = note.object as? Tab { tab = requested }
        }
    }
}

// MARK: - Home

private struct HomeTab: View {
    let openSettings: () -> Void
    @AppStorage(Prefs.Key.enabled) private var enabled = true
    @AppStorage(Prefs.Key.convertKey) private var convertKey = Prefs.ConvertKey.shift
    @AppStorage(Prefs.Key.toolsKey) private var toolsKey = Prefs.ToolsKey.option
    @AppStorage(Prefs.Key.saveLocation) private var saveLocation = Prefs.SaveLocation.beside
    @ObservedObject private var runner = ActionRunner.shared
    @State private var dropped: [URL] = []
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            HStack(spacing: 12) {
                HintCard(key: convertKey.symbol, title: "\(convertKey.name) + drag", subtitle: "Convert to another format")
                HintCard(key: toolsKey.symbol, title: "\(toolsKey.name) + drag", subtitle: "Edit, crop, trim, compress…")
            }
            dropZone
            if !runner.history.isEmpty { recent }
            HStack {
                Text("Everything happens on this Mac. New files go \(destination).")
                Spacer()
                Button("Settings…", action: openSettings)
                    .buttonStyle(GlassPillButtonStyle())
            }
            .font(.caption)
            .foregroundStyle(Theme.ink.opacity(0.7))
        }
    }

    private var destination: String {
        switch saveLocation {
        case .beside: "next to the originals"
        case .downloads: "to Downloads"
        case .folder: "to \(Prefs.customFolder?.lastPathComponent ?? "your chosen folder")"
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            LimeSlice().frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text("Lime").font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Squeeze any file into a new format.").foregroundStyle(Theme.ink.opacity(0.7))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Toggle("Enabled", isOn: $enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                Text(enabled ? "On" : "Off")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(enabled ? Theme.limeDeep : Theme.ink.opacity(0.7))
            }
        }
    }

    @ViewBuilder private var dropZone: some View {
        VStack(spacing: 12) {
            if dropped.isEmpty {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Theme.limeDeep)
                Text("Or drop files here").font(.headline)
                Text("Pick what to do with them from a list.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink.opacity(0.7))
            } else {
                droppedActions
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding(14)
        .background(.white.opacity(isTargeted ? 0.5 : 0.25), in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.limeDeep.opacity(isTargeted ? 0.9 : 0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
        .dropDestination(for: URL.self) { urls, _ in
            dropped = urls.filter(\.isFileURL)
            return !dropped.isEmpty
        } isTargeted: { isTargeted = $0 }
    }

    private var droppedActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(dropped.count == 1 ? dropped[0].lastPathComponent : "\(dropped.count) files")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Clear") { dropped = [] }
                    .buttonStyle(.borderless)
            }
            actionRow("Convert", ActionCatalog.actions(for: dropped, mode: .convert))
            actionRow("Tools", ActionCatalog.actions(for: dropped, mode: .tools))
        }
    }

    private func actionRow(_ title: String, _ actions: [LimeAction]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.ink.opacity(0.7))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], spacing: 6) {
                ForEach(actions) { action in
                    Button {
                        runner.run(action, on: dropped)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: action.symbol).font(.system(size: 14, weight: .semibold))
                            Text(action.label).font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity, minHeight: 42)
                    }
                    .buttonStyle(LimeButtonStyle())
                    .help(action.title)
                }
            }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECENT")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.ink.opacity(0.7))
            ForEach(runner.history.prefix(4)) { item in
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.limeDeep)
                    Text(item.outputs.count == 1 ? item.outputs[0].lastPathComponent : "\(item.outputs.count) files")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.title).foregroundStyle(Theme.ink.opacity(0.7)).lineLimit(1)
                    Spacer()
                    Button("Show") { NSWorkspace.shared.activateFileViewerSelecting(item.outputs) }
                        .buttonStyle(.borderless)
                }
                .font(.callout)
            }
        }
    }
}

private struct HintCard: View {
    let key: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Text(key)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 38, height: 38)
                .background(Theme.gradient, in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.callout, design: .rounded, weight: .semibold))
                Text(subtitle).font(.caption).foregroundStyle(Theme.ink.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.35), in: .rect(cornerRadius: 12))
    }
}

private struct LimeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.ink)
            .background(configuration.isPressed ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(.white.opacity(0.3)),
                        in: .rect(cornerRadius: 9))
    }
}

#Preview {
    ContentView()
}
