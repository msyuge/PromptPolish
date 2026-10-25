import AppKit

/// Системные инструкции по чатам: стандартные из ресурсов приложения и правки пользователя поверх них.
/// Правки хранятся как `SystemPrompt-<чат>.txt` в `~/Library/Application Support/PromptPolish/SystemPrompts`,
/// поэтому переживают переустановку и их можно править в любом редакторе.
@MainActor
final class SystemPromptStore: ObservableObject {
    @Published private(set) var overrides: [ChatTarget: String] = [:]

    let defaults: [ChatTarget: String]
    let directory: URL

    init(defaults: [ChatTarget: String], directory: URL = SystemPromptStore.standardDirectory) {
        self.defaults = defaults
        self.directory = directory
        reload()
    }

    /// Стандартные инструкции из бандла; их отсутствие — дефект сборки.
    static func bundled() -> SystemPromptStore {
        let builder = PromptBuilder.bundledOrFail()
        let defaults = Dictionary(uniqueKeysWithValues: ChatTarget.allCases.map { ($0, builder.systemPrompt(for: $0)) })
        return SystemPromptStore(defaults: defaults)
    }

    nonisolated static let standardDirectory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "PromptPolish/SystemPrompts")

    /// Инструкции, с которыми сейчас работает утилита.
    var builder: PromptBuilder {
        PromptBuilder(systemPrompts: Dictionary(uniqueKeysWithValues: ChatTarget.allCases.map { ($0.rawValue, text(for: $0)) }))
    }

    func text(for target: ChatTarget) -> String {
        overrides[target] ?? defaults[target] ?? ""
    }

    func isCustomized(_ target: ChatTarget) -> Bool {
        overrides[target] != nil
    }

    func fileURL(for target: ChatTarget) -> URL {
        directory.appending(path: "SystemPrompt-\(target.rawValue).txt")
    }

    /// Сохраняет правку. Пустой текст или текст, совпадающий со стандартным, означает «без правки».
    func save(_ text: String, for target: ChatTarget) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != defaults[target] else {
            try reset(target)
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try trimmed.write(to: fileURL(for: target), atomically: true, encoding: .utf8)
        overrides[target] = trimmed
    }

    /// Возвращает стандартную инструкцию.
    func reset(_ target: ChatTarget) throws {
        let url = fileURL(for: target)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
        overrides[target] = nil
    }

    /// Перечитывает правки с диска — на случай, если файл изменили во внешнем редакторе.
    func reload() {
        var loaded: [ChatTarget: String] = [:]
        for target in ChatTarget.allCases {
            guard let text = try? String(contentsOf: fileURL(for: target), encoding: .utf8) else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { loaded[target] = trimmed }
        }
        overrides = loaded
    }

    /// Показывает файл правки в Finder (или папку, если правки ещё нет).
    func revealInFinder(_ target: ChatTarget) {
        let url = fileURL(for: target)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(directory)
        }
    }
}
