import SwiftUI

/// Вкладка настроек «Системные инструкции»: список чатов слева, редактор инструкции выбранного чата справа,
/// переключатель комплекта (русский — для идей на кириллице, английский — для остальных).
/// Несохранённые правки хранятся отдельно для каждого чата и языка, пока окно открыто.
struct SystemPromptsView: View {
    @ObservedObject var store: SystemPromptStore
    @State private var selection: ChatTarget = .generic
    @State private var language: PromptLanguage = .ru
    @State private var drafts: [SystemPromptStore.Key: String] = [:]
    @State private var errorMessage: String?

    private var key: SystemPromptStore.Key { SystemPromptStore.Key(target: selection, language: language) }

    var body: some View {
        HStack(spacing: 0) {
            List(ChatTarget.allCases, id: \.self, selection: $selection) { target in
                HStack {
                    Text(target.instructionsTitle)
                    Spacer()
                    if PromptLanguage.allCases.contains(where: { drafts[.init(target: target, language: $0)] != nil }) {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundStyle(.orange)
                            .help("Есть несохранённые изменения")
                    } else if PromptLanguage.allCases.contains(where: { store.isCustomized(target, language: $0) }) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.tint)
                            .help("Инструкция изменена")
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(width: 190)
            Divider()
            editor
        }
        .frame(width: SettingsView.size.width, height: SettingsView.size.height)
        .onAppear { store.reload() }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(selection.instructionsTitle)
                    .font(.headline)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Язык инструкции", selection: $language) {
                    ForEach(PromptLanguage.allCases, id: \.self) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            TextEditor(text: Binding(
                get: { drafts[key] ?? store.text(for: selection, language: language) },
                set: { text in drafts[key] = text == store.text(for: selection, language: language) ? nil : text }
            ))
            .font(.body.monospaced())
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(.background, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Сбросить к стандартной") { reset() }
                    .disabled(!store.isCustomized(selection, language: language) && drafts[key] == nil)
                Button("Показать файл в Finder") { store.revealInFinder(selection, language: language) }
                Spacer()
                Button("Отменить изменения") { drafts[key] = nil }
                    .disabled(drafts[key] == nil)
                Button("Сохранить") { save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(drafts[key] == nil)
            }

            Text("Русская инструкция используется для идей на кириллице, английская — для остальных. Изменения применяются к следующему улучшению промта; пустая инструкция означает стандартную.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var status: String {
        if drafts[key] != nil { return "не сохранено" }
        return store.isCustomized(selection, language: language) ? "изменена" : "стандартная"
    }

    private func save() {
        guard let draft = drafts[key] else { return }
        do {
            try store.save(draft, for: selection, language: language)
            drafts[key] = nil
            errorMessage = nil
        } catch {
            errorMessage = "Не удалось сохранить: \(error.localizedDescription)"
        }
    }

    private func reset() {
        do {
            try store.reset(selection, language: language)
            drafts[key] = nil
            errorMessage = nil
        } catch {
            errorMessage = "Не удалось сбросить: \(error.localizedDescription)"
        }
    }
}

extension ChatTarget {
    /// Название в списке инструкций: у общей инструкции своё имя вместо «любого чата».
    var instructionsTitle: String {
        self == .generic ? "Общая (любой чат)" : displayName
    }
}
