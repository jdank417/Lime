//
//  EditorWindow.swift
//  Lime
//

import AppKit
import Combine
import SwiftUI

/// Connects a tool's window to the action waiting on it: Apply delivers files, closing cancels.
@MainActor
final class EditorSession: ObservableObject {
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?

    fileprivate var continuation: CheckedContinuation<[URL], Error>?
    fileprivate var window: EditorWindow?

    /// Runs the tool's work with a spinner showing; on success the window closes with the results.
    func apply(_ work: @escaping () async throws -> [URL]) {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                finish(.success(try await work()))
            } catch {
                isWorking = false
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Closes a window that produced nothing to show, like the QR reader.
    func close() { finish(.success([])) }

    func cancel() { finish(.failure(CancellationError())) }

    fileprivate func finish(_ result: Result<[URL], Error>) {
        guard let continuation else { return }
        self.continuation = nil
        if let window {
            window.onClose = nil
            window.close()
            Editor.forget(window)
        }
        window = nil
        continuation.resume(with: result)
    }
}

final class EditorWindow: NSWindow {
    var onClose: (() -> Void)?

    override func close() {
        let callback = onClose
        onClose = nil
        super.close()
        callback?()
    }

    override func cancelOperation(_ sender: Any?) { close() }
}

@MainActor
enum Editor {
    private static var open: [EditorWindow] = []

    /// Shows a tool window and waits until it's applied (its output files) or closed (CancellationError).
    static func present<Content: View>(width: CGFloat, height: CGFloat,
                                       @ViewBuilder content: (EditorSession) -> Content) async throws -> [URL] {
        let session = EditorSession()
        let window = EditorWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: content(session).frame(width: width, height: height))
        host.sizingOptions = []
        window.contentView = host
        window.center()

        open.append(window)
        return try await withCheckedThrowingContinuation { continuation in
            session.continuation = continuation
            session.window = window
            window.onClose = { [weak session] in session?.cancel() }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }

    fileprivate static func forget(_ window: EditorWindow) {
        open.removeAll { $0 === window }
    }
}

// MARK: - Shared pieces

/// The frame every tool window uses: close button and title on top, content, then the Apply row.
struct EditorShell<Content: View, Controls: View>: View {
    let title: String
    @ObservedObject var session: EditorSession
    var applyTitle = "Apply"
    var canApply = true
    /// nil hides the Apply button (viewer-style windows).
    var onApply: (() -> Void)?
    @ViewBuilder var content: Content
    @ViewBuilder var controls: Controls

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                HStack {
                    Button {
                        session.cancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .background(.white.opacity(0.35), in: Circle())
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close")
                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            Rectangle().fill(Theme.ink.opacity(0.12)).frame(height: 1)

            content
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Rectangle().fill(Theme.ink.opacity(0.12)).frame(height: 1)
            HStack(spacing: 10) {
                controls
                Spacer(minLength: 8)
                if let message = session.errorMessage {
                    Text(message)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red: 0.55, green: 0.05, blue: 0.05))
                        .lineLimit(2)
                }
                if session.isWorking { ProgressView().controlSize(.small) }
                if let onApply {
                    Button(applyTitle, action: onApply)
                        .buttonStyle(LimeProminentButtonStyle())
                        .keyboardShortcut(.defaultAction)
                        .disabled(session.isWorking || !canApply)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
        }
        .foregroundStyle(Theme.ink)
        .tint(Theme.limeDeep)
        .background(LimeWindowBackground())
    }
}

extension EditorShell where Controls == EmptyView {
    init(title: String, session: EditorSession, applyTitle: String = "Apply", canApply: Bool = true,
         onApply: (() -> Void)?, @ViewBuilder content: () -> Content) {
        self.init(title: title, session: session, applyTitle: applyTitle, canApply: canApply, onApply: onApply,
                  content: content, controls: { EmptyView() })
    }
}

/// Dark rounded box that media previews sit in.
struct PreviewBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack { content }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(10)
            .background(Color(red: 0.06, green: 0.08, blue: 0.05).opacity(0.88), in: .rect(cornerRadius: 16))
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.limeDeep)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Exposure ——●—— 0.00 EV ↺"
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var defaultValue: Double = 0
    var format: (Double) -> String = { String(format: "%+.0f", $0) }

    var body: some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 96, alignment: .leading)
            Slider(value: $value, in: range)
            Text(format(value))
                .monospacedDigit()
                .frame(width: 62, alignment: .trailing)
            Button {
                value = defaultValue
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.plain)
            .opacity(value == defaultValue ? 0.35 : 1)
            .accessibilityLabel("Reset \(title)")
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
    }
}

/// Where an image of `size` lands when scaled to fit inside `container`.
func fittedRect(_ size: CGSize, in container: CGSize) -> CGRect {
    guard size.width > 0, size.height > 0 else { return .zero }
    let scale = min(container.width / size.width, container.height / size.height)
    let fitted = CGSize(width: size.width * scale, height: size.height * scale)
    return CGRect(x: (container.width - fitted.width) / 2, y: (container.height - fitted.height) / 2,
                  width: fitted.width, height: fitted.height)
}

func formatTime(_ seconds: Double) -> String {
    let total = max(seconds, 0)
    let minutes = Int(total) / 60
    let rest = total - Double(minutes * 60)
    return String(format: "%d:%05.2f", minutes, rest)
}
