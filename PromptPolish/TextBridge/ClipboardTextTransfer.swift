import AppKit

/// Чтение и вставка текста через ⌘A/⌘C/⌘V. Исходное содержимое буфера обмена
/// восстанавливается после каждой операции, в том числе при ошибке и отмене задачи.
@MainActor
final class ClipboardTextTransfer {
    struct Timing {
        var pollInterval: Duration = .milliseconds(15)
        var copyTimeout: Duration = .milliseconds(600)
        /// Сколько ждать после ⌘V, прежде чем вернуть буфер: приложение читает его асинхронно.
        var pasteSettle: Duration = .milliseconds(350)
        var afterSelectAll: Duration = .milliseconds(60)
    }

    private let pasteboard: NSPasteboard
    private let keys: KeySending
    private let timing: Timing

    init(pasteboard: NSPasteboard = .general, keys: KeySending = CGEventKeySender(), timing: Timing = Timing()) {
        self.pasteboard = pasteboard
        self.keys = keys
        self.timing = timing
    }

    /// Копирует выделение. Если выделения нет и `selectAllIfEmpty`, выделяет всё поле и копирует его.
    func copySelection(selectAllIfEmpty: Bool) async throws -> (text: String, selectedAll: Bool) {
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        defer { snapshot.restore(to: pasteboard) }

        if let text = try await copyOnce() {
            return (text, false)
        }
        guard selectAllIfEmpty else { throw TextBridgeError.noText }

        keys.send(.selectAll)
        try await Task.sleep(for: timing.afterSelectAll)
        if let text = try await copyOnce() {
            return (text, true)
        }
        throw TextBridgeError.noText
    }

    /// Вставляет текст на место выделения (или всего поля, если `selectAll`).
    func paste(_ text: String, selectAll: Bool) async throws {
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        defer { snapshot.restore(to: pasteboard) }

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: .transient)
        pasteboard.writeObjects([item])

        if selectAll {
            keys.send(.selectAll)
            try await Task.sleep(for: timing.afterSelectAll)
        }
        keys.send(.paste)
        try await Task.sleep(for: timing.pasteSettle)
    }

    /// Очищает буфер, отправляет ⌘C и ждёт, пока приложение положит туда непустой текст.
    private func copyOnce() async throws -> String? {
        pasteboard.clearContents()
        let baseline = pasteboard.changeCount
        keys.send(.copy)

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timing.copyTimeout)
        while clock.now < deadline {
            if pasteboard.changeCount != baseline,
               let text = pasteboard.string(forType: .string),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
            try await Task.sleep(for: timing.pollInterval)
        }
        return nil
    }
}
