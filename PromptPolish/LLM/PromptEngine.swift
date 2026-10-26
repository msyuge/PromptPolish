import Foundation

enum ModelLoadEvent: Sendable {
    case downloading(fraction: Double)
    case loading
}

/// Движок, который превращает диалог в поток текста: локальная MLX-модель или Apple Intelligence.
protocol PromptEngine: AnyObject, Sendable {
    /// Готовит модель: скачивает и загружает её (MLX) или проверяет доступность (Apple Intelligence).
    func prepare(onEvent: @escaping @Sendable (ModelLoadEvent) -> Void) async throws

    /// Стримит ответ модели кусками текста. Отмена задачи-потребителя останавливает генерацию.
    func respond(to turns: [ChatTurn]) -> AsyncThrowingStream<String, Error>
}

enum PromptEngines {
    /// Движок для выбранной модели. Apple Intelligence — только на macOS 26+, иначе остаётся MLX.
    static func make(for choice: ModelChoice) -> any PromptEngine {
        if case .system = choice.source, #available(macOS 26.0, *) {
            return AppleIntelligenceEngine()
        }
        return LLMEngine(spec: ModelSpec(for: choice))
    }
}
