//
//  DocumentEditors.swift
//  Lime
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Metadata

struct MetadataEditor: View {
    let url: URL
    @ObservedObject var session: EditorSession
    @State private var info: MetadataTool.Info?
    @State private var removeLocation = false
    @State private var failure: String?

    var body: some View {
        EditorShell(title: "Metadata", session: session, applyTitle: "Save Copy", canApply: info != nil, onApply: save) {
            VStack(alignment: .leading, spacing: 12) {
                if let info {
                    SectionTitle("Edit")
                    ForEach(info.fields.indices, id: \.self) { index in
                        HStack {
                            Text(info.fields[index].label).frame(width: 96, alignment: .leading)
                            TextField(info.fields[index].label, text: binding(index))
                                .textFieldStyle(.roundedBorder)
                        }
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                    }
                    if info.hasLocation || FileKind.of(url) == .image {
                        Toggle(info.hasLocation ? "Remove location (GPS)" : "No location saved in this file",
                               isOn: $removeLocation)
                            .toggleStyle(.checkbox)
                            .disabled(!info.hasLocation)
                    }
                    SectionTitle("Everything in this file")
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(info.rows) { row in
                                HStack(alignment: .top) {
                                    Text("\(row.group) · \(row.key)")
                                        .foregroundStyle(Theme.ink.opacity(0.7))
                                        .frame(width: 210, alignment: .leading)
                                    Text(row.value)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .padding(.vertical, 4)
                                .padding(.horizontal, 10)
                            }
                        }
                    }
                    .background(.white.opacity(0.35), in: .rect(cornerRadius: 12))
                } else if let failure {
                    Text(failure).font(.system(size: 14, weight: .semibold, design: .rounded))
                } else {
                    ProgressView()
                }
            }
        } controls: {
            Button("Remove All") {
                let url = url
                session.apply { [try await MetadataTool.strip(url)] }
            }
            .buttonStyle(GlassPillButtonStyle())
            .disabled(info == nil)
        }
        .task {
            do {
                info = try await MetadataTool.read(url)
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    private func binding(_ index: Int) -> Binding<String> {
        Binding(get: { info?.fields[index].value ?? "" }, set: { info?.fields[index].value = $0 })
    }

    private func save() {
        guard let info else { return }
        let url = url, removeLocation = removeLocation
        let fields = Dictionary(uniqueKeysWithValues: info.fields.map { ($0.key, $0.value) })
        session.apply { [try await MetadataTool.save(url, fields: fields, removeLocation: removeLocation)] }
    }
}

// MARK: - Organize PDF

struct PDFOrganizer: View {
    private struct Page: Identifiable {
        let id = UUID()
        let index: Int
        let thumbnail: NSImage
        var rotation = 0
    }

    let url: URL
    @ObservedObject var session: EditorSession
    @State private var pages: [Page] = []

    var body: some View {
        EditorShell(title: "Organize PDF", session: session, canApply: !pages.isEmpty, onApply: apply) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Drag pages to reorder. Rotate or remove them with the buttons.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 14)], spacing: 14) {
                        ForEach(pages) { page in
                            cell(page)
                                .draggable(page.id.uuidString)
                                .dropDestination(for: String.self) { items, _ in
                                    return move(items.first, before: page.id)
                                }
                        }
                    }
                    .padding(4)
                }
            }
        } controls: {
            Text("\(pages.count) pages").font(.caption.weight(.semibold))
        }
        .task {
            let url = url
            let images = (try? await offMain { try PDFConverter.thumbnails(url, size: 220) }) ?? []
            pages = images.enumerated().map { Page(index: $0.offset, thumbnail: $0.element) }
        }
    }

    private func cell(_ page: Page) -> some View {
        VStack(spacing: 6) {
            Image(nsImage: page.thumbnail)
                .resizable()
                .scaledToFit()
                .rotationEffect(.degrees(Double(page.rotation)))
                .frame(height: 150)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
            HStack(spacing: 6) {
                Text("\(page.index + 1)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Spacer()
                Button {
                    if let i = pages.firstIndex(where: { $0.id == page.id }) { pages[i].rotation = (pages[i].rotation + 90) % 360 }
                } label: {
                    Image(systemName: "rotate.right")
                }
                .accessibilityLabel("Rotate page \(page.index + 1)")
                Button {
                    pages.removeAll { $0.id == page.id }
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Remove page \(page.index + 1)")
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(.white.opacity(0.35), in: .rect(cornerRadius: 12))
    }

    private func move(_ id: String?, before target: UUID) -> Bool {
        guard let id, let from = pages.firstIndex(where: { $0.id.uuidString == id }),
              let to = pages.firstIndex(where: { $0.id == target }), from != to else { return false }
        withAnimation(.spring(response: 0.3)) {
            let page = pages.remove(at: from)
            pages.insert(page, at: to)
        }
        return true
    }

    private func apply() {
        let url = url
        let choices = pages.map { PDFConverter.PageChoice(index: $0.index, rotation: $0.rotation) }
        session.apply { [try await offMain { try PDFConverter.reorganize(url, pages: choices) }] }
    }
}
