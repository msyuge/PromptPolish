import Foundation

/// Ищет уже скачанную модель, чтобы не держать на диске вторую копию:
/// сначала в папках LM Studio, затем в кэше Hugging Face. Если не нашлось — модель скачивается.
struct ModelLocator: Sendable {
    enum Location: Equatable, Sendable {
        case lmStudio(URL)
        case huggingFaceCache(URL)
        /// Модели нет на диске — её скачает `HubSnapshotDownloader`.
        case download

        var directory: URL? {
            switch self {
            case let .lmStudio(url), let .huggingFaceCache(url): url
            case .download: nil
            }
        }

        var description: String {
            switch self {
            case let .lmStudio(url): "LM Studio: \(url.path(percentEncoded: false))"
            case let .huggingFaceCache(url): "Кэш Hugging Face: \(url.path(percentEncoded: false))"
            case .download: "Будет скачана с Hugging Face"
            }
        }
    }

    let lmStudioRoots: [URL]
    let huggingFaceHub: URL

    static let standard: ModelLocator = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ModelLocator(
            lmStudioRoots: [
                home.appending(path: ".lmstudio/models"),
                home.appending(path: ".cache/lm-studio/models"),
            ],
            huggingFaceHub: home.appending(path: ".cache/huggingface/hub")
        )
    }()

    /// `repoIDs` — одинаковые веса могут лежать под разными именами репозиториев.
    func locate(repoIDs: [String]) -> Location {
        for root in lmStudioRoots {
            for id in repoIDs {
                let directory = root.appending(path: id)
                if Self.isComplete(directory) { return .lmStudio(directory) }
            }
        }
        for id in repoIDs {
            if let snapshot = huggingFaceSnapshot(for: id) { return .huggingFaceCache(snapshot) }
        }
        return .download
    }

    /// Снимок в кэше Hugging Face: `models--org--name/snapshots/<commit из refs/main>`.
    private func huggingFaceSnapshot(for id: String) -> URL? {
        let repo = huggingFaceHub.appending(path: "models--" + id.replacingOccurrences(of: "/", with: "--"))
        guard let commit = try? String(contentsOf: repo.appending(path: "refs/main"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !commit.isEmpty else { return nil }
        let snapshot = repo.appending(path: "snapshots/\(commit)")
        return Self.isComplete(snapshot) ? snapshot : nil
    }

    /// Папка пригодна для загрузки, если в ней есть конфиг, токенизатор и все файлы весов из индекса.
    static func isComplete(_ directory: URL) -> Bool {
        let fileManager = FileManager.default
        func exists(_ name: String) -> Bool {
            fileManager.fileExists(atPath: directory.appending(path: name).path(percentEncoded: false))
        }
        guard exists("config.json"), exists("tokenizer.json") else { return false }

        let index = directory.appending(path: "model.safetensors.index.json")
        if let data = try? Data(contentsOf: index),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let weightMap = json["weight_map"] as? [String: String] {
            return Set(weightMap.values).allSatisfy(exists)
        }
        return exists("model.safetensors")
    }
}
