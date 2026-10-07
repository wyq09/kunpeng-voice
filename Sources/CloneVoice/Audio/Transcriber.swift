import Foundation
import Speech

/// Transcribes uploaded samples so users never have to type what they said.
enum Transcriber {
    enum Failure: LocalizedError {
        case denied
        case unavailable

        var errorDescription: String? {
            switch self {
            case .denied: "没有语音识别权限，请在下方手动填写音频里说的话。"
            case .unavailable: "没能自动识别，请在下方手动填写音频里说的话。"
            }
        }
    }

    static func transcribe(_ url: URL) async throws -> String {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { throw Failure.denied }

        let locale = Locale.preferredLanguages.first.map(Locale.init(identifier:)) ?? Locale(identifier: "zh-CN")
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
              recognizer.isAvailable
        else { throw Failure.unavailable }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }
                if let result, result.isFinal {
                    hasResumed = true
                    let text = result.bestTranscription.formattedString
                    text.isEmpty
                        ? continuation.resume(throwing: Failure.unavailable)
                        : continuation.resume(returning: text)
                } else if error != nil {
                    hasResumed = true
                    continuation.resume(throwing: Failure.unavailable)
                }
            }
        }
    }
}
