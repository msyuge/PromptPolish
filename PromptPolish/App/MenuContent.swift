import SwiftUI

struct MenuContent: View {
    @ObservedObject var coordinator: ImproveCoordinator
    @ObservedObject var permission: AccessibilityPermission
    @ObservedObject var models: ModelStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    init(coordinator: ImproveCoordinator) {
        self.coordinator = coordinator
        self.permission = coordinator.permission
        self.models = coordinator.models
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

        ModelMenu(models: models)
        Text(models.state.statusText)
        if case .failed = models.state {
            Button("Повторить загрузку модели") { models.prepare() }
        }

        Divider()

        Button("Системные инструкции…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: SystemPromptsView.windowID)
        }

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
