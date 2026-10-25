import CoreGraphics

enum KeyShortcut: CaseIterable {
    case selectAll
    case copy
    case paste

    /// Виртуальные коды клавиш ANSI-раскладки; macOS сопоставляет ⌘-сочетания по ним независимо от языка ввода.
    var keyCode: CGKeyCode {
        switch self {
        case .selectAll: 0x00
        case .copy: 0x08
        case .paste: 0x09
        }
    }
}

@MainActor
protocol KeySending {
    func send(_ shortcut: KeyShortcut)
}

/// Отправляет ⌘-сочетания активному приложению через CGEvent.
@MainActor
struct CGEventKeySender: KeySending {
    func send(_ shortcut: KeyShortcut) {
        let source = CGEventSource(stateID: .privateState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: keyDown) else { continue }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }
    }
}
