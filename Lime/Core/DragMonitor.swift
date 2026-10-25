//
//  DragMonitor.swift
//  Lime
//

import AppKit

/// Notices when the user drags files anywhere on the Mac while holding Shift or Option.
///
/// It polls instead of using event monitors: during another app's drag session the mouse
/// events go to that app, but the button state, modifiers and drag pasteboard are global.
@MainActor
final class DragMonitor {
    var onStart: (_ urls: [URL], _ mode: WheelMode, _ location: NSPoint) -> Void = { _, _, _ in }
    var onModeChange: (WheelMode) -> Void = { _ in }
    var onEnd: () -> Void = {}

    var isEnabled: () -> Bool = { true }

    private var timer: Timer?
    private var wasPressed = false
    private var dragCountAtPress = 0
    private var active = false
    private var mode: WheelMode = .convert
    private let dragPasteboard = NSPasteboard(name: .drag)

    func start() {
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let pressed = NSEvent.pressedMouseButtons & 1 != 0
        defer { wasPressed = pressed }

        if !pressed {
            if active {
                active = false
                onEnd()
            }
            return
        }
        if !wasPressed {
            // A drag writes to the drag pasteboard; remember where it stood when the button went down.
            dragCountAtPress = dragPasteboard.changeCount
            return
        }

        let flags = NSEvent.modifierFlags
        let held: WheelMode? = flags.contains(.option) ? .tools : flags.contains(.shift) ? .convert : nil

        if active {
            if let held, held != mode {
                mode = held
                onModeChange(held)
            }
            return
        }

        guard let held, isEnabled(), dragPasteboard.changeCount != dragCountAtPress,
              dragPasteboard.types?.contains(.fileURL) == true else { return }
        let urls = dragPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return }
        active = true
        mode = held
        onStart(urls, held, NSEvent.mouseLocation)
    }
}
