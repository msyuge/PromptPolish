import Foundation
import MLX
import os

/// Выбор модели и её состояние для интерфейса. Сам движок — actor `LLMEngine`; сюда приходят только события.
@MainActor
final class ModelStore: ObservableObject {
    enum State: Equatable {
        case idle
        case downloading(fraction: Double)
        case loading
        case ready
        case failed(String)
    }

    private static let selectionKey = "selectedModelID"

    @Published private(set) var state: State = .idle
    @Published private(set) var installed: [ModelChoice] = []
    @Published private(set) var downloads: [ModelChoice] = []
    @Published private(set) var current: ModelChoice
    /// Движок текущей модели; при смене модели создаётся новый, а старый освобождается.
    private(set) var engine: LLMEngine

    private let locator: ModelLocator
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.alekseimaksimov.promptpolish", category: "models")
    private let physicalMemory = ProcessInfo.processInfo.physicalMemory

    init(locator: ModelLocator = .standard, defaults: UserDefaults = .standard) {
        self.locator = locator
        self.defaults = defaults
        let catalog = ModelCatalog.build(local: locator.scan(), physicalMemory: physicalMemory)
        let choice = ModelCatalog.resolve(
            selectedID: defaults.string(forKey: Self.selectionKey),
            installed: catalog.installed,
            downloads: catalog.downloads
        )
        installed = catalog.installed
        downloads = catalog.downloads
        current = choice
        engine = LLMEngine(spec: ModelSpec(for: choice))
        logCatalog()
    }

    private func logCatalog() {
        let installedIDs = installed.map { "\($0.id) [\($0.sourceLabel)]" }.joined(separator: ", ")
        let downloadIDs = downloads.map(\.id).joined(separator: ", ")
        logger.notice("catalog: installed=\(installedIDs, privacy: .public); downloads=\(downloadIDs, privacy: .public); current=\(self.current.id, privacy: .public)")
    }

    func fitsMemory(_ choice: ModelChoice) -> Bool {
        ModelCatalog.fitsMemory(sizeBytes: choice.sizeBytes, physicalMemory: physicalMemory)
    }

    /// Пересканирует диск: после скачивания модель переезжает из «Скачать» в установленные.
    func refreshCatalog() {
        let catalog = ModelCatalog.build(local: locator.scan(), physicalMemory: physicalMemory)
        installed = catalog.installed
        downloads = catalog.downloads
        if let copy = catalog.installed.first(where: { $0.id == current.id }) {
            current = copy
        }
        logCatalog()
    }

    /// Переключает модель: старая выгружается из памяти, новая находится на диске или скачивается.
    func select(_ choice: ModelChoice) {
        guard choice != current else { return }
        current = choice
        defaults.set(choice.id, forKey: Self.selectionKey)
        logger.notice("model selected: \(choice.id, privacy: .public) [\(choice.sourceLabel, privacy: .public)]")
        engine = LLMEngine(spec: ModelSpec(for: choice))
        // Веса старой модели освобождаются вместе с её движком; кэш буферов MLX отдаём системе сразу.
        Memory.clearCache()
        state = .idle
        prepare()
    }

    /// Запускает скачивание и загрузку, если модель ещё не готова и не загружается.
    func prepare() {
        switch state {
        case .idle, .failed: break
        case .downloading, .loading, .ready: return
        }
        state = .loading
        let engine = engine
        let wasDownload = !current.isInstalled
        Task {
            do {
                try await engine.prepare { event in
                    Task { @MainActor in self.apply(event, from: engine) }
                }
                // Пока модель грузилась, пользователь мог выбрать другую — её состояние не трогаем.
                guard engine === self.engine else { return }
                state = .ready
                logger.notice("model ready: \(self.current.id, privacy: .public)")
                if wasDownload { refreshCatalog() }
            } catch {
                guard engine === self.engine else { return }
                state = .failed(error.localizedDescription)
                logger.error("model failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func apply(_ event: LLMEngine.LoadEvent, from engine: LLMEngine) {
        guard engine === self.engine else { return }
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
