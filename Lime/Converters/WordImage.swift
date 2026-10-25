//
//  WordImage.swift
//  Lime
//

import CoreGraphics
import Foundation

/// Builds a .docx holding one picture. AppKit's Word writer drops images, so this writes the
/// handful of XML parts a Word document needs and zips them with the picture.
nonisolated enum WordImage {
    static func document(for url: URL) async throws -> URL {
        let image = try ImageConverter.render(ImageConverter.load(url))
        let png = try ImageTools.encode(image, as: ImageConverter.png, quality: 1)

        // Fit the page's 6.5" text width; Word measures in EMUs (914,400 per inch).
        let emuPerPixel = 9525.0
        let maxWidth = 6.5 * 914_400
        let scale = min(1, maxWidth / (Double(image.width) * emuPerPixel))
        let cx = Int(Double(image.width) * emuPerPixel * scale), cy = Int(Double(image.height) * emuPerPixel * scale)

        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let parts: [String: Data] = [
            "[Content_Types].xml": Data(contentTypes.utf8),
            "_rels/.rels": Data(packageRels.utf8),
            "word/_rels/document.xml.rels": Data(documentRels.utf8),
            "word/document.xml": Data(body(cx: cx, cy: cy, name: url.lastPathComponent).utf8),
            "word/media/image1.png": png,
        ]
        for (path, data) in parts {
            let file = scratch.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
        }
        let out = Output.url(for: url, ext: "docx")
        try await ArchiveTool.run("/usr/bin/zip", ["-q", "-X", "-r", out.path, "[Content_Types].xml", "_rels", "word"], in: scratch)
        return out
    }

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Default Extension="png" ContentType="image/png"/>
    <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    </Types>
    """

    private static let packageRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """

    private static let documentRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rIdImage1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.png"/>
    </Relationships>
    """

    private static func body(cx: Int, cy: Int, name: String) -> String {
        let safeName = name.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
          xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
          xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
          xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
        <w:body><w:p><w:r><w:drawing>
        <wp:inline><wp:extent cx="\(cx)" cy="\(cy)"/><wp:docPr id="1" name="\(safeName)"/>
        <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
        <pic:pic><pic:nvPicPr><pic:cNvPr id="1" name="\(safeName)"/><pic:cNvPicPr/></pic:nvPicPr>
        <pic:blipFill><a:blip r:embed="rIdImage1"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>
        <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>
        </pic:pic></a:graphicData></a:graphic></wp:inline>
        </w:drawing></w:r></w:p>
        <w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>
        </w:body></w:document>
        """
    }
}
