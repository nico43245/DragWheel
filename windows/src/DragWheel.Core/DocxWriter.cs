using System.IO.Compression;
using System.Text;
using ImageMagick;

namespace DragWheel.Core;

/// <summary>Writes minimal Word documents (images and/or plain paragraphs) as an Office Open XML package.</summary>
public static class DocxWriter
{
    private const double EmuPerPixel = 9525;              // at 96 dpi
    private const double MaxWidthEmu = 9638.0 * 635;      // A4 width minus 2 cm margins, twips → EMU
    private const double MaxHeightEmu = 14570.0 * 635;

    public static void Images(IReadOnlyList<string> inputs, string output) => Write(output, inputs, []);

    public static void Paragraphs(IEnumerable<string> paragraphs, string output) => Write(output, [], paragraphs);

    private static void Write(string output, IReadOnlyList<string> images, IEnumerable<string> paragraphs)
    {
        var body = new StringBuilder();
        var rels = new StringBuilder();
        var media = new List<(string Name, byte[] Data)>();

        for (var i = 0; i < images.Count; i++)
        {
            var n = i + 1;
            using var image = new MagickImage(images[i]);
            image.AutoOrient();
            var png = image.ToByteArray(MagickFormat.Png);
            media.Add(($"word/media/image{n}.png", png));

            double w = image.Width * EmuPerPixel, h = image.Height * EmuPerPixel;
            var fit = Math.Min(1, Math.Min(MaxWidthEmu / w, MaxHeightEmu / h));
            long cx = (long)Math.Round(w * fit), cy = (long)Math.Round(h * fit);

            rels.Append($"""<Relationship Id="rIdImg{n}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image{n}.png"/>""");
            body.Append($"""
                <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="{cx}" cy="{cy}"/><wp:docPr id="{n}" name="Picture {n}"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="{n}" name="image{n}.png"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="rIdImg{n}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
                """);
        }

        foreach (var paragraph in paragraphs)
        {
            if (paragraph == "\f")
            {
                body.Append("""<w:p><w:r><w:br w:type="page"/></w:r></w:p>""");
                continue;
            }
            body.Append("<w:p><w:r><w:t xml:space=\"preserve\">").Append(Text.XmlEscape(paragraph)).Append("</w:t></w:r></w:p>");
        }

        var document = $"""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>{body}<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="0" w:footer="0" w:gutter="0"/></w:sectPr></w:body></w:document>
            """;

        var temp = output + ".partial";
        using (var zip = ZipFile.Open(temp, ZipArchiveMode.Create))
        {
            Entry(zip, "[Content_Types].xml", """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>
                """);
            Entry(zip, "_rels/.rels", """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
                """);
            Entry(zip, "word/_rels/document.xml.rels", $"""
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">{rels}</Relationships>
                """);
            Entry(zip, "word/document.xml", document);
            foreach (var (name, data) in media)
            {
                using var s = zip.CreateEntry(name, CompressionLevel.NoCompression).Open();
                s.Write(data);
            }
        }
        File.Move(temp, output, overwrite: true);
    }

    private static void Entry(ZipArchive zip, string name, string content)
    {
        using var writer = new StreamWriter(zip.CreateEntry(name, CompressionLevel.Optimal).Open(), new UTF8Encoding(false));
        writer.Write(content);
    }
}
