import Foundation

/// Состояние одной сессии улучшения, которое показывает панель.
@MainActor
final class PreviewModel: ObservableObject {
    enum Phase: Equatable {
        case waitingForModel
        case generating
        case ready
        case replacing
        case failed(String)
    }

    let target: ChatTarget
    @Published var text = ""
    @Published var phase: Phase = .waitingForModel

    var onReplace: () -> Void = {}
    var onCopy: () -> Void = {}
    var onCancel: () -> Void = {}

    init(target: ChatTarget) {
        self.target = target
    }

    /// Результат можно использовать, когда генерация закончилась (в том числе если не удалась сама замена).
    var canUseResult: Bool {
        guard !text.isEmpty else { return false }
        switch phase {
        case .ready, .failed: return true
        case .waitingForModel, .generating, .replacing: return false
        }
    }

    var isStreaming: Bool {
        phase == .generating || phase == .waitingForModel
    }
}
