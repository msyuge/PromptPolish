import Foundation

/// AI-чат, в поле которого пользователь улучшает промт.
enum ChatTarget: String, CaseIterable, Sendable {
    case claude
    case chatGPT
    case gemini
    case perplexity
    case deepSeek
    case grok
    case copilot
    case mistral
    case generic

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .chatGPT: "ChatGPT"
        case .gemini: "Gemini"
        case .perplexity: "Perplexity"
        case .deepSeek: "DeepSeek"
        case .grok: "Grok"
        case .copilot: "Copilot"
        case .mistral: "Le Chat"
        case .generic: "любого чата"
        }
    }

    private var bundleIDs: Set<String> {
        switch self {
        case .claude: ["com.anthropic.claudefordesktop"]
        case .chatGPT: ["com.openai.chat"]
        case .perplexity: ["ai.perplexity.mac"]
        case .gemini, .deepSeek, .grok, .copilot, .mistral, .generic: []
        }
    }

    private var hosts: [String] {
        switch self {
        case .claude: ["claude.ai"]
        case .chatGPT: ["chatgpt.com", "chat.openai.com"]
        case .gemini: ["gemini.google.com", "aistudio.google.com"]
        case .perplexity: ["perplexity.ai"]
        case .deepSeek: ["chat.deepseek.com"]
        case .grok: ["grok.com"]
        case .copilot: ["copilot.microsoft.com"]
        case .mistral: ["chat.mistral.ai"]
        case .generic: []
        }
    }

    /// Адрес страницы важнее приложения: в браузере bundle ID говорит только о браузере.
    static func detect(bundleID: String?, pageURL: URL?) -> ChatTarget {
        if let url = pageURL, let host = url.host()?.lowercased() {
            if host == "x.com" || host.hasSuffix(".x.com"), url.path().hasPrefix("/i/grok") {
                return .grok
            }
            if let target = allCases.first(where: { target in
                target.hosts.contains { host == $0 || host.hasSuffix("." + $0) }
            }) {
                return target
            }
        }
        if let bundleID, let target = allCases.first(where: { $0.bundleIDs.contains(bundleID) }) {
            return target
        }
        return .generic
    }
}
