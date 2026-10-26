import Foundation
import MLXLLM
import MLXLMCommon

/// Модель и параметры генерации.
struct ModelSpec: Sendable {
    /// Репозиторий Hugging Face, из которого модель скачивается, если её нет на диске.
    let id: String
    let displayName: String
    /// Папка с уже скачанной моделью (LM Studio или кэш Hugging Face).
    let directory: URL?
    let extraEOSTokens: Set<String>
    /// Параметры шаблона чата: рассуждения Qwen3/3.5 отключены, для переписывания промта они только замедляют ответ.
    /// Шаблоны других моделей лишний параметр игнорируют.
    let templateContext: [String: Bool]
    let parameters: GenerateParameters

    init(for choice: ModelChoice) {
        id = choice.id
        displayName = choice.name
        directory = choice.directory
        extraEOSTokens = Self.endOfTurnTokens(modelType: choice.modelType)
        templateContext = ["enable_thinking": false]
        parameters = GenerateParameters(maxTokens: 1500, temperature: 0.7, topP: 0.8, topK: 20)
    }

    /// Токены конца реплики, которых может не быть среди EOS в конфиге модели.
    static func endOfTurnTokens(modelType: String?) -> Set<String> {
        guard let modelType else { return [] }
        if modelType.hasPrefix("qwen") { return ["<|im_end|>"] }
        if modelType.hasPrefix("gemma4") { return ["<turn|>"] }
        if modelType.hasPrefix("gemma") { return ["<end_of_turn>"] }
        return []
    }

    var configuration: ModelConfiguration {
        if let directory {
            return ModelConfiguration(directory: directory, extraEOSTokens: extraEOSTokens)
        }
        return ModelConfiguration(id: id, extraEOSTokens: extraEOSTokens)
    }
}

/// Локальная генерация через MLX. Модель загружается один раз; параллельные вызовы `prepare`
/// ждут одну и ту же загрузку. Вся работа идёт вне main thread.
actor LLMEngine: PromptEngine {
    nonisolated let spec: ModelSpec

    private var container: ModelContainer?
    private var loadTask: Task<ModelContainer, Error>?

    init(spec: ModelSpec) {
        self.spec = spec
    }

    /// Загружает модель из её папки или сначала скачивает с Hugging Face.
    func prepare(onEvent: @escaping @Sendable (ModelLoadEvent) -> Void = { _ in }) async throws {
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

    private func loadedContainer(onEvent: @escaping @Sendable (ModelLoadEvent) -> Void) async throws -> ModelContainer {
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
