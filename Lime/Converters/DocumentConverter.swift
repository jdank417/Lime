//
//  DocumentConverter.swift
//  Lime
//

import AppKit

/// Text documents via NSAttributedString. Stays on the main actor: HTML import and printing need it.
enum DocumentConverter {
    struct Target {
        let label: String
        let ext: String
        /// nil means PDF, which goes through the print system so pages break properly.
        let type: NSAttributedString.DocumentType?
    }

    static let targets: [Target] = [
        .init(label: "PDF", ext: "pdf", type: nil),
        .init(label: "DOCX", ext: "docx", type: .officeOpenXML),
        .init(label: "RTF", ext: "rtf", type: .rtf),
        .init(label: "TXT", ext: "txt", type: .plain),
        .init(label: "HTML", ext: "html", type: .html),
        .init(label: "ODT", ext: "odt", type: .openDocument),
        .init(label: "DOC", ext: "doc", type: .docFormat),
    ]

    static func convert(_ url: URL, to target: Target) throws -> URL {
        let text = try load(url)
        let out = Output.url(for: url, ext: target.ext)
        try write(text, to: out, type: target.type)
        return out
    }

    static func load(_ url: URL) throws -> NSAttributedString {
        if normalizedExtension(of: url) == "md" {
            let data = try Data(contentsOf: url)
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            if let parsed = try? NSAttributedString(markdown: data, options: options, baseURL: url) {
                return styledMarkdown(parsed)
            }
        }
        return try NSAttributedString(url: url, options: [:], documentAttributes: nil)
    }

    static func write(_ text: NSAttributedString, to url: URL, type: NSAttributedString.DocumentType?) throws {
        guard let type else { return try writePDF(text, to: url) }
        var attributes: [NSAttributedString.DocumentAttributeKey: Any] = [.documentType: type]
        if type == .plain || type == .html {
            attributes[.characterEncoding] = String.Encoding.utf8.rawValue
        }
        let data = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: attributes)
        try data.write(to: url)
    }

    private static func writePDF(_ text: NSAttributedString, to url: URL) throws {
        let info = NSPrintInfo(dictionary: [.jobSavingURL: url])
        info.jobDisposition = .save
        info.paperSize = NSSize(width: 612, height: 792)
        for margin in [\NSPrintInfo.topMargin, \.bottomMargin, \.leftMargin, \.rightMargin] {
            info[keyPath: margin] = 54
        }
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false

        let textView = NSTextView(usingTextLayoutManager: false)
        textView.frame = NSRect(x: 0, y: 0, width: info.paperSize.width - 108, height: 100)
        // Without this, dark mode would print white text.
        textView.appearance = NSAppearance(named: .aqua)
        textView.textStorage?.setAttributedString(text)
        textView.isVerticallyResizable = true
        if let container = textView.textContainer, let layout = textView.layoutManager {
            layout.ensureLayout(for: container)
            textView.frame.size.height = max(layout.usedRect(for: container).height, 100)
        }

        let operation = NSPrintOperation(view: textView, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else { throw LimeError.failed("Couldn't create the PDF") }
    }

    /// Markdown parsing only records *intent*; turn it into real fonts so RTF/DOCX/PDF show it.
    private static func styledMarkdown(_ parsed: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: parsed)
        let full = NSRange(location: 0, length: result.length)
        let base = NSFont.systemFont(ofSize: 13)
        result.addAttribute(.font, value: base, range: full)
        result.enumerateAttribute(NSAttributedString.Key("NSInlinePresentationIntent"), in: full) { value, range, _ in
            guard let raw = (value as? NSNumber)?.uintValue else { return }
            let intent = InlinePresentationIntent(rawValue: raw)
            var font = base
            if intent.contains(.code) {
                font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            }
            var traits: NSFontDescriptor.SymbolicTraits = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if intent.contains(.emphasized) { traits.insert(.italic) }
            if !traits.isEmpty {
                font = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
            }
            result.addAttribute(.font, value: font, range: range)
        }
        return result
    }
}
