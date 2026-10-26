import AppKit

/// Системные инструкции по чатам и языкам: стандартные из ресурсов приложения и правки пользователя поверх них.
/// Правки хранятся как `SystemPrompt-<чат>-<язык>.txt` в `~/Library/Application Support/PromptPolish/SystemPrompts`,
/// поэтому переживают переустановку и их можно править в любом редакторе.
@MainActor
final class SystemPromptStore: ObservableObject {
    struct Key: Hashable, Sendable {
        let target: ChatTarget
        let language: PromptLanguage
    }

    @Published private(set) var overrides: [Key: String] = [:]

    let defaults: [Key: String]
    let directory: URL

    init(defaults: [Key: String], directory: URL = SystemPromptStore.standardDirectory) {
        self.defaults = defaults
        self.directory = directory
        reload()
    }

    /// Стандартные инструкции из бандла; их отсутствие — дефект сборки.
    static func bundled() -> SystemPromptStore {
        let builder = PromptBuilder.bundledOrFail()
        var defaults: [Key: String] = [:]
        for target in ChatTarget.allCases {
            for language in PromptLanguage.allCases {
                defaults[Key(target: target, language: language)] = builder.systemPrompt(for: target, language: language)
            }
        }
        return SystemPromptStore(defaults: defaults)
    }

    nonisolated static let standardDirectory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "PromptPolish/SystemPrompts")

    /// Инструкции, с которыми сейчас работает утилита.
    var builder: PromptBuilder {
        var prompts: [String: String] = [:]
        for target in ChatTarget.allCases {
            for language in PromptLanguage.allCases {
                prompts[PromptBuilder.key(target, language)] = text(for: target, language: language)
            }
        }
        return PromptBuilder(systemPrompts: prompts)
    }

    func text(for target: ChatTarget, language: PromptLanguage) -> String {
        let key = Key(target: target, language: language)
        return overrides[key] ?? defaults[key] ?? ""
    }

    func isCustomized(_ target: ChatTarget, language: PromptLanguage) -> Bool {
        overrides[Key(target: target, language: language)] != nil
    }

    func fileURL(for target: ChatTarget, language: PromptLanguage) -> URL {
        directory.appending(path: "SystemPrompt-\(PromptBuilder.key(target, language)).txt")
    }

    /// Сохраняет правку. Пустой текст или текст, совпадающий со стандартным, означает «без правки».
    func save(_ text: String, for target: ChatTarget, language: PromptLanguage) throws {
        let key = Key(target: target, language: language)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != defaults[key] else {
            try reset(target, language: language)
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try trimmed.write(to: fileURL(for: target, language: language), atomically: true, encoding: .utf8)
        overrides[key] = trimmed
    }

    /// Возвращает стандартную инструкцию.
    func reset(_ target: ChatTarget, language: PromptLanguage) throws {
        let url = fileURL(for: target, language: language)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
        overrides[Key(target: target, language: language)] = nil
    }

    /// Перечитывает правки с диска — на случай, если файл изменили во внешнем редакторе.
    func reload() {
        var loaded: [Key: String] = [:]
        for target in ChatTarget.allCases {
            for language in PromptLanguage.allCases {
                guard let text = try? String(contentsOf: fileURL(for: target, language: language), encoding: .utf8) else { continue }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { loaded[Key(target: target, language: language)] = trimmed }
            }
        }
        overrides = loaded
    }

    /// Показывает файл правки в Finder (или папку, если правки ещё нет).
    func revealInFinder(_ target: ChatTarget, language: PromptLanguage) {
        let url = fileURL(for: target, language: language)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(directory)
        }
    }
}
