import AppKit

/// Текст, взятый из поля ввода активного приложения, и всё, что нужно, чтобы потом заменить его.
@MainActor
struct CapturedText {
    enum Source {
        /// Прочитан через Accessibility. `range` — заменяемый диапазон в UTF-16, `isWholeValue` —
        /// выделения не было и взято всё поле, `isWebContent` — элемент внутри AXWebArea.
        case accessibility(element: AXUIElement, range: CFRange, isWholeValue: Bool, isWebContent: Bool)
        /// Скопирован через ⌘C (`selectedAll` — перед этим понадобился ⌘A).
        case clipboard(selectedAll: Bool)
    }

    let text: String
    let app: NSRunningApplication
    let source: Source
    /// Адрес страницы, если поле внутри веб-контента.
    let pageURL: URL?
    /// Где показать панель превью, в координатах AppKit.
    let anchor: CGRect?
}

enum TextBridgeError: LocalizedError, Equatable {
    case noFrontmostApp
    case secureField
    case noText
    case targetAppGone

    var errorDescription: String? {
        switch self {
        case .noFrontmostApp: "Не удалось определить активное приложение."
        case .secureField: "Поле пароля: текст недоступен."
        case .noText: "Не нашёл текст: выделите промт в поле ввода."
        case .targetAppGone: "Приложение с полем ввода закрыто."
        }
    }
}

@MainActor
protocol TextBridge {
    func capture() async throws -> CapturedText
    func replace(_ captured: CapturedText, with text: String) async throws
}
