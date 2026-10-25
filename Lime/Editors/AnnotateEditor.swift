//
//  AnnotateEditor.swift
//  Lime
//

import AppKit
import SwiftUI

struct AnnotateEditor: View {
    typealias Mark = ImageTools.Mark

    let url: URL
    @ObservedObject var session: EditorSession
    @State private var preview: NSImage?
    @State private var marks: [Mark] = []
    @State private var current: Mark?
    @State private var tool = Mark.Kind.arrow
    @State private var color = RGBA(hex: 0xE53935)
    @State private var lineWidth = 5.0
    @State private var text = ""

    private static let palette: [RGBA] = [0xE53935, 0x7CC822, 0xFDD835, 0x1E88E5, 0xFFFFFF, 0x111111].map(RGBA.init(hex:))

    var body: some View {
        EditorShell(title: "Annotate", session: session, canApply: !marks.isEmpty, onApply: apply) {
            VStack(spacing: 12) {
                toolbar
                PreviewBox {
                    GeometryReader { geometry in
                        let fit = fittedRect(preview?.size ?? .zero, in: geometry.size)
                        if let preview {
                            ZStack {
                                Image(nsImage: preview).resizable()
                                Canvas { context, size in
                                    for mark in marks + (current.map { [$0] } ?? []) {
                                        draw(mark, in: &context, size: size)
                                    }
                                }
                            }
                            .frame(width: fit.width, height: fit.height)
                            .contentShape(Rectangle())
                            .gesture(drawGesture(fit.size))
                            .position(x: fit.midX, y: fit.midY)
                        }
                    }
                }
                .frame(height: 440)
            }
        } controls: {
            Button("Undo") { _ = marks.popLast() }
                .buttonStyle(GlassPillButtonStyle())
                .disabled(marks.isEmpty)
            Button("Clear") { marks.removeAll() }
                .buttonStyle(GlassPillButtonStyle())
                .disabled(marks.isEmpty)
        }
        .task {
            let url = url
            preview = (try? await offMain { try ImageTools.previewImage(url) }).flatMap(ImageTools.nsImage)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Tool", selection: $tool) {
                Image(systemName: "pencil.tip").tag(Mark.Kind.pen).help("Pen")
                Image(systemName: "highlighter").tag(Mark.Kind.highlighter).help("Highlighter")
                Image(systemName: "arrow.up.right").tag(Mark.Kind.arrow).help("Arrow")
                Image(systemName: "rectangle").tag(Mark.Kind.box).help("Box")
                Image(systemName: "textformat").tag(Mark.Kind.text).help("Text")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)

            HStack(spacing: 6) {
                ForEach(Self.palette, id: \.self) { swatch in
                    Button {
                        color = swatch
                    } label: {
                        Circle()
                            .fill(Color(cgColor: swatch.cgColor))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1))
                            .padding(2)
                            .overlay(Circle().strokeBorder(Theme.ink, lineWidth: color == swatch ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Color")
                }
            }

            if tool == .text {
                TextField("Type, then click the photo", text: $text)
                    .textFieldStyle(.roundedBorder)
            } else {
                Slider(value: $lineWidth, in: 2...16)
                    .frame(maxWidth: 140)
                    .help("Line width")
            }
        }
    }

    private func drawGesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = CGPoint(x: min(max(value.location.x / size.width, 0), 1),
                                    y: min(max(value.location.y / size.height, 0), 1))
                guard tool != .text else { return }
                if current == nil {
                    let start = CGPoint(x: value.startLocation.x / size.width, y: value.startLocation.y / size.height)
                    current = Mark(kind: tool, points: [start], color: color, width: lineWidth / size.width)
                }
                switch tool {
                case .pen, .highlighter: current?.points.append(point)
                default: current?.points = [current?.points.first ?? point, point]
                }
            }
            .onEnded { value in
                if tool == .text {
                    guard !text.isEmpty else { return }
                    let point = CGPoint(x: value.location.x / size.width, y: value.location.y / size.height)
                    marks.append(Mark(kind: .text, points: [point], color: color, width: 5 / size.width, text: text))
                    text = ""
                } else if let current {
                    marks.append(current)
                }
                current = nil
            }
    }

    private func draw(_ mark: Mark, in context: inout GraphicsContext, size: CGSize) {
        let swatch = Color(cgColor: mark.color.cgColor)
        if mark.kind == .text {
            guard let point = mark.points.first else { return }
            context.draw(Text(mark.text).font(.system(size: mark.fontSize(in: size), weight: .bold)).foregroundColor(swatch),
                         at: CGPoint(x: point.x * size.width, y: point.y * size.height), anchor: .leading)
            return
        }
        let style = StrokeStyle(lineWidth: mark.strokeWidth(in: size), lineCap: .round, lineJoin: .round)
        context.stroke(Path(mark.path(in: size)), with: .color(mark.kind == .highlighter ? swatch.opacity(0.4) : swatch), style: style)
    }

    private func apply() {
        let url = url, marks = marks
        session.apply { [try await offMain { try ImageTools.applyAnnotations(url, marks: marks) }] }
    }
}
