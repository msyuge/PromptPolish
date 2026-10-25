import Foundation
import HuggingFace
import MLXLMCommon
import Tokenizers

/// Скачивает снимок репозитория Hugging Face в стандартный кэш (~/.cache/huggingface/hub).
/// Если полный снимок уже в кэше, swift-huggingface отдаёт его без обращения к сети.
/// При обрыве соединения скачивание повторяется: swift-huggingface дозакачивает файл с места обрыва.
struct HubSnapshotDownloader: MLXLMCommon.Downloader {
    private let client: HubClient
    private let maxAttempts: Int

    init(client: HubClient = HubClient(), maxAttempts: Int = 6) {
        self.client = client
        self.maxAttempts = maxAttempts
    }

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        guard let repo = Repo.ID(rawValue: id) else { throw LLMError.invalidModelID(id) }
        var attempt = 1
        while true {
            do {
                return try await client.downloadSnapshot(
                    of: repo,
                    revision: revision ?? "main",
                    matching: patterns,
                    progressHandler: { @MainActor progress in
                        progressHandler(progress)
                    }
                )
            } catch let error as URLError where Self.isTransient(error) && attempt < maxAttempts {
                try await Task.sleep(for: .seconds(min(30, 2 << attempt)))
                attempt += 1
            }
        }
    }

    static func isTransient(_ error: URLError) -> Bool {
        [.networkConnectionLost, .notConnectedToInternet, .timedOut, .cannotConnectToHost,
         .cannotFindHost, .dnsLookupFailed, .secureConnectionFailed].contains(error.code)
    }
}

/// Загружает токенизатор swift-transformers из локальной папки модели.
struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await AutoTokenizer.from(modelFolder: directory)
        return TokenizerBridge(upstream: upstream)
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
