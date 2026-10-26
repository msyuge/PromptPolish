import KeyboardShortcuts
import SwiftUI

/// Вкладки окна настроек; выбранная запоминается между открытиями.
enum SettingsTab: String {
    case general
    case instructions

    static let storageKey = "settingsTab"
}

struct SettingsView: View {
    /// Общий размер всех вкладок: окно не меняет размер при переключении.
    static let size = CGSize(width: 780, height: 540)

    @ObservedObject var permission: AccessibilityPermission
    @ObservedObject var models: ModelStore
    @ObservedObject var prompts: SystemPromptStore
    @AppStorage(SettingsTab.storageKey) private var tab: SettingsTab = .general
    @AppStorage(ModelStore.unloadDelayKey) private var unloadDelay = ModelStore.defaultUnloadDelay
    @AppStorage(ModelStore.loadAtLaunchKey) private var loadAtLaunch = false

    var body: some View {
        TabView(selection: $tab) {
            general
                .tabItem { Label("Основные", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            SystemPromptsView(store: prompts)
                .tabItem { Label("Системные инструкции", systemImage: "text.alignleft") }
                .tag(SettingsTab.instructions)
        }
    }

    private var general: some View {
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
                Picker("Модель", selection: Binding(
                    get: { models.current.id },
                    set: { id in
                        if let choice = (models.installed + models.downloads).first(where: { $0.id == id }) {
                            models.select(choice)
                        }
                    }
                )) {
                    if !models.installed.isEmpty {
                        Section("На диске") {
                            ForEach(models.installed) { choice in
                                Text("\(choice.name) — \(choice.sourceLabel)").tag(choice.id)
                            }
                        }
                    }
                    if !models.downloads.isEmpty {
                        Section("Скачать") {
                            ForEach(models.downloads) { choice in
                                Text("\(choice.name) — \(choice.sizeLabel)").tag(choice.id)
                            }
                        }
                    }
                }
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
                Picker("Выгружать из памяти", selection: $unloadDelay) {
                    ForEach(ModelStore.unloadDelayOptions, id: \.seconds) { option in
                        Text(option.title).tag(option.seconds)
                    }
                }
                Toggle("Загружать модель при запуске", isOn: $loadAtLaunch)
                Text(models.current.usesAppMemory
                    ? "Загруженная модель занимает около \(models.current.sizeLabel) памяти. Без загрузки при запуске первый ⌥⌘P ждёт 2–4 секунды, пока модель читается с диска."
                    : "Apple Intelligence работает в памяти macOS, а не PromptPolish: выгрузка и загрузка при запуске относятся только к моделям MLX.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(models.current.locationDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if !models.fitsMemory(models.current) {
                    Text("Этой модели может не хватить оперативной памяти: возможны своп и замедление.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                HStack {
                    Text("Ищу MLX-модели в LM Studio и кэше Hugging Face. Модели Ollama (GGUF) не поддерживаются.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Обновить") { models.refreshCatalog() }
                        .controlSize(.small)
                }
            }

            Section {
                LabeledContent("Версия", value: Bundle.main.shortVersion)
                if let acknowledgements = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt") {
                    LabeledContent("Сторонние компоненты") {
                        Button("Лицензии") { NSWorkspace.shared.open(acknowledgements) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
