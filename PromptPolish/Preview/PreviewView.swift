import SwiftUI

struct PreviewView: View {
    @ObservedObject var model: PreviewModel
    @ObservedObject var models: ModelStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if model.questions.isEmpty {
                promptContent
            } else {
                questionsContent
            }
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
    private var promptContent: some View {
        if model.phase == .ready {
            TextEditor(text: $model.text)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        } else {
            StreamingText(text: model.text.isEmpty ? placeholder : model.text, isPlaceholder: model.text.isEmpty)
        }
    }

    private var questionsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Модели нужно уточнить:")
                .font(.subheadline.weight(.semibold))
            StreamingText(text: model.questions, isPlaceholder: false)
            TextEditor(text: $model.answer)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 90)
                .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if model.answer.isEmpty {
                        Text("Ваши ответы…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .allowsHitTesting(false)
                    }
                }
                .disabled(model.phase != .needsAnswers)
        }
    }

    private var buttons: some View {
        HStack {
            Button("Отмена", role: .cancel) { model.onCancel() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            if model.questions.isEmpty {
                Button("Копировать") { model.onCopy() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(!model.canUseResult)
                Button("Заменить") { model.onReplace() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canUseResult)
            } else {
                Button("Ответить") { model.onAnswer() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canSendAnswer)
            }
        }
    }

    private var placeholder: String {
        model.phase == .waitingForModel ? models.state.statusText : "Генерирую…"
    }

    private var statusText: String {
        switch model.phase {
        case .waitingForModel: "ожидание модели"
        case .generating: "генерация"
        case .needsAnswers: "ответ — ⌘↩"
        case .ready: "можно отредактировать"
        case .replacing: "замена…"
        case .failed: "ошибка"
        }
    }
}

/// Текст, который дописывается по мере генерации и сам прокручивается к концу.
private struct StreamingText: View {
    let text: String
    let isPlaceholder: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text)
                    .font(isPlaceholder ? .body : .body.monospaced())
                    .foregroundStyle(isPlaceholder ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
                Color.clear.frame(height: 1).id("end")
            }
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .onChange(of: text) {
                proxy.scrollTo("end", anchor: .bottom)
            }
        }
    }
}
