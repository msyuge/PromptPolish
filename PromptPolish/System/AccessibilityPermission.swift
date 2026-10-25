import AppKit
import ApplicationServices

/// Состояние разрешения Accessibility. Пока доступа нет, раз в секунду перепроверяет его,
/// потому что macOS не присылает уведомление о выдаче разрешения.
@MainActor
final class AccessibilityPermission: ObservableObject {
    @Published private(set) var isTrusted: Bool = AXIsProcessTrusted()

    private var pollTimer: Timer?

    init() {
        if !isTrusted { startPolling() }
    }

    /// Показывает системный запрос и открывает нужный раздел System Settings.
    func request() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        guard !isTrusted else { return }
        openSystemSettings()
        startPolling()
    }

    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        isTrusted = AXIsProcessTrusted()
        if isTrusted {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }
}
