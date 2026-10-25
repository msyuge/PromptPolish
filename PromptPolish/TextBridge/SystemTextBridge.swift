import AppKit
import os

/// Читает текст через Accessibility, а если приложение его не отдаёт — через ⌘C.
/// Заменяет через Accessibility только в нативных полях: в веб-контенте и Electron прямая запись
/// в AX не доходит до состояния JS-фреймворка, поэтому там всегда используется вставка ⌘V.
@MainActor
final class SystemTextBridge: TextBridge {
    private let clipboard: ClipboardTextTransfer
    private let logger = Logger(subsystem: "com.alekseimaksimov.promptpolish", category: "textbridge")

    init(clipboard: ClipboardTextTransfer = ClipboardTextTransfer()) {
        self.clipboard = clipboard
    }

    func capture() async throws -> CapturedText {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw TextBridgeError.noFrontmostApp
        }
        try await waitForModifiersReleased()

        if let focused = try AccessibilityText.readFocused(pid: app.processIdentifier) {
            logger.notice("capture via AX, length=\(focused.text.count), whole=\(focused.isWholeValue), web=\(focused.isWebContent), app=\(app.bundleIdentifier ?? "?", privacy: .public)")
            return CapturedText(
                text: focused.text,
                app: app,
                source: .accessibility(
                    element: focused.element,
                    range: focused.range,
                    isWholeValue: focused.isWholeValue,
                    isWebContent: focused.isWebContent
                ),
                pageURL: focused.pageURL,
                anchor: focused.anchor
            )
        }

        let context = AccessibilityText.focusedContext()
        let copied = try await clipboard.copySelection(selectAllIfEmpty: true)
        logger.notice("capture via clipboard, length=\(copied.text.count), selectedAll=\(copied.selectedAll), app=\(app.bundleIdentifier ?? "?", privacy: .public)")
        return CapturedText(
            text: copied.text,
            app: app,
            source: .clipboard(selectedAll: copied.selectedAll),
            pageURL: context.pageURL,
            anchor: context.anchor
        )
    }

    func replace(_ captured: CapturedText, with text: String) async throws {
        try await activate(captured.app)

        switch captured.source {
        case let .accessibility(element, range, isWholeValue, isWebContent):
            if !isWebContent, AccessibilityText.replace(in: element, range: range, with: text) {
                logger.notice("replace via AX")
                return
            }
            if !isWholeValue {
                AccessibilityText.select(range, in: element)
            }
            try await clipboard.paste(text, selectAll: isWholeValue)
            logger.notice("replace via clipboard after AX capture, selectAll=\(isWholeValue)")

        case let .clipboard(selectedAll):
            try await clipboard.paste(text, selectAll: selectedAll)
            logger.notice("replace via clipboard, selectAll=\(selectedAll)")
        }
    }

    /// Хоткей срабатывает, пока ⌥⌘ ещё могут быть зажаты; синтетический ⌘C смешался бы с ними.
    private func waitForModifiersReleased() async throws {
        let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift, .maskControl]
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while clock.now < deadline, !CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty {
            try await Task.sleep(for: .milliseconds(15))
        }
    }

    private func activate(_ app: NSRunningApplication) async throws {
        guard !app.isTerminated else { throw TextBridgeError.targetAppGone }
        guard !app.isActive else { return }
        app.activate()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .milliseconds(800))
        while clock.now < deadline, !app.isActive {
            try await Task.sleep(for: .milliseconds(15))
        }
        try await Task.sleep(for: .milliseconds(80))
    }
}
