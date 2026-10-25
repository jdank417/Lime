//
//  Island.swift
//  Lime
//

import AppKit
import Combine
import SwiftUI

/// A black pill at the top of the screen that shows a job's progress, then its result.
@MainActor
final class Island: ObservableObject {
    static let shared = Island()

    enum State: Equatable {
        case hidden
        case working(title: String, detail: String)
        case done(name: String, outputs: [URL])
        case failed(String)
    }

    @Published private(set) var state: State = .hidden
    /// nil while a job can't say how far along it is.
    @Published private(set) var progress: Double?

    private static let size = NSSize(width: 420, height: 120)
    private lazy var panel = makePanel()
    private var pendingHide: DispatchWorkItem?

    func working(_ title: String, detail: String) {
        progress = nil
        present(.working(title: title, detail: detail))
    }

    func setProgress(_ value: Double) {
        guard case .working = state else { return }
        withAnimation(.linear(duration: 0.2)) { progress = value }
    }

    func done(_ outputs: [URL]) {
        let name = outputs.count == 1 ? outputs[0].lastPathComponent : "\(outputs.count) files"
        present(.done(name: name, outputs: outputs))
        hide(after: 4.5)
    }

    func failed(_ message: String) {
        present(.failed(message))
        hide(after: 6)
    }

    func reveal() {
        if case .done(_, let outputs) = state {
            NSWorkspace.shared.activateFileViewerSelecting(outputs)
        }
        hide()
    }

    func hide(after delay: TimeInterval = 0) {
        pendingHide?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { self.state = .hidden }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if self.state == .hidden { self.panel.orderOut(nil) }
            }
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func present(_ newState: State) {
        pendingHide?.cancel()
        if !panel.isVisible || state == .hidden {
            panel.setFrameOrigin(origin())
            panel.orderFrontRegardless()
        }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { state = newState }
    }

    /// Centered just under the menu bar of the screen the mouse is on.
    private func origin() -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSPointInRect(mouse, $0.frame) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        return NSPoint(x: visible.midX - Self.size.width / 2, y: visible.maxY - Self.size.height - 4)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        let host = FirstMouseHostingView(rootView: IslandView(island: self))
        host.sizingOptions = []
        host.frame = panel.contentLayoutRect
        panel.contentView = host
        return panel
    }
}

/// Lets a click land on the island even though Lime isn't the active app.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct IslandView: View {
    @ObservedObject var island: Island

    var body: some View {
        VStack {
            switch island.state {
            case .hidden:
                EmptyView()
            case .working(let title, let detail):
                working(title, detail)
                    .transition(.scale(scale: 0.4, anchor: .top).combined(with: .opacity))
            case .done(let name, _):
                pill {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.limeLight)
                    Text("\(name) is ready")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button("Show") { island.reveal() }
                        .buttonStyle(IslandButtonStyle())
                }
                .transition(.scale(scale: 0.4, anchor: .top).combined(with: .opacity))
            case .failed(let message):
                pill {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                        .lineLimit(2)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Spacer(minLength: 8)
                    Button("OK") { island.hide() }
                        .buttonStyle(IslandButtonStyle())
                }
                .transition(.scale(scale: 0.4, anchor: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 6)
    }

    private func working(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).lineLimit(1)
                Spacer()
                if let progress = island.progress {
                    Text("\(Int(progress * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            Text(detail)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.middle)
            ProgressBar(value: island.progress)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 340)
        .background(.black, in: .rect(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }

    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10, content: content)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .frame(width: 340, height: 44)
            .background(.black, in: .capsule)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }
}

/// Determinate when `value` is set, otherwise a sliding sliver.
private struct ProgressBar: View {
    let value: Double?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.lime.opacity(0.22))
                if let value {
                    Capsule().fill(Theme.gradient).frame(width: max(6, width * value))
                } else {
                    TimelineView(.animation) { timeline in
                        let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                        Capsule().fill(Theme.gradient)
                            .frame(width: width * 0.3)
                            .offset(x: (width * 1.3) * phase - width * 0.3)
                    }
                    .clipShape(Capsule())
                }
            }
        }
        .frame(height: 5)
    }
}

private struct IslandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Theme.limeLight.opacity(configuration.isPressed ? 0.7 : 1), in: .capsule)
    }
}
