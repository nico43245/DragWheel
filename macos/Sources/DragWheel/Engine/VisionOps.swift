import AppKit
import CoreImage
import Vision

/// On-device machine learning: text recognition and subject cut-out.
enum VisionOps {
    /// Recognizes text in an image (Romanian + English first, then automatic).
    static func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = ["ro-RO", "en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    /// Removes the background around the main subject(s), keeping transparency.
    static func removeBackground(_ input: URL) throws -> URL {
        let image = try ImageOps.loadCGImage(input)
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            throw DragWheelError.message("No clear subject found in \(input.lastPathComponent).")
        }
        let masked = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: false)
        let ciImage = CIImage(cvPixelBuffer: masked)
        guard let cg = CIContext().createCGImage(ciImage, from: ciImage.extent) else {
            throw DragWheelError.message("Couldn't render the cut-out.")
        }
        let output = OutputNaming.file(for: input, suffix: "_nobg", ext: "png")
        try ImageOps.writeCGImage(cg, to: output, type: .png)
        return output
    }
}
