import Foundation
import MLXLLM
import MLXLMCommon

/// Модель и параметры генерации.
struct ModelSpec: Sendable {
    let id: String
    let displayName: String
    let approximateSize: String
    let extraEOSTokens: Set<String>

    static let qwen25_3B = ModelSpec(
        id: "mlx-community/Qwen2.5-3B-Instruct-4bit",
        displayName: "Qwen2.5 3B Instruct (4-bit)",
        approximateSize: "≈1,7 ГБ",
        extraEOSTokens: ["<|im_end|>"]
    )

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
    private let builder: PromptBuilder
    private let parameters = GenerateParameters(maxTokens: 1024, temperature: 0.3, topP: 0.9, repetitionPenalty: 1.05)

    private var container: ModelContainer?
    private var loadTask: Task<ModelContainer, Error>?

    init(spec: ModelSpec = .qwen25_3B, builder: PromptBuilder) {
        self.spec = spec
        self.builder = builder
    }

    var isLoaded: Bool { container != nil }

    /// Скачивает модель (если её нет в кэше) и загружает её в память.
    func prepare(onEvent: @escaping @Sendable (LoadEvent) -> Void = { _ in }) async throws {
        _ = try await loadedContainer(onEvent: onEvent)
    }

    /// Стримит улучшенную версию промта кусками текста. Отмена задачи-потребителя останавливает генерацию.
    nonisolated func improve(_ prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.generate(prompt) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func generate(_ prompt: String, onChunk: @Sendable (String) -> Void) async throws {
        let container = try await loadedContainer(onEvent: { _ in })
        let chat: [Chat.Message] = builder.messages(for: prompt).map { turn in
            switch turn.role {
            case .system: .system(turn.content)
            case .user: .user(turn.content)
            }
        }
        let input = try await container.prepare(input: UserInput(chat: chat))
        let stream = try await container.generate(input: input, parameters: parameters)
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
