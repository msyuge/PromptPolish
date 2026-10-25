import SwiftUI

struct MenuContent: View {
    @ObservedObject var coordinator: ImproveCoordinator
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Улучшить промт") {
            coordinator.improvePrompt()
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
