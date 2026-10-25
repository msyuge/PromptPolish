import AppKit

/// Полная копия содержимого pasteboard: все элементы и все их типы в исходном порядке.
struct PasteboardSnapshot: Equatable {
    struct Entry: Equatable {
        let type: NSPasteboard.PasteboardType
        let data: Data
    }

    let items: [[Entry]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { Entry(type: type, data: $0) }
            }
        }
        return PasteboardSnapshot(items: items.filter { !$0.isEmpty })
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let objects = items.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for entry in entries {
                item.setData(entry.data, forType: entry.type)
            }
            return item
        }
        pasteboard.writeObjects(objects)
    }
}

extension NSPasteboard.PasteboardType {
    /// Соглашение nspasteboard.org: менеджеры буфера обмена не сохраняют такие записи в историю.
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
}
