import SwiftUI

/// Подменю выбора модели: MLX-модели на диске (LM Studio, кэш Hugging Face) и модели для скачивания.
struct ModelMenu: View {
    @ObservedObject var models: ModelStore

    var body: some View {
        Menu("Модель: \(models.current.name)") {
            if !models.installed.isEmpty {
                Section("На диске") {
                    ForEach(models.installed) { choice in
                        item(choice, title: "\(choice.name) — \(choice.sourceLabel), \(choice.sizeLabel)")
                    }
                }
            }
            if !models.downloads.isEmpty {
                Section("Скачать с Hugging Face") {
                    ForEach(models.downloads) { choice in
                        item(choice, title: "\(choice.name) — \(choice.sizeLabel)")
                    }
                }
            }
            Divider()
            Button("Обновить список") { models.refreshCatalog() }
        }
    }

    /// Пункт с галочкой у текущей модели; модели, которым может не хватить памяти, помечены.
    private func item(_ choice: ModelChoice, title: String) -> some View {
        let warning = models.fitsMemory(choice) ? "" : " ⚠︎ мало памяти"
        return Toggle(title + warning, isOn: Binding(
            get: { models.current.id == choice.id },
            set: { isOn in if isOn { models.select(choice) } }
        ))
    }
}
