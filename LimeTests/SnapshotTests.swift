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
        try save(ContentView().background(Color(nsColor: .windowBackgroundColor)), to: out.appendingPathComponent("window.png"))
    }

    private func save(_ view: some View, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let rep = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}
