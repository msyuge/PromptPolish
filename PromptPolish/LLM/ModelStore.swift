import Foundation

/// Состояние модели для интерфейса. Сам движок — actor `LLMEngine`; сюда приходят только события.
@MainActor
final class ModelStore: ObservableObject {
    enum State: Equatable {
        case idle
        case downloading(fraction: Double)
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    let engine: LLMEngine

    init(engine: LLMEngine) {
        self.engine = engine
    }

    var spec: ModelSpec { engine.spec }

    /// Запускает скачивание и загрузку, если модель ещё не готова и не загружается.
    func prepare() {
        switch state {
        case .idle, .failed: break
        case .downloading, .loading, .ready: return
        }
        state = .loading
        Task {
            do {
                try await engine.prepare { event in
                    Task { @MainActor in self.apply(event) }
                }
                state = .ready
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func apply(_ event: LLMEngine.LoadEvent) {
        switch state {
        case .downloading, .loading: break
        case .idle, .ready, .failed: return
        }
        switch event {
        case let .downloading(fraction): state = .downloading(fraction: fraction)
        case .loading: state = .loading
        }
    }
}

extension ModelStore.State {
    var statusText: String {
        switch self {
        case .idle: "Модель не загружена"
        case let .downloading(fraction): "Скачивание модели: \(Int((fraction * 100).rounded()))%"
        case .loading: "Загрузка модели…"
        case .ready: "Модель готова"
        case let .failed(message): "Ошибка модели: \(message)"
        }
    }
}
