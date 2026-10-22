import Foundation
import ImageIO

/// Writes a minimal Word document holding images, one per paragraph, scaled to fit an A4 page.
/// (AppKit's own DOCX export drops image attachments, so we assemble the OOXML package ourselves.)
enum DocxWriter {
    private static let emuPerPixel = 9525.0            // at 96 dpi
    private static let maxWidthEMU = 9638.0 * 635       // A4 width minus 2 cm margins, twips → EMU
    private static let maxHeightEMU = 14570.0 * 635

    static func imagesToDocx(_ inputs: [URL], output: URL) async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("dragwheel-docx-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        for dir in ["_rels", "word/_rels", "word/media"] {
            try fm.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
        }

        var relationships = ""
        var paragraphs = ""
        for (index, input) in inputs.enumerated() {
            let n = index + 1
            let image = try ImageOps.loadCGImage(input)
            try ImageOps.writeCGImage(image, to: root.appendingPathComponent("word/media/image\(n).png"), type: .png)

            var w = Double(image.width) * emuPerPixel
            var h = Double(image.height) * emuPerPixel
            let fit = min(1, maxWidthEMU / w, maxHeightEMU / h)
            w = (w * fit).rounded(); h = (h * fit).rounded()

            relationships += #"<Relationship Id="rIdImg\#(n)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image\#(n).png"/>"#
            paragraphs += """
            <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">\
            <wp:extent cx="\(Int(w))" cy="\(Int(h))"/><wp:docPr id="\(n)" name="Picture \(n)"/>\
            <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic>\
            <pic:nvPicPr><pic:cNvPr id="\(n)" name="image\(n).png"/><pic:cNvPicPr/></pic:nvPicPr>\
            <pic:blipFill><a:blip r:embed="rIdImg\(n)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>\
            <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(Int(w))" cy="\(Int(h))"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>\
            </pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
            """
        }

        let files: [String: String] = [
            "[Content_Types].xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
            <Default Extension="xml" ContentType="application/xml"/>\
            <Default Extension="png" ContentType="image/png"/>\
            <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
            </Types>
            """,
            "_rels/.rels": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>\
            </Relationships>
            """,
            "word/_rels/document.xml.rels": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(relationships)</Relationships>
            """,
            "word/document.xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
            xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" \
            xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
            xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">\
            <w:body>\(paragraphs)<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>\
            <w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="0" w:footer="0" w:gutter="0"/>\
            </w:sectPr></w:body></w:document>
            """,
        ]
        for (path, text) in files {
            try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }

        try await ProcessRunner.run("/usr/bin/zip", ["-X", "-q", "-r", output.path,
                                                     "[Content_Types].xml", "_rels", "word"], in: root)
    }
}
