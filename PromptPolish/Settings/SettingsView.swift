import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @ObservedObject var permission: AccessibilityPermission
    @ObservedObject var models: ModelStore

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

            Section("Модель") {
                LabeledContent("Модель", value: models.spec.displayName)
                LabeledContent("Размер", value: models.spec.approximateSize)
                LabeledContent("Состояние") {
                    switch models.state {
                    case let .downloading(fraction):
                        ProgressView(value: fraction) {
                            Text(models.state.statusText)
                        }
                        .frame(width: 200)
                    case .loading:
                        ProgressView().controlSize(.small)
                    case .failed:
                        Button("Повторить") { models.prepare() }
                    case .idle, .ready:
                        Text(models.state.statusText)
                    }
                }
                if case let .failed(message) = models.state {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                Text("Веса хранятся в ~/.cache/huggingface/hub. Сеть нужна только для первого скачивания.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
