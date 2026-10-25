import SwiftUI

struct MenuContent: View {
    @ObservedObject var coordinator: ImproveCoordinator
    @ObservedObject var permission: AccessibilityPermission
    @Environment(\.openSettings) private var openSettings

    init(coordinator: ImproveCoordinator) {
        self.coordinator = coordinator
        self.permission = coordinator.permission
    }

    var body: some View {
        Button("Улучшить промт") {
            coordinator.improvePrompt()
        }
        .disabled(!permission.isTrusted)

        if !permission.isTrusted {
            Button("Выдать доступ к Accessibility…") {
                permission.request()
            }
        }

        Divider()

        Button("Настройки…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")

        Button("Выход") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
