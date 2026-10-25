import SwiftUI

/// Окно «Системные инструкции»: список чатов слева, редактор инструкции выбранного чата справа.
/// Несохранённые правки хранятся отдельно для каждого чата, пока окно открыто.
struct SystemPromptsView: View {
    static let windowID = "system-prompts"

    @ObservedObject var store: SystemPromptStore
    @State private var selection: ChatTarget = .generic
    @State private var drafts: [ChatTarget: String] = [:]
    @State private var errorMessage: String?

    var body: some View {
        NavigationSplitView {
            List(ChatTarget.allCases, id: \.self, selection: $selection) { target in
                HStack {
                    Text(target.instructionsTitle)
                    Spacer()
                    if drafts[target] != nil {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundStyle(.orange)
                            .help("Есть несохранённые изменения")
                    } else if store.isCustomized(target) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.tint)
                            .help("Инструкция изменена")
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            editor(for: selection)
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { store.reload() }
    }

    private func editor(for target: ChatTarget) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(target.instructionsTitle)
                    .font(.headline)
                Text(status(for: target))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            TextEditor(text: Binding(
                get: { drafts[target] ?? store.text(for: target) },
                set: { text in drafts[target] = text == store.text(for: target) ? nil : text }
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
                Button("Сбросить к стандартной") { reset(target) }
                    .disabled(!store.isCustomized(target) && drafts[target] == nil)
                Button("Показать файл в Finder") { store.revealInFinder(target) }
                Spacer()
                Button("Отменить изменения") { drafts[target] = nil }
                    .disabled(drafts[target] == nil)
                Button("Сохранить") { save(target) }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(drafts[target] == nil)
            }

            Text("Изменения применяются к следующему улучшению промта, перезапуск не нужен. Пустая инструкция означает стандартную.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private func status(for target: ChatTarget) -> String {
        if drafts[target] != nil { return "не сохранено" }
        return store.isCustomized(target) ? "изменена" : "стандартная"
    }

    private func save(_ target: ChatTarget) {
        guard let draft = drafts[target] else { return }
        do {
            try store.save(draft, for: target)
            drafts[target] = nil
            errorMessage = nil
        } catch {
            errorMessage = "Не удалось сохранить: \(error.localizedDescription)"
        }
    }

    private func reset(_ target: ChatTarget) {
        do {
            try store.reset(target)
            drafts[target] = nil
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
