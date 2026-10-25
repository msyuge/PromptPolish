import Foundation

/// Состояние одной сессии улучшения, которое показывает панель.
@MainActor
final class PreviewModel: ObservableObject {
    enum Phase: Equatable {
        case waitingForModel
        case generating
        /// Модель задала уточняющие вопросы и ждёт ответа пользователя.
        case needsAnswers
        case ready
        case replacing
        case failed(String)
    }

    let target: ChatTarget
    /// Готовый (или стримящийся) промт — только он попадает в поле ввода.
    @Published var text = ""
    /// Уточняющие вопросы модели, если она их задала.
    @Published var questions = ""
    @Published var answer = ""
    @Published var phase: Phase = .waitingForModel

    var onReplace: () -> Void = {}
    var onCopy: () -> Void = {}
    var onCancel: () -> Void = {}
    var onAnswer: () -> Void = {}

    init(target: ChatTarget) {
        self.target = target
    }

    /// Результат можно использовать, когда промт дописан (в том числе если не удалась сама замена).
    var canUseResult: Bool {
        guard !text.isEmpty, questions.isEmpty else { return false }
        switch phase {
        case .ready, .failed: return true
        case .waitingForModel, .generating, .needsAnswers, .replacing: return false
        }
    }

    var canSendAnswer: Bool {
        phase == .needsAnswers && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isStreaming: Bool {
        phase == .generating || phase == .waitingForModel
    }

    func apply(_ reply: ModelReply) {
        switch reply {
        case let .prompt(prompt):
            text = prompt
            questions = ""
        case let .questions(list):
            questions = list
            text = ""
        }
    }
}
