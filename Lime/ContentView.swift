//
//  ContentView.swift
//  Lime
//
//  Created by Jason Dank on 10/25/26.
//

import ServiceManagement
import SwiftUI

struct ContentView: View {
    @AppStorage("enabled") private var enabled = true
    @ObservedObject private var runner = ActionRunner.shared
    @State private var dropped: [URL] = []
    @State private var isTargeted = false
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            HStack(spacing: 12) {
                HintCard(key: "⇧", title: "Shift + drag", subtitle: "Convert to another format")
                HintCard(key: "⌥", title: "Option + drag", subtitle: "Edit, crop, trim, compress…")
            }
            dropZone
            if !runner.history.isEmpty { recent }
            Divider()
            Toggle("Open Lime at login", isOn: $opensAtLogin)
                .onChange(of: opensAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        opensAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Text("Everything is converted on this Mac. New files are saved next to the originals.")
                .font(.caption)
                .foregroundStyle(Theme.ink.opacity(0.7))
        }
        .padding(24)
        .padding(.top, 8)
        .frame(width: 540)
        .foregroundStyle(Theme.ink)
        .tint(Theme.limeDeep)
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
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.lime)
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
            .foregroundStyle(configuration.isPressed ? Theme.ink : Theme.ink)
            .background(configuration.isPressed ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.lime.opacity(0.14)),
                        in: .rect(cornerRadius: 9))
    }
}

#Preview {
    ContentView()
}
