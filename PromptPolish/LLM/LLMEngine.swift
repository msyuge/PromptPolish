import Foundation
import MLXLLM
import MLXLMCommon

/// Модель и параметры генерации.
struct ModelSpec: Sendable {
    let id: String
    let displayName: String
    let approximateSize: String
    let extraEOSTokens: Set<String>
    /// Параметры шаблона чата (например, отключение режима рассуждений у Qwen3.5).
    let templateContext: [String: Bool]
    let parameters: GenerateParameters

    /// Qwen3.5 4B (март 2026): ≈3 ГБ весов — помещается на Mac с 8 ГБ памяти вместе с браузером.
    /// Рассуждения отключены: для переписывания промта они только замедляют ответ.
    static let qwen35_4B = ModelSpec(
        id: "mlx-community/Qwen3.5-4B-4bit",
        displayName: "Qwen3.5 4B (4-bit)",
        approximateSize: "≈3 ГБ",
        extraEOSTokens: ["<|im_end|>"],
        templateContext: ["enable_thinking": false],
        parameters: GenerateParameters(maxTokens: 1500, temperature: 0.7, topP: 0.8, topK: 20)
    )

    static let `default` = qwen35_4B
    static let all: [ModelSpec] = [.qwen35_4B]

    var configuration: ModelConfiguration {
        ModelConfiguration(id: id, extraEOSTokens: extraEOSTokens)
    }
}

/// Локальная генерация через MLX. Модель загружается один раз; параллельные вызовы `prepare`
/// ждут одну и ту же загрузку. Вся работа идёт вне main thread.
actor LLMEngine {
    enum LoadEvent: Sendable {
        case downloading(fraction: Double)
        case loading
    }

    nonisolated let spec: ModelSpec

    private var container: ModelContainer?
    private var loadTask: Task<ModelContainer, Error>?

    init(spec: ModelSpec = .default) {
        self.spec = spec
    }

    var isLoaded: Bool { container != nil }

    /// Скачивает модель (если её нет в кэше) и загружает её в память.
    func prepare(onEvent: @escaping @Sendable (LoadEvent) -> Void = { _ in }) async throws {
        _ = try await loadedContainer(onEvent: onEvent)
    }

    /// Стримит ответ модели на диалог кусками текста. Отмена задачи-потребителя останавливает генерацию.
    nonisolated func respond(to turns: [ChatTurn]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.generate(turns) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func generate(_ turns: [ChatTurn], onChunk: @Sendable (String) -> Void) async throws {
        let container = try await loadedContainer(onEvent: { _ in })
        let chat: [Chat.Message] = turns.map { turn in
            switch turn.role {
            case .system: .system(turn.content)
            case .user: .user(turn.content)
            case .assistant: .assistant(turn.content)
            }
        }
        let context: [String: any Sendable] = spec.templateContext
        let input = try await container.prepare(input: UserInput(chat: chat, additionalContext: context))
        let stream = try await container.generate(input: input, parameters: spec.parameters)
        for await event in stream {
            try Task.checkCancellation()
            if let chunk = event.chunk {
                onChunk(chunk)
            }
        }
        try Task.checkCancellation()
    }

    private func loadedContainer(onEvent: @escaping @Sendable (LoadEvent) -> Void) async throws -> ModelContainer {
        if let container { return container }
        if let loadTask { return try await loadTask.value }

        let configuration = spec.configuration
        let task = Task<ModelContainer, Error> {
            let container = try await LLMModelFactory.shared.loadContainer(
                from: HubSnapshotDownloader(),
                using: TransformersTokenizerLoader(),
                configuration: configuration,
                progressHandler: { progress in
                    let fraction = progress.fractionCompleted
                    onEvent(fraction < 1 ? .downloading(fraction: fraction) : .loading)
                }
            )
            return container
        }
        loadTask = task
        do {
            let loaded = try await task.value
            container = loaded
            loadTask = nil
            return loaded
        } catch {
            loadTask = nil
            throw error
        }
    }
}
