import Foundation
import FoundationModels

/// Встроенная модель Apple Intelligence (Foundation Models, macOS 26+).
/// Её не нужно скачивать, а память под неё выделяет система, а не процесс PromptPolish.
enum AppleIntelligence {
    enum Status: Equatable, Sendable {
        case available
        /// Mac поддерживает Apple Intelligence, но она выключена в Системных настройках.
        case notEnabled
        /// Система ещё скачивает или готовит модель.
        case notReady
        /// macOS старше 26 или Mac не поддерживает Apple Intelligence.
        case unsupported
    }

    static let modelID = "apple/foundation-model"
    /// Экспериментально: русский Apple официально не поддерживает, и на русских инструкциях модель
    /// заметно чаще маленьких MLX-моделей выдаёт бессмыслицу, пустой ответ или зацикливается.
    static let displayName = "Apple Intelligence (экспериментально)"

    static var status: Status {
        guard #available(macOS 26.0, *) else { return .unsupported }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .notEnabled
        case .unavailable(.modelNotReady):
            return .notReady
        case .unavailable:
            return .unsupported
        }
    }
}

enum AppleIntelligenceError: LocalizedError {
    case notEnabled
    case notReady
    case unsupported
    case refused
    case tooLong
    case unsupportedLanguage
    case busy

    var errorDescription: String? {
        switch self {
        case .notEnabled: "Apple Intelligence выключена. Включите её в Системных настройках → Apple Intelligence и Siri или выберите другую модель."
        case .notReady: "macOS ещё готовит модель Apple Intelligence. Попробуйте позже или выберите другую модель."
        case .unsupported: "Apple Intelligence недоступна на этом Mac. Выберите другую модель в меню."
        case .refused: "Apple Intelligence отказалась обрабатывать этот текст из-за ограничений безопасности. Выберите другую модель или измените текст."
        case .tooLong: "Текст слишком длинный для Apple Intelligence (лимит 4096 токенов). Сократите его или выберите другую модель."
        case .unsupportedLanguage: "Apple Intelligence не поддерживает язык этого текста. Выберите другую модель в меню."
        case .busy: "Apple Intelligence сейчас занята. Попробуйте ещё раз через несколько секунд."
        }
    }
}

/// Генерация на Foundation Models. Диалог (инструкция, идея, вопросы, ответы) передаётся как transcript,
/// а снимки стриминга превращаются в приращения текста, как у MLX-движка.
@available(macOS 26.0, *)
final class AppleIntelligenceEngine: PromptEngine {
    func prepare(onEvent: @escaping @Sendable (ModelLoadEvent) -> Void) async throws {
        switch AppleIntelligence.status {
        case .available: return
        case .notEnabled: throw AppleIntelligenceError.notEnabled
        case .notReady: throw AppleIntelligenceError.notReady
        case .unsupported: throw AppleIntelligenceError.unsupported
        }
    }

    nonisolated func respond(to turns: [ChatTurn]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.prepare(onEvent: { _ in })
                    guard let last = turns.last, last.role == .user else {
                        throw LLMError.emptyOutput
                    }
                    let session = LanguageModelSession(transcript: Self.transcript(for: turns.dropLast()))
                    let options = GenerationOptions(temperature: 0.7, maximumResponseTokens: 1500)
                    var emitted = ""
                    for try await snapshot in session.streamResponse(to: last.content, options: options) {
                        try Task.checkCancellation()
                        let text = snapshot.content
                        // Строковые снимки только растут; если модель всё же переписала начало, ждём следующего.
                        guard text.hasPrefix(emitted), text.count > emitted.count else { continue }
                        continuation.yield(String(text.dropFirst(emitted.count)))
                        emitted = text
                    }
                    continuation.finish()
                } catch let error as LanguageModelSession.GenerationError {
                    continuation.finish(throwing: Self.describe(error))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func transcript(for turns: ArraySlice<ChatTurn>) -> Transcript {
        let entries: [Transcript.Entry] = turns.map { turn in
            let segments = [Transcript.Segment.text(Transcript.TextSegment(content: turn.content))]
            switch turn.role {
            case .system: return .instructions(Transcript.Instructions(segments: segments, toolDefinitions: []))
            case .user: return .prompt(Transcript.Prompt(segments: segments))
            case .assistant: return .response(Transcript.Response(assetIDs: [], segments: segments))
            }
        }
        return Transcript(entries: entries)
    }

    private static func describe(_ error: LanguageModelSession.GenerationError) -> Error {
        switch error {
        case .guardrailViolation, .refusal: AppleIntelligenceError.refused
        case .exceededContextWindowSize: AppleIntelligenceError.tooLong
        case .unsupportedLanguageOrLocale: AppleIntelligenceError.unsupportedLanguage
        case .assetsUnavailable: AppleIntelligenceError.notReady
        case .rateLimited, .concurrentRequests: AppleIntelligenceError.busy
        default: error
        }
    }
}
