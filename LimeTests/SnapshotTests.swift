//
//  SnapshotTests.swift
//  LimeTests
//

import AppKit
import SwiftUI
import Testing
@testable import Lime

/// Renders the UI to PNGs in $LIME_SNAPSHOT_DIR so it can be eyeballed. Skipped when the variable isn't set.
@MainActor
struct SnapshotTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIME_SNAPSHOT_DIR"] != nil))
    func renderUI() throws {
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LIME_SNAPSHOT_DIR"]!)
        let image = FileManager.default.temporaryDirectory.appendingPathComponent("photo.heic")
        try Data().write(to: image)

        for (name, mode, hovered) in [("wheel-convert", WheelMode.convert, 1), ("wheel-tools", .tools, nil)] {
            let controller = WheelController()
            controller.stage(urls: [image], mode: mode, hovered: hovered)
            try save(WheelView(controller: controller).background(Color(white: 0.55)), to: out.appendingPathComponent("\(name).png"))
        }
        try save(ContentView(), to: out.appendingPathComponent("window.png"))
        // Scroll views don't render here, so draw the tabs' content on its own.
        try save(SettingsTab().padding(24).frame(width: 560).background(LimeWindowBackground()).foregroundStyle(Theme.ink),
                 to: out.appendingPathComponent("settings.png"))
        try save(AboutTab().padding(24).frame(width: 560).background(LimeWindowBackground()).foregroundStyle(Theme.ink),
                 to: out.appendingPathComponent("about.png"))

        let session = EditorSession()
        try save(AdjustEditor(urls: [image], session: session).frame(width: 620, height: 760), to: out.appendingPathComponent("edit.png"))
        try save(CompressImageEditor(urls: [image], session: session).frame(width: 540, height: 470), to: out.appendingPathComponent("compress.png"))
        try save(SpeedEditor(url: image, session: session).frame(width: 540, height: 330), to: out.appendingPathComponent("speed.png"))
    }

    private func save(_ view: some View, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let rep = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}
