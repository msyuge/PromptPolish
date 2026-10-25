import SwiftUI

struct PreviewView: View {
    @ObservedObject var model: PreviewModel
    @ObservedObject var models: ModelStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
            if case let .failed(message) = model.phase {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttons
        }
        .padding(16)
        .padding(.top, 8)
        .frame(width: PreviewPanelController.size.width, height: PreviewPanelController.size.height)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(.tint)
            Text("Промт для \(model.target.displayName)")
                .font(.headline)
            Spacer()
            if model.isStreaming {
                ProgressView().controlSize(.small)
            }
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.phase == .ready {
            TextEditor(text: $model.text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.text.isEmpty ? placeholder : model.text)
                        .font(.body)
                        .foregroundStyle(model.text.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                    Color.clear.frame(height: 1).id("end")
                }
                .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: model.text) {
                    proxy.scrollTo("end", anchor: .bottom)
                }
            }
        }
    }

    private var buttons: some View {
        HStack {
            Button("Отмена", role: .cancel) { model.onCancel() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Копировать") { model.onCopy() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!model.canUseResult)
            Button("Заменить") { model.onReplace() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canUseResult)
        }
    }

    private var placeholder: String {
        model.phase == .waitingForModel ? models.state.statusText : "Генерирую…"
    }

    private var statusText: String {
        switch model.phase {
        case .waitingForModel: "ожидание модели"
        case .generating: "генерация"
        case .ready: "можно отредактировать"
        case .replacing: "замена…"
        case .failed: "ошибка"
        }
    }
}
