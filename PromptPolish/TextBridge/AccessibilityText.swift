import ApplicationServices

/// Работа с текстом сфокусированного элемента через AXUIElement.
@MainActor
enum AccessibilityText {
    struct Focused {
        let element: AXUIElement
        let text: String
        let range: CFRange
        let isWholeValue: Bool
        let isWebContent: Bool
    }

    /// Сколько ждать ответа зависшего приложения, прежде чем перейти к буферу обмена.
    private static let messagingTimeout: Float = 0.5
    private static let editableRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole]

    /// Читает выделенный текст сфокусированного поля, а если выделения нет — всё его значение.
    static func readFocused(pid: pid_t) throws -> Focused? {
        enableElectronAccessibility(pid: pid)

        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        guard let element: AXUIElement = attribute(kAXFocusedUIElementAttribute, of: systemWide) else { return nil }
        AXUIElementSetMessagingTimeout(element, messagingTimeout)

        let role: String? = attribute(kAXRoleAttribute, of: element)
        let subrole: String? = attribute(kAXSubroleAttribute, of: element)
        if role == "AXSecureTextField" || subrole == kAXSecureTextFieldSubrole {
            throw TextBridgeError.secureField
        }

        let isWebContent = hasWebAreaAncestor(element)

        if let selected: String = attribute(kAXSelectedTextAttribute, of: element),
           !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let range = selectedRange(of: element) {
            return Focused(element: element, text: selected, range: range, isWholeValue: false, isWebContent: isWebContent)
        }

        guard let role, editableRoles.contains(role) || isSettable(kAXValueAttribute, of: element),
              let value: String = attribute(kAXValueAttribute, of: element),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let whole = CFRange(location: 0, length: (value as NSString).length)
        return Focused(element: element, text: value, range: whole, isWholeValue: true, isWebContent: isWebContent)
    }

    /// Заменяет диапазон текста и проверяет, что новое значение действительно появилось в поле.
    static func replace(in element: AXUIElement, range: CFRange, with text: String) -> Bool {
        var range = range
        guard let rangeValue = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue) == .success,
              AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success,
              let value: String = attribute(kAXValueAttribute, of: element) else { return false }
        return value.contains(text)
    }

    /// Восстанавливает выделение перед вставкой через буфер обмена; ошибки не критичны.
    static func select(_ range: CFRange, in element: AXUIElement) {
        var range = range
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return }
        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
    }

    /// Electron-приложения (в том числе десктопный Claude) строят дерево Accessibility только по этому флагу.
    private static func enableElectronAccessibility(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    private static func hasWebAreaAncestor(_ element: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        for _ in 0..<40 {
            guard let node = current else { return false }
            if attribute(kAXRoleAttribute, of: node) as String? == "AXWebArea" { return true }
            current = attribute(kAXParentAttribute, of: node)
        }
        return false
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        guard let value: AXValue = attribute(kAXSelectedTextRangeAttribute, of: element) else { return nil }
        var range = CFRange()
        return AXValueGetValue(value, .cfRange, &range) ? range : nil
    }

    private static func isSettable(_ name: String, of element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }

    private static func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
