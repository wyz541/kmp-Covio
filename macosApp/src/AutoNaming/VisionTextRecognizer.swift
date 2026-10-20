import CoreGraphics
import Foundation
import Vision

/// Vision 文本识别的共享入口。
///
/// 剪贴板、图片命名和扫描 PDF 使用同一组语言与采样设置。
enum VisionTextRecognizer {
    static let languages = ["zh-Hans", "en-US"]

    static func recognizeText(in fileURL: URL) -> String {
        let request = makeRequest()
        let handler = VNImageRequestHandler(url: fileURL, options: [:])
        return perform(request, with: handler)
    }

    static func recognizeText(in image: CGImage) -> String {
        let request = makeRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        return perform(request, with: handler)
    }

    private static func makeRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = false
        return request
    }

    private static func perform(
        _ request: VNRecognizeTextRequest,
        with handler: VNImageRequestHandler
    ) -> String {
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        let observations = request.results ?? []
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
