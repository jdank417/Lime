//
//  Wheel.swift
//  Lime
//

import AppKit
import Combine
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// Hit-testing math for the wheel, in a top-left-origin coordinate space.
nonisolated enum WheelGeometry {
    static let size: CGFloat = 250
    static let inner: CGFloat = 38
    static let outer: CGFloat = 110

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
    /// A real preview of the file; nil until Quick Look delivers one (or if it can't).
    @Published private(set) var thumbnail: NSImage?
    @Published private(set) var sizeText = ""
    @Published private(set) var hovered: Int?
    @Published private(set) var shown = false
    /// From the Size setting; the wheel is drawn at its base size and scaled.
    @Published private(set) var scale: CGFloat = 1

    private lazy var panel = WheelPanel(controller: self)
    private var center: NSPoint = .zero
    private var pendingHide: DispatchWorkItem?

    var isVisible: Bool { panel.isVisible }

    func show(urls: [URL], mode: WheelMode, at point: NSPoint) {
        pendingHide?.cancel()
        load(urls: urls, mode: mode)
        hovered = nil
        center = point
        shown = false
        scale = Prefs.wheelScale

        let side = WheelGeometry.size * scale
        panel.setContentSize(NSSize(width: side, height: side))
        panel.setFrameOrigin(NSPoint(x: point.x - side / 2, y: point.y - side / 2))
        panel.orderFrontRegardless()
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.74)) { self.shown = true }
        }
    }

    private func load(urls: [URL], mode: WheelMode) {
        self.urls = urls
        self.mode = mode
        actions = ActionCatalog.actions(for: urls, mode: mode)
        icon = urls.count == 1 ? NSWorkspace.shared.icon(forFile: urls[0].path) : NSWorkspace.shared.icon(for: .data)
        thumbnail = nil

        let bytes = urls.reduce(Int64(0)) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.totalFileSizeKey]).totalFileSize) ?? 0)
        }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        sizeText = urls.count == 1 ? size : "\(urls.count) files · \(size)"

        guard let first = urls.first else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: first, size: CGSize(width: 160, height: 160), scale: scale,
                                                   representationTypes: .thumbnail)
        Task {
            guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request),
                  self.urls.first == first else { return }
            withAnimation(.easeOut(duration: 0.15)) { self.thumbnail = representation.nsImage }
        }
    }

    func setMode(_ mode: WheelMode) {
        guard mode != self.mode else { return }
        self.mode = mode
        withAnimation(.easeOut(duration: 0.15)) {
            actions = ActionCatalog.actions(for: urls, mode: mode)
            hovered = nil
        }
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

    /// `point` is in the panel's (scaled) coordinates.
    func updateHover(at point: CGPoint) {
        let index = WheelGeometry.index(at: CGPoint(x: point.x / scale, y: point.y / scale), count: actions.count)
        guard index != hovered else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) { hovered = index }
        if index != nil && Prefs.haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    func clearHover() {
        withAnimation(.easeOut(duration: 0.12)) { hovered = nil }
    }

    #if DEBUG
    /// Puts the wheel in a given state without showing the panel, for previews and snapshot tests.
    func stage(urls: [URL], mode: WheelMode, hovered: Int?) {
        load(urls: urls, mode: mode)
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
        ActionRunner.shared.run(action, on: targets)
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

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        shrinkDragImages(sender)
        return track(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { track(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { controller?.clearHover() }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return controller?.drop(urls) ?? false
    }

    override func mouseDown(with event: NSEvent) { controller?.hide() }

    /// Swaps Finder's big preview (and its name label) for a small thumbnail beside the cursor,
    /// so the slices stay readable. Finder's own preview comes back once the drag leaves the wheel.
    private func shrinkDragImages(_ sender: NSDraggingInfo) {
        guard let controller, Prefs.shrinkDragPreview else { return }
        let image = controller.thumbnail ?? controller.icon
        let cursor = convert(sender.draggingLocation, from: nil)
        let side: CGFloat = 26
        sender.enumerateDraggingItems(options: [.clearNonenumeratedImages], for: self, classes: [NSURL.self],
                                      searchOptions: [.urlReadingFileURLsOnly: true]) { item, index, _ in
            // Stack a few small tiles just below and right of the pointer.
            let offset = CGFloat(min(index, 3)) * 4
            let frame = NSRect(x: cursor.x + 10 + offset, y: cursor.y + 14 + offset, width: side, height: side)
            item.setDraggingFrame(frame, contents: index < 4 ? image : nil)
        }
    }

    private func track(_ sender: NSDraggingInfo) -> NSDragOperation {
        controller?.updateHover(at: convert(sender.draggingLocation, from: nil))
        // Over the center nothing is selected, so releasing there cancels.
        return controller?.hovered == nil ? [] : .copy
    }
}

// MARK: - Drawing

/// Liquid glass: a glass rim with separate rounded glass slices inside it and the file in the middle.
struct WheelView: View {
    @ObservedObject var controller: WheelController
    @AppStorage(Prefs.Key.glass) private var glass = Prefs.GlassStyle.clear
    @AppStorage(Prefs.Key.hoverColor) private var hoverColor = Prefs.HoverColor.lime

    var body: some View {
        let count = controller.actions.count
        ZStack {
            Color.clear
                .frame(width: (WheelGeometry.outer + 7) * 2, height: (WheelGeometry.outer + 7) * 2)
                .glassEffect(glass == .clear ? .clear.tint(.white.opacity(0.04)) : .regular.tint(.white.opacity(0.1)), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 5)

            if count == 0 {
                Text("Nothing to do\nfor this file")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.black.opacity(0.6))
                    .offset(y: -(WheelGeometry.inner + WheelGeometry.outer) / 2)
            }

            ForEach(Array(controller.actions.enumerated()), id: \.element.id) { index, action in
                GlassSlice(action: action, index: index, count: count, mode: controller.mode,
                           isHovered: controller.hovered == index, glass: glass, hoverColor: hoverColor)
            }

            hub
        }
        .frame(width: WheelGeometry.size, height: WheelGeometry.size)
        .scaleEffect(controller.shown ? controller.scale : controller.scale * 0.6)
        .opacity(controller.shown ? 1 : 0)
        .frame(width: WheelGeometry.size * controller.scale, height: WheelGeometry.size * controller.scale)
    }

    private var hub: some View {
        let diameter = (WheelGeometry.inner - 4) * 2
        let hovered = controller.hovered.flatMap { controller.actions.indices.contains($0) ? controller.actions[$0] : nil }
        return ZStack {
            if let thumbnail = controller.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
            } else {
                Color.clear
                    .frame(width: diameter, height: diameter)
                    .glassEffect(.clear, in: Circle())
                Image(nsImage: controller.icon)
                    .resizable()
                    .frame(width: 34, height: 34)
                    .offset(y: -8)
            }
            Text(hovered?.label.uppercased() ?? controller.sizeText)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.black.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .frame(maxWidth: diameter + 8)
                .glassEffect(.regular.tint(.white.opacity(0.5)), in: Capsule())
                .offset(y: controller.thumbnail == nil ? 18 : 0)
        }
        .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1).frame(width: diameter, height: diameter))
    }
}

private struct GlassSlice: View {
    let action: LimeAction
    let index: Int
    let count: Int
    let mode: WheelMode
    let isHovered: Bool
    let glass: Prefs.GlassStyle
    let hoverColor: Prefs.HoverColor

    var body: some View {
        let step = 360 / Double(count)
        let middle = WheelGeometry.centerAngle(of: index, count: count)
        let shape = RoundedSlice(start: .degrees(middle - step / 2), end: .degrees(middle + step / 2),
                                 inner: WheelGeometry.inner, outer: WheelGeometry.outer,
                                 gap: 5, corner: count > 8 ? 8 : 11)
        let radius = (WheelGeometry.inner + WheelGeometry.outer) / 2 + 3
        let radians = middle * .pi / 180

        ZStack {
            Color.clear
                .frame(width: WheelGeometry.size, height: WheelGeometry.size)
                .glassEffect(glass == .clear ? .clear.tint(.white.opacity(0.16)) : .regular.tint(.white.opacity(0.35)), in: shape)
            // A solid fill, so the hovered slice stands out over any desktop.
            shape.fill(hoverColor.gradient)
                .opacity(isHovered ? 0.92 : 0)
            shape.stroke(.white.opacity(isHovered ? 0.9 : 0.4), lineWidth: 0.75)
            label
                .foregroundStyle(isHovered ? Theme.ink : .black.opacity(0.78))
                .offset(x: radius * cos(radians), y: radius * sin(radians))
        }
        .frame(width: WheelGeometry.size, height: WheelGeometry.size)
        .scaleEffect(isHovered ? 1.05 : 1)
    }

    @ViewBuilder private var label: some View {
        if mode == .tools {
            VStack(spacing: 2) {
                Image(systemName: action.symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(action.label.uppercased())
                    .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                    .tracking(0.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 46)
            }
        } else {
            Text(action.label.uppercased())
                .font(.system(size: count > 8 ? 10 : 12, weight: .heavy, design: .rounded))
                .tracking(0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: 46)
        }
    }
}
