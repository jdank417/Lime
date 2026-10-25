//
//  Wheel.swift
//  Lime
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Hit-testing math for the wheel, in a top-left-origin coordinate space.
nonisolated enum WheelGeometry {
    static let size: CGFloat = 400
    static let inner: CGFloat = 62
    static let outer: CGFloat = 160

    /// Which wedge sits under `point`, or nil over the center (cancel) or outside the panel.
    static func index(at point: CGPoint, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let dx = point.x - size / 2, dy = point.y - size / 2
        guard hypot(dx, dy) >= inner else { return nil }
        let step = 360 / Double(count)
        var degrees = atan2(dy, dx) * 180 / .pi + 90 + step / 2
        degrees = degrees.truncatingRemainder(dividingBy: 360)
        if degrees < 0 { degrees += 360 }
        return min(Int(degrees / step), count - 1)
    }

    /// Wedge 0 points straight up; the rest follow clockwise.
    static func centerAngle(of index: Int, count: Int) -> Double {
        -90 + Double(index) * 360 / Double(count)
    }
}

@MainActor
final class WheelController: ObservableObject {
    @Published private(set) var actions: [LimeAction] = []
    @Published private(set) var mode: WheelMode = .convert
    @Published private(set) var urls: [URL] = []
    @Published private(set) var icon = NSImage()
    @Published private(set) var hovered: Int?
    @Published private(set) var shown = false

    private lazy var panel = WheelPanel(controller: self)
    private var center: NSPoint = .zero
    private var pendingHide: DispatchWorkItem?

    var isVisible: Bool { panel.isVisible }

    func show(urls: [URL], mode: WheelMode, at point: NSPoint) {
        pendingHide?.cancel()
        self.urls = urls
        self.mode = mode
        actions = ActionCatalog.actions(for: urls, mode: mode)
        icon = urls.count == 1 ? NSWorkspace.shared.icon(forFile: urls[0].path) : NSWorkspace.shared.icon(for: .data)
        hovered = nil
        center = point
        shown = false

        let half = WheelGeometry.size / 2
        panel.setFrameOrigin(NSPoint(x: point.x - half, y: point.y - half))
        panel.orderFrontRegardless()
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) { self.shown = true }
        }
    }

    func setMode(_ mode: WheelMode) {
        guard mode != self.mode else { return }
        self.mode = mode
        actions = ActionCatalog.actions(for: urls, mode: mode)
        hovered = nil
    }

    /// Called when the mouse button goes up. The drop (if any) arrives around the same time,
    /// so wait a beat before hiding instead of yanking the target away.
    func dragEnded() {
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func hide() {
        pendingHide?.cancel()
        panel.orderOut(nil)
        shown = false
        hovered = nil
    }

    func updateHover(at point: CGPoint) {
        let index = WheelGeometry.index(at: point, count: actions.count)
        guard index != hovered else { return }
        withAnimation(.easeOut(duration: 0.12)) { hovered = index }
        if index != nil {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    func clearHover() {
        withAnimation(.easeOut(duration: 0.12)) { hovered = nil }
    }

    #if DEBUG
    /// Puts the wheel in a given state without showing the panel, for previews and snapshot tests.
    func stage(urls: [URL], mode: WheelMode, hovered: Int?) {
        self.urls = urls
        self.mode = mode
        actions = ActionCatalog.actions(for: urls, mode: mode)
        icon = NSWorkspace.shared.icon(forFile: urls[0].path)
        self.hovered = hovered
        shown = true
    }
    #endif

    /// Returns whether the drop was accepted.
    func drop(_ dropped: [URL]) -> Bool {
        guard let index = hovered, actions.indices.contains(index) else {
            hide()
            return false
        }
        let action = actions[index]
        let targets = dropped.isEmpty ? urls : dropped
        hide()
        ActionRunner.shared.run(action, on: targets, near: center)
        return true
    }
}

// MARK: - Window

/// Borderless, click-through-to-nothing panel that floats above everything, even full-screen apps.
final class WheelPanel: NSPanel {
    init(controller: WheelController) {
        let frame = NSRect(x: 0, y: 0, width: WheelGeometry.size, height: WheelGeometry.size)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false

        let container = NSView(frame: frame)
        let host = NSHostingView(rootView: WheelView(controller: controller))
        host.sizingOptions = []
        host.frame = frame
        host.autoresizingMask = [.width, .height]
        // The drop target sits on top of the SwiftUI view so it gets every drag message.
        let dropTarget = WheelDropView(frame: frame, controller: controller)
        dropTarget.autoresizingMask = [.width, .height]
        container.addSubview(host)
        container.addSubview(dropTarget)
        contentView = container
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class WheelDropView: NSView {
    private weak var controller: WheelController?

    init(frame: NSRect, controller: WheelController) {
        self.controller = controller
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { track(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { track(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { controller?.clearHover() }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return controller?.drop(urls) ?? false
    }

    override func mouseDown(with event: NSEvent) { controller?.hide() }

    private func track(_ sender: NSDraggingInfo) -> NSDragOperation {
        controller?.updateHover(at: convert(sender.draggingLocation, from: nil))
        // Over the center nothing is selected, so releasing there cancels.
        return controller?.hovered == nil ? [] : .copy
    }
}

// MARK: - Drawing

struct WheelView: View {
    @ObservedObject var controller: WheelController

    var body: some View {
        let count = controller.actions.count
        ZStack {
            Circle()
                .fill(Theme.glass.opacity(0.35))
                .frame(width: WheelGeometry.outer * 2 + 14, height: WheelGeometry.outer * 2 + 14)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 6)

            if count == 0 {
                AnnularSector(start: .degrees(0), end: .degrees(360), inner: WheelGeometry.inner, outer: WheelGeometry.outer)
                    .fill(Theme.glass.opacity(0.88))
                Text("Nothing to do\nfor this file")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                    .offset(y: -(WheelGeometry.inner + WheelGeometry.outer) / 2)
            }

            ForEach(Array(controller.actions.enumerated()), id: \.element.id) { index, action in
                Wedge(action: action, index: index, count: count, isHovered: controller.hovered == index)
            }

            center
        }
        .frame(width: WheelGeometry.size, height: WheelGeometry.size)
        .scaleEffect(controller.shown ? 1 : 0.55)
        .opacity(controller.shown ? 1 : 0)
    }

    private var center: some View {
        let hovered = controller.hovered.flatMap { controller.actions.indices.contains($0) ? controller.actions[$0] : nil }
        return ZStack {
            Circle().fill(Theme.glass.opacity(0.94))
            Circle().strokeBorder(Theme.lime.opacity(0.8), lineWidth: 2)
            VStack(spacing: 3) {
                Image(nsImage: controller.icon)
                    .resizable()
                    .frame(width: 34, height: 34)
                Text(hovered?.title ?? (controller.urls.count > 1 ? "\(controller.urls.count) files" : controller.mode.title))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(hovered == nil ? .white.opacity(0.75) : Theme.limeLight)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 92)
                HStack(spacing: 6) {
                    modeKey("⇧", .convert)
                    modeKey("⌥", .tools)
                }
            }
        }
        .frame(width: (WheelGeometry.inner - 6) * 2, height: (WheelGeometry.inner - 6) * 2)
    }

    private func modeKey(_ key: String, _ mode: WheelMode) -> some View {
        let active = controller.mode == mode
        return Text(key)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(active ? Theme.ink : .white.opacity(0.5))
            .frame(width: 18, height: 14)
            .background(active ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(.white.opacity(0.1)), in: .rect(cornerRadius: 4))
    }
}

private struct Wedge: View {
    let action: LimeAction
    let index: Int
    let count: Int
    let isHovered: Bool

    var body: some View {
        let step = 360 / Double(count)
        let middle = WheelGeometry.centerAngle(of: index, count: count)
        let gap = count > 1 ? 1.3 : 0
        let shape = AnnularSector(start: .degrees(middle - step / 2 + gap), end: .degrees(middle + step / 2 - gap),
                                  inner: WheelGeometry.inner, outer: WheelGeometry.outer)
        let radius = (WheelGeometry.inner + WheelGeometry.outer) / 2 + 4
        let radians = middle * .pi / 180

        ZStack {
            shape.fill(isHovered ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.glass.opacity(0.86)))
            shape.stroke(Theme.lime.opacity(isHovered ? 1 : 0.3), lineWidth: 1)
            VStack(spacing: 4) {
                Image(systemName: action.symbol)
                    .font(.system(size: 17, weight: .semibold))
                Text(action.label)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 64)
            }
            .foregroundStyle(isHovered ? Theme.ink : .white)
            .offset(x: radius * cos(radians), y: radius * sin(radians))
        }
        .scaleEffect(isHovered ? 1.05 : 1)
    }
}
