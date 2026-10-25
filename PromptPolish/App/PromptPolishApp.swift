import SwiftUI

@main
struct PromptPolishApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("PromptPolish", systemImage: "wand.and.stars") {
            MenuContent(coordinator: appDelegate.coordinator)
        }
        .menuBarExtraStyle(.menu)

        Window("Системные инструкции", id: SystemPromptsView.windowID) {
            SystemPromptsView(store: appDelegate.coordinator.prompts)
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(
                permission: appDelegate.coordinator.permission,
                models: appDelegate.coordinator.models
            )
        }
    }
}
