//
//  HUD.swift
//  Lime
//

import AppKit
import Combine
import SwiftUI

/// The little pill that shows progress and results after a drop. Click it to reveal the output.
@MainActor
final class HUD: ObservableObject {
    static let shared = HUD()

    enum State {
        case working(String)
        case done(String, [URL])
        case failed(String)
    }

    @Published private(set) var state: State = .working("")

    private static let size = NSSize(width: 340, height: 64)
    private lazy var panel = makePanel()
    private var pendingHide: DispatchWorkItem?

    func show(_ state: State, near point: NSPoint?) {
        self.state = state
        pendingHide?.cancel()
        if !panel.isVisible || point != nil {
            panel.setFrameOrigin(origin(near: point))
        }
        panel.orderFrontRegardless()

        if case .working = state { return }
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    func tapped() {
        if case .done(_, let outputs) = state {
            NSWorkspace.shared.activateFileViewerSelecting(outputs)
        }
        pendingHide?.cancel()
        panel.orderOut(nil)
    }

    /// Just below the wheel's center, kept on screen. Without a point, bottom-center of the screen.
    private func origin(near point: NSPoint?) -> NSPoint {
        let size = Self.size
        let screen = point.flatMap { point in NSScreen.screens.first { NSPointInRect(point, $0.frame) } } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var origin = point.map { NSPoint(x: $0.x - size.width / 2, y: $0.y - size.height / 2 - 40) }
            ?? NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 80)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        return origin
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        let host = FirstMouseHostingView(rootView: HUDView(hud: self))
        host.sizingOptions = []
        host.frame = panel.contentLayoutRect
        panel.contentView = host
        return panel
    }
}

/// Lets a click land on the HUD even though Lime isn't the active app.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct HUDView: View {
    @ObservedObject var hud: HUD

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(width: 330, height: 54)
        .background(Theme.glass.opacity(0.94), in: .capsule)
        .overlay(Capsule().strokeBorder(accent.opacity(0.7), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .onTapGesture { hud.tapped() }
    }

    @ViewBuilder private var icon: some View {
        switch hud.state {
        case .working:
            ProgressView().controlSize(.small).tint(Theme.lime)
        case .done:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 24)).foregroundStyle(Theme.lime)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 22)).foregroundStyle(.orange)
        }
    }

    private var headline: String {
        switch hud.state {
        case .working(let title): title
        case .done(let name, _): name
        case .failed: "That didn't work"
        }
    }

    private var detail: String? {
        switch hud.state {
        case .working: nil
        case .done: "Click to show in Finder"
        case .failed(let message): message
        }
    }

    private var accent: Color {
        if case .failed = hud.state { return .orange }
        return Theme.lime
    }
}
