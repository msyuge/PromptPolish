import Foundation

/// MLX-модель, уже лежащая на диске.
struct LocalModel: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case lmStudio
        case huggingFaceCache
    }

    /// Имя репозитория вида `mlx-community/Qwen3.5-4B-MLX-4bit`.
    let repoID: String
    let directory: URL
    let source: Source
    let sizeBytes: Int64
    let modelType: String?
}

/// Находит готовые MLX-модели в папках LM Studio и в кэше Hugging Face,
/// чтобы не держать на диске вторую копию. GGUF-модели (Ollama, llama.cpp) не подходят и пропускаются.
struct ModelLocator: Sendable {
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

    func scan() -> [LocalModel] {
        scanLMStudio() + scanHuggingFaceCache()
    }

    /// LM Studio хранит модели как `<root>/<publisher>/<model>`.
    private func scanLMStudio() -> [LocalModel] {
        lmStudioRoots.flatMap { root in
            subdirectories(of: root).flatMap { publisher in
                subdirectories(of: publisher).compactMap { directory in
                    model(at: directory, repoID: "\(publisher.lastPathComponent)/\(directory.lastPathComponent)", source: .lmStudio)
                }
            }
        }
    }

    /// Кэш Hugging Face: `models--org--name/snapshots/<commit из refs/main>`.
    private func scanHuggingFaceCache() -> [LocalModel] {
        subdirectories(of: huggingFaceHub).compactMap { repo in
            let name = repo.lastPathComponent
            guard name.hasPrefix("models--") else { return nil }
            let parts = name.dropFirst("models--".count).components(separatedBy: "--")
            guard parts.count == 2,
                  let commit = try? String(contentsOf: repo.appending(path: "refs/main"), encoding: .utf8)
                      .trimmingCharacters(in: .whitespacesAndNewlines), !commit.isEmpty else { return nil }
            return model(at: repo.appending(path: "snapshots/\(commit)"), repoID: parts.joined(separator: "/"), source: .huggingFaceCache)
        }
    }

    private func model(at directory: URL, repoID: String, source: LocalModel.Source) -> LocalModel? {
        guard let weights = Self.weightFiles(in: directory) else { return nil }
        let size = weights.reduce(Int64(0)) { total, name in
            let path = directory.appending(path: name).path(percentEncoded: false)
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            return total + ((attributes?[.size] as? NSNumber)?.int64Value ?? 0)
        }
        return LocalModel(repoID: repoID, directory: directory, source: source, sizeBytes: size, modelType: Self.modelType(in: directory))
    }

    /// Файлы весов, если папка пригодна для MLX: есть конфиг, токенизатор и все safetensors из индекса.
    static func weightFiles(in directory: URL) -> [String]? {
        let fileManager = FileManager.default
        func exists(_ name: String) -> Bool {
            fileManager.fileExists(atPath: directory.appending(path: name).path(percentEncoded: false))
        }
        guard exists("config.json"), exists("tokenizer.json") else { return nil }

        let index = directory.appending(path: "model.safetensors.index.json")
        if let data = try? Data(contentsOf: index),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let weightMap = json["weight_map"] as? [String: String] {
            let files = Array(Set(weightMap.values)).sorted()
            return files.allSatisfy(exists) ? files : nil
        }
        return exists("model.safetensors") ? ["model.safetensors"] : nil
    }

    private static func modelType(in directory: URL) -> String? {
        guard let data = try? Data(contentsOf: directory.appending(path: "config.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["model_type"] as? String
    }

    private func subdirectories(of url: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        return contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }
}
