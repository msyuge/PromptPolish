import Foundation
import MLX
import os

/// Выбор модели и её состояние для интерфейса. Сам движок — actor `LLMEngine`; сюда приходят только события.
///
/// Модель занимает 1–4 ГБ, а на Mac с 8 ГБ это вытесняет остальные приложения в своп. Поэтому она
/// загружается только по требованию (первый ⌥⌘P) и выгружается после простоя.
@MainActor
final class ModelStore: ObservableObject {
    /// Через сколько секунд простоя выгружать модель; 0 — никогда.
    nonisolated static let unloadDelayKey = "unloadModelAfterSeconds"
    nonisolated static let loadAtLaunchKey = "loadModelAtLaunch"
    nonisolated static let defaultUnloadDelay = 300
    nonisolated static let unloadDelayOptions: [(seconds: Int, title: String)] = [
        (60, "через 1 минуту"), (300, "через 5 минут"), (900, "через 15 минут"), (3600, "через 1 час"), (0, "никогда"),
    ]
    /// Освобождённые буферы MLX сверх этого объёма сразу возвращаются системе, а не копятся в кэше.
    private static let mlxCacheLimit = 256 * 1024 * 1024

    enum State: Equatable {
        case idle
        case downloading(fraction: Double)
        case loading
        case ready
        case failed(String)
    }

    /// Ключ сменён в 1.0.2, чтобы у всех модель выбралась заново по новым правилам (по умолчанию Qwen3.5 2B).
    private static let selectionKey = "selectedModelID.v2"

    @Published private(set) var state: State = .idle
    @Published private(set) var installed: [ModelChoice] = []
    @Published private(set) var downloads: [ModelChoice] = []
    @Published private(set) var current: ModelChoice
    /// Движок текущей модели; при смене модели создаётся новый, а старый освобождается.
    private(set) var engine: any PromptEngine

    private let locator: ModelLocator
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.alekseimaksimov.promptpolish", category: "models")
    private let physicalMemory = ProcessInfo.processInfo.physicalMemory
    /// Сколько сессий сейчас пользуются моделью: пока есть хотя бы одна, модель не выгружается.
    private var activeUses = 0
    private var lastUsed = Date()
    private var idleTimer: Timer?

    init(locator: ModelLocator = .standard, defaults: UserDefaults = .standard) {
        self.locator = locator
        self.defaults = defaults
        let appleIntelligence = AppleIntelligence.status
        let catalog = ModelCatalog.build(local: locator.scan(), physicalMemory: physicalMemory, appleIntelligence: appleIntelligence)
        let choice = ModelCatalog.resolve(
            selectedID: defaults.string(forKey: Self.selectionKey),
            installed: catalog.installed,
            downloads: catalog.downloads
        )
        installed = catalog.installed
        downloads = catalog.downloads
        current = choice
        engine = PromptEngines.make(for: choice)
        defaults.register(defaults: [Self.unloadDelayKey: Self.defaultUnloadDelay, Self.loadAtLaunchKey: false])
        Memory.cacheLimit = Self.mlxCacheLimit
        logCatalog()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.unloadIfIdle() }
        }
    }

    var loadsAtLaunch: Bool { defaults.bool(forKey: Self.loadAtLaunchKey) }

    /// Сессия улучшения начинает пользоваться моделью; если модель выгружена, она загружается.
    func beginUse() {
        activeUses += 1
        lastUsed = .now
        prepare()
    }

    /// Сессия закончилась: отсчёт простоя начинается заново, кэш буферов MLX отдаётся системе.
    func endUse() {
        activeUses = max(0, activeUses - 1)
        lastUsed = .now
        Memory.clearCache()
    }

    /// Освобождает память, занятую моделью. Следующий ⌥⌘P загрузит её снова (2–4 секунды с диска).
    func unload() {
        guard activeUses == 0 else { return }
        switch state {
        case .ready, .failed: break
        case .idle, .downloading, .loading: return
        }
        engine = PromptEngines.make(for: current)
        Memory.clearCache()
        state = .idle
        logger.notice("model unloaded: \(self.current.id, privacy: .public)")
    }

    private func unloadIfIdle() {
        guard current.usesAppMemory else { return }
        let delay = defaults.integer(forKey: Self.unloadDelayKey)
        if Self.shouldUnload(isReady: state == .ready, activeUses: activeUses, lastUsed: lastUsed, now: .now, delay: delay) {
            unload()
        }
    }

    nonisolated static func shouldUnload(isReady: Bool, activeUses: Int, lastUsed: Date, now: Date, delay: Int) -> Bool {
        isReady && activeUses == 0 && delay > 0 && now.timeIntervalSince(lastUsed) >= Double(delay)
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
        let catalog = ModelCatalog.build(local: locator.scan(), physicalMemory: physicalMemory, appleIntelligence: AppleIntelligence.status)
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
        engine = PromptEngines.make(for: choice)
        // Веса старой модели освобождаются вместе с её движком; кэш буферов MLX отдаём системе сразу.
        Memory.clearCache()
        state = .idle
        lastUsed = .now
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

    private func apply(_ event: ModelLoadEvent, from engine: any PromptEngine) {
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
        case .idle: "Модель загрузится при ⌥⌘P"
        case let .downloading(fraction): "Скачивание модели: \(Int((fraction * 100).rounded()))%"
        case .loading: "Загрузка модели…"
        case .ready: "Модель готова"
        case let .failed(message): "Ошибка модели: \(message)"
        }
    }
}
