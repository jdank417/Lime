//
//  SettingsView.swift
//  Lime
//

import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Settings

struct SettingsTab: View {
    @AppStorage(Prefs.Key.enabled) private var enabled = true
    @AppStorage(Prefs.Key.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(Prefs.Key.soundWhenDone) private var soundWhenDone = false
    @AppStorage(Prefs.Key.revealWhenDone) private var revealWhenDone = false
    @AppStorage(Prefs.Key.convertKey) private var convertKey = Prefs.ConvertKey.shift
    @AppStorage(Prefs.Key.toolsKey) private var toolsKey = Prefs.ToolsKey.option
    @AppStorage(Prefs.Key.wheelSize) private var wheelSize = Prefs.WheelSize.medium
    @AppStorage(Prefs.Key.glass) private var glass = Prefs.GlassStyle.clear
    @AppStorage(Prefs.Key.hoverColor) private var hoverColor = Prefs.HoverColor.lime
    @AppStorage(Prefs.Key.haptics) private var haptics = true
    @AppStorage(Prefs.Key.shrinkDragPreview) private var shrinkDragPreview = true
    @AppStorage(Prefs.Key.saveLocation) private var saveLocation = Prefs.SaveLocation.beside
    @AppStorage(Prefs.Key.customFolder) private var customFolder = ""
    @AppStorage(Prefs.Key.imageQuality) private var imageQuality = 0.9
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard("General") {
                SettingRow("Lime is on", detail: "Turn off to drag files normally without the wheel.") {
                    Toggle("", isOn: $enabled).toggleStyle(.switch)
                }
                SettingRow("Open at login") {
                    Toggle("", isOn: $opensAtLogin).toggleStyle(.switch)
                        .onChange(of: opensAtLogin) { _, on in
                            do {
                                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            } catch {
                                opensAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                }
                SettingRow("Show in menu bar", detail: "When hidden, open Lime from Applications to get back here.") {
                    Toggle("", isOn: $showMenuBarIcon).toggleStyle(.switch)
                }
                SettingRow("Play a sound when done") {
                    Toggle("", isOn: $soundWhenDone).toggleStyle(.switch)
                }
                SettingRow("Show results in Finder", detail: "Opens the new file's folder as soon as it's ready.") {
                    Toggle("", isOn: $revealWhenDone).toggleStyle(.switch)
                }
            }

            SettingsCard("Wheel") {
                SettingRow("Convert key", detail: "Hold it while dragging to see formats.") {
                    Picker("", selection: $convertKey) {
                        ForEach(Prefs.ConvertKey.allCases) { Text("\($0.symbol) \($0.name)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                SettingRow("Tools key", detail: "Hold it while dragging to see tools.") {
                    Picker("", selection: $toolsKey) {
                        ForEach(Prefs.ToolsKey.allCases) { Text("\($0.symbol) \($0.name)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                SettingRow("Size") {
                    Picker("", selection: $wheelSize) {
                        Text("Small").tag(Prefs.WheelSize.small)
                        Text("Medium").tag(Prefs.WheelSize.medium)
                        Text("Large").tag(Prefs.WheelSize.large)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                SettingRow("Glass", detail: "Clear lets your desktop show through; frosted is easier to read.") {
                    Picker("", selection: $glass) {
                        Text("Clear").tag(Prefs.GlassStyle.clear)
                        Text("Frosted").tag(Prefs.GlassStyle.frosted)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                SettingRow("Highlight color") {
                    HStack(spacing: 8) {
                        ForEach(Prefs.HoverColor.allCases) { color in
                            Button {
                                hoverColor = color
                            } label: {
                                Circle()
                                    .fill(color.gradient)
                                    .frame(width: 22, height: 22)
                                    .padding(2)
                                    .overlay(Circle().strokeBorder(Theme.ink, lineWidth: hoverColor == color ? 2 : 0))
                            }
                            .buttonStyle(.plain)
                            .help(color.rawValue.capitalized)
                            .accessibilityLabel("\(color.rawValue.capitalized) highlight")
                        }
                    }
                }
                SettingRow("Haptic feedback", detail: "A tap on the trackpad as you cross each slice.") {
                    Toggle("", isOn: $haptics).toggleStyle(.switch)
                }
                SettingRow("Shrink the dragged file", detail: "Swaps Finder's big preview for a small thumbnail over the wheel.") {
                    Toggle("", isOn: $shrinkDragPreview).toggleStyle(.switch)
                }
            }

            SettingsCard("Files") {
                SettingRow("Save new files") {
                    Picker("", selection: $saveLocation) {
                        ForEach(Prefs.SaveLocation.allCases) { Text($0.title).tag($0) }
                    }
                    .frame(width: 200)
                    .onChange(of: saveLocation) { _, location in
                        if location == .folder && customFolder.isEmpty { chooseFolder() }
                    }
                }
                if saveLocation == .folder {
                    SettingRow(customFolder.isEmpty ? "No folder chosen" : (customFolder as NSString).abbreviatingWithTildeInPath) {
                        Button("Choose…", action: chooseFolder)
                            .buttonStyle(GlassPillButtonStyle())
                    }
                }
                SettingRow("Photo quality", detail: "For JPG, HEIC and AVIF. Higher looks better but makes bigger files.") {
                    HStack {
                        Slider(value: $imageQuality, in: 0.5...1).frame(width: 130)
                        Text("\(Int(imageQuality * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Restore Defaults", action: restoreDefaults)
                    .buttonStyle(GlassPillButtonStyle())
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.message = "Lime will save new files here."
        if panel.runModal() == .OK, let url = panel.url {
            customFolder = url.path
        } else if customFolder.isEmpty {
            saveLocation = .beside
        }
    }

    private func restoreDefaults() {
        for key in [Prefs.Key.showMenuBarIcon, Prefs.Key.convertKey, Prefs.Key.toolsKey, Prefs.Key.wheelSize, Prefs.Key.glass,
                    Prefs.Key.hoverColor, Prefs.Key.haptics, Prefs.Key.shrinkDragPreview, Prefs.Key.saveLocation,
                    Prefs.Key.customFolder, Prefs.Key.imageQuality, Prefs.Key.revealWhenDone, Prefs.Key.soundWhenDone] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title)
            VStack(spacing: 0) { content }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(.white.opacity(0.35), in: .rect(cornerRadius: 14))
        }
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: Control

    init(_ title: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(Theme.ink.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control.labelsHidden()
        }
        .padding(.vertical, 9)
    }
}

// MARK: - About

struct AboutTab: View {
    private static let website = URL(string: "https://jasondank.com")!
    private static let repository = URL(string: "https://github.com/jdank417/Lime")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                LimeSlice().frame(width: 88, height: 88)
                Text("Lime").font(.system(size: 30, weight: .bold, design: .rounded))
                Text(version).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Theme.ink.opacity(0.7))
                Text("Convert and edit files right from Finder. Free and open source.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 6)

            VStack(spacing: 12) {
                Text("MADE BY")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(Theme.ink.opacity(0.6))
                Text("Jason Dank").font(.system(size: 22, weight: .bold, design: .rounded))
                Text("I build apps for the Mac, iPhone and the web. See what else I'm working on.")
                    .font(.system(size: 13, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.ink.opacity(0.8))
                Link(destination: Self.website) {
                    Label("Visit jasondank.com", systemImage: "globe")
                }
                .buttonStyle(LimeProminentButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(.white.opacity(0.35), in: .rect(cornerRadius: 16))

            HStack(spacing: 10) {
                Link(destination: Self.repository) {
                    Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: Self.repository.appendingPathComponent("releases/latest")) {
                    Label("Check for Updates", systemImage: "arrow.down.circle")
                }
                Link(destination: Self.repository.appendingPathComponent("issues/new")) {
                    Label("Report a Bug", systemImage: "ladybug")
                }
            }
            .buttonStyle(GlassPillButtonStyle())

            Text("© 2026 Jason Dank · Released under the MIT License")
                .font(.caption)
                .foregroundStyle(Theme.ink.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}
