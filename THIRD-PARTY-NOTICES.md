# Third-party notices

DragWheel's own code is under the [MIT License](LICENSE). The Windows app ships these components:

| Component | License | Project |
| --- | --- | --- |
| .NET runtime and WPF | MIT | https://github.com/dotnet |
| Magick.NET (with ImageMagick and its delegate libraries) | Apache-2.0, plus the ImageMagick License | https://github.com/dlemstra/Magick.NET |
| PDFsharp & MigraDoc 6.2.x (the last MIT-licensed line) | MIT | https://github.com/empira/PDFsharp |
| PdfPig | Apache-2.0 | https://github.com/UglyToad/PdfPig |
| ONNX Runtime | MIT | https://github.com/microsoft/onnxruntime |
| U²-Net (`u2netp`) model | Apache-2.0 | https://github.com/xuebinqin/U-2-Net |

Neither app bundles these tools. They are optional, and you install them yourself:

| Tool | License | Used for |
| --- | --- | --- |
| FFmpeg | LGPL/GPL, depending on the build | Video and audio on both platforms |
| libwebp `cwebp` | BSD-3-Clause | WebP on macOS |

The macOS app uses only Apple's system frameworks (AppKit, SwiftUI, ImageIO, PDFKit, Vision).
