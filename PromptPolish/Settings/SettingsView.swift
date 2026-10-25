import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @ObservedObject var permission: AccessibilityPermission

    var body: some View {
        Form {
            Section("Горячая клавиша") {
                KeyboardShortcuts.Recorder("Улучшить промт:", name: .improvePrompt)
            }

            Section("Разрешения") {
                LabeledContent("Accessibility") {
                    if permission.isTrusted {
                        Label("Выдано", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Выдать доступ…") { permission.request() }
                    }
                }
            }

            Section {
                LabeledContent("Версия", value: Bundle.main.shortVersion)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
