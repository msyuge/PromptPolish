import AppKit
@testable import PromptPolish

extension NSPasteboard {
    static func makeUnique() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("PromptPolishTests.\(UUID().uuidString)"))
    }
}

extension NSPasteboard.PasteboardType {
    static let custom = NSPasteboard.PasteboardType("com.alekseimaksimov.promptpolish.tests.custom")
}

/// Заполняет буфер «пользовательскими» данными: два элемента, у первого три типа.
@MainActor
func fillWithUserContent(_ pasteboard: NSPasteboard) {
    pasteboard.clearContents()
    let first = NSPasteboardItem()
    first.setString("user text", forType: .string)
    first.setString("<b>user text</b>", forType: .html)
    first.setData(Data([0x00, 0xFF, 0x10]), forType: .custom)
    let second = NSPasteboardItem()
    second.setString("https://example.com", forType: .URL)
    pasteboard.writeObjects([first, second])
}

/// Имитирует приложение с полем ввода: реагирует на ⌘A/⌘C/⌘V как текстовое поле.
@MainActor
final class FakeTextField: KeySending {
    let pasteboard: NSPasteboard
    var fieldText: String
    var selection: String?
    private(set) var sent: [KeyShortcut] = []
    private(set) var pasted: [String] = []

    init(pasteboard: NSPasteboard, fieldText: String, selection: String? = nil) {
        self.pasteboard = pasteboard
        self.fieldText = fieldText
        self.selection = selection
    }

    func send(_ shortcut: KeyShortcut) {
        sent.append(shortcut)
        switch shortcut {
        case .selectAll:
            selection = fieldText.isEmpty ? nil : fieldText
        case .copy:
            guard let selection else { return }
            pasteboard.clearContents()
            pasteboard.setString(selection, forType: .string)
        case .paste:
            if let text = pasteboard.string(forType: .string) {
                pasted.append(text)
            }
        }
    }
}

extension ClipboardTextTransfer.Timing {
    static let fast = ClipboardTextTransfer.Timing(
        pollInterval: .milliseconds(1),
        copyTimeout: .milliseconds(50),
        pasteSettle: .milliseconds(5),
        afterSelectAll: .milliseconds(1)
    )
}
