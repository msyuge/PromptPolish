import Foundation

/// Модель, которую можно выбрать в меню: уже лежащая на диске или доступная для скачивания.
struct ModelChoice: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        /// Встроенная модель Apple Intelligence: её не нужно скачивать, память выделяет macOS.
        case system
        case lmStudio(URL)
        case huggingFaceCache(URL)
        case download
    }

    /// Имя репозитория — одно и то же для копии в LM Studio, в кэше и для скачивания.
    let id: String
    let name: String
    let sizeBytes: Int64
    let modelType: String?
    let source: Source

    var directory: URL? {
        switch source {
        case let .lmStudio(url), let .huggingFaceCache(url): url
        case .system, .download: nil
        }
    }

    var isInstalled: Bool {
        if case .download = source { return false }
        return true
    }

    /// Модель Apple живёт в памяти системы, а не процесса PromptPolish: выгружать её нечего.
    var usesAppMemory: Bool {
        if case .system = source { return false }
        return true
    }

    var sizeLabel: String {
        if case .system = source { return "встроена в macOS" }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var sourceLabel: String {
        switch source {
        case .system: "встроена в macOS"
        case .lmStudio: "LM Studio"
        case .huggingFaceCache: "кэш Hugging Face"
        case .download: "будет скачана"
        }
    }

    var locationDescription: String {
        switch source {
        case .system: "Встроенная модель Apple Intelligence: скачивать не нужно, память выделяет macOS."
        case let .lmStudio(url): "LM Studio: \(url.path(percentEncoded: false))"
        case let .huggingFaceCache(url): "Кэш Hugging Face: \(url.path(percentEncoded: false))"
        case .download: "Будет скачана с Hugging Face (\(sizeLabel))"
        }
    }
}

/// Какие модели показать в меню и какую выбрать по умолчанию.
enum ModelCatalog {
    struct Downloadable: Sendable {
        let id: String
        let name: String
        let sizeBytes: Int64
        let modelType: String
    }

    /// Модель по умолчанию (решение пользователя): 4B слишком долго качается, а 0.8B в прогоне делала
    /// слабые промты и переносила в них содержание примеров из инструкций.
    static let defaultID = "mlx-community/Qwen3.5-2B-MLX-4bit"

    /// Проверенные MLX-модели, которые поддерживает mlx-swift-lm, от маленьких к большим. Размеры — суммарный объём весов.
    static let downloadable: [Downloadable] = [
        Downloadable(id: "mlx-community/Qwen3.5-0.8B-MLX-4bit", name: "Qwen3.5 0.8B", sizeBytes: 650_000_000, modelType: "qwen3_5"),
        Downloadable(id: "mlx-community/Qwen3.5-2B-MLX-4bit", name: "Qwen3.5 2B", sizeBytes: 1_750_000_000, modelType: "qwen3_5"),
        Downloadable(id: "mlx-community/Qwen3.5-4B-MLX-4bit", name: "Qwen3.5 4B", sizeBytes: 3_060_000_000, modelType: "qwen3_5"),
        Downloadable(id: "mlx-community/gemma-4-e2b-it-4bit", name: "Gemma 4 E2B", sizeBytes: 3_580_000_000, modelType: "gemma4"),
        Downloadable(id: "mlx-community/gemma-4-e4b-it-4bit", name: "Gemma 4 E4B", sizeBytes: 5_180_000_000, modelType: "gemma4"),
        Downloadable(id: "mlx-community/Qwen3.5-9B-MLX-4bit", name: "Qwen3.5 9B", sizeBytes: 5_980_000_000, modelType: "qwen3_5"),
    ]

    /// Модель помещается, если вместе с ~3 ГБ на систему и браузер и ~15% на KV-кэш
    /// не превышает физическую память. На 8 ГБ это модели до ~4,8 ГБ весов.
    static func fitsMemory(sizeBytes: Int64, physicalMemory: UInt64) -> Bool {
        Double(sizeBytes) * 1.15 + 3e9 <= Double(physicalMemory)
    }

    static let appleIntelligence = ModelChoice(
        id: AppleIntelligence.modelID,
        name: AppleIntelligence.displayName,
        sizeBytes: 0,
        modelType: nil,
        source: .system
    )

    /// Установленные модели (копия LM Studio важнее копии в кэше, Apple Intelligence последней)
    /// и то, что ещё можно скачать. Apple Intelligence показывается, если Mac её поддерживает,
    /// даже выключенную: при выборе утилита подскажет, как её включить.
    static func build(
        local: [LocalModel],
        physicalMemory: UInt64,
        appleIntelligence: AppleIntelligence.Status = .unsupported
    ) -> (installed: [ModelChoice], downloads: [ModelChoice]) {
        var installed: [String: ModelChoice] = [:]
        for model in local {
            let source: ModelChoice.Source = model.source == .lmStudio ? .lmStudio(model.directory) : .huggingFaceCache(model.directory)
            let choice = ModelChoice(
                id: model.repoID,
                name: displayName(for: model.repoID),
                sizeBytes: model.sizeBytes,
                modelType: model.modelType,
                source: source
            )
            if let existing = installed[model.repoID], case .lmStudio = existing.source { continue }
            installed[model.repoID] = choice
        }
        let downloads = downloadable
            .filter { installed[$0.id] == nil && fitsMemory(sizeBytes: $0.sizeBytes, physicalMemory: physicalMemory) }
            .map { ModelChoice(id: $0.id, name: $0.name, sizeBytes: $0.sizeBytes, modelType: $0.modelType, source: .download) }
        let sortedInstalled = installed.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let system = appleIntelligence == .unsupported ? [] : [Self.appleIntelligence]
        return (sortedInstalled + system, downloads)
    }

    /// Сохранённый выбор, если он ещё доступен; иначе MLX-модель, которая уже лежит на диске
    /// (сначала модель по умолчанию, потом проверенные из каталога, потом любая), чтобы ничего не качать;
    /// и только если на диске пусто — скачивание модели по умолчанию. Apple Intelligence по умолчанию
    /// не выбирается: на русском она слишком часто выдаёт бессмыслицу.
    static func resolve(selectedID: String?, installed: [ModelChoice], downloads: [ModelChoice]) -> ModelChoice {
        let all = installed + downloads
        if let selectedID, let choice = all.first(where: { $0.id == selectedID }) {
            return choice
        }
        let local = installed.filter { $0.source != .system }
        if let choice = local.first(where: { $0.id == defaultID }) {
            return choice
        }
        if let choice = downloadable.lazy.compactMap({ known in local.first { $0.id == known.id } }).first {
            return choice
        }
        if let choice = local.first {
            return choice
        }
        if let choice = downloads.first(where: { $0.id == defaultID }) {
            return choice
        }
        let fallback = downloadable[0]
        return ModelChoice(id: fallback.id, name: fallback.name, sizeBytes: fallback.sizeBytes, modelType: fallback.modelType, source: .download)
    }

    /// Имя для меню: известные модели — по каталогу, остальные — по имени папки.
    static func displayName(for repoID: String) -> String {
        downloadable.first { $0.id == repoID }?.name ?? (repoID.components(separatedBy: "/").last ?? repoID)
    }
}
