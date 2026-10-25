import XCTest
@testable import PromptPolish

final class ModelLocatorTests: XCTestCase {
    private var root: URL!
    private var locator: ModelLocator!

    override func setUpWithError() throws {
        // /var во временной папке — ссылка на /private/var; сканер возвращает настоящие пути.
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: "ModelLocatorTests-\(UUID().uuidString)")
        locator = ModelLocator(
            lmStudioRoots: [root.appending(path: "lmstudio")],
            huggingFaceHub: root.appending(path: "hub")
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Папка MLX-модели: конфиг с model_type, токенизатор, индекс весов и перечисленные в нём файлы.
    private func makeModel(
        at directory: URL,
        modelType: String = "qwen3_5",
        shards: [String] = ["model.safetensors"],
        missing: Set<String> = []
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let weightMap = Dictionary(uniqueKeysWithValues: shards.enumerated().map { ("layer.\($0.offset)", $0.element) })
        var files: [String: Data] = [
            "config.json": try JSONSerialization.data(withJSONObject: ["model_type": modelType]),
            "tokenizer.json": Data("{}".utf8),
            "model.safetensors.index.json": try JSONSerialization.data(withJSONObject: ["weight_map": weightMap]),
        ]
        for shard in shards { files[shard] = Data(repeating: 1, count: 100) }
        for (name, data) in files where !missing.contains(name) {
            try data.write(to: directory.appending(path: name))
        }
    }

    private func makeHubSnapshot(repo: String, commit: String = "abc123") throws -> URL {
        let repoDirectory = root.appending(path: "hub/models--" + repo.replacingOccurrences(of: "/", with: "--"))
        let snapshot = repoDirectory.appending(path: "snapshots/\(commit)")
        try makeModel(at: snapshot)
        try FileManager.default.createDirectory(at: repoDirectory.appending(path: "refs"), withIntermediateDirectories: true)
        try Data("\(commit)\n".utf8).write(to: repoDirectory.appending(path: "refs/main"))
        return snapshot
    }

    func testFindsLMStudioModelWithSizeAndType() throws {
        let directory = root.appending(path: "lmstudio/mlx-community/Qwen3.5-4B-MLX-4bit")
        try makeModel(at: directory, shards: ["model-1.safetensors", "model-2.safetensors"])

        let models = locator.scan()

        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models.first?.repoID, "mlx-community/Qwen3.5-4B-MLX-4bit")
        XCTAssertEqual(models.first?.directory.resolvingSymlinksInPath().path, directory.path)
        XCTAssertEqual(models.first?.source, .lmStudio)
        XCTAssertEqual(models.first?.sizeBytes, 200)
        XCTAssertEqual(models.first?.modelType, "qwen3_5")
    }

    func testFindsHuggingFaceSnapshotFromRef() throws {
        let snapshot = try makeHubSnapshot(repo: "mlx-community/gemma-4-e2b-it-4bit")

        let models = locator.scan()

        XCTAssertEqual(models.map(\.repoID), ["mlx-community/gemma-4-e2b-it-4bit"])
        XCTAssertEqual(models.first?.directory.resolvingSymlinksInPath().path, snapshot.path)
        XCTAssertEqual(models.first?.source, .huggingFaceCache)
    }

    func testSkipsIncompleteAndGGUFModels() throws {
        try makeModel(
            at: root.appending(path: "lmstudio/mlx-community/Partial"),
            shards: ["model-00001-of-00002.safetensors", "model-00002-of-00002.safetensors"],
            missing: ["model-00002-of-00002.safetensors"]
        )
        try makeModel(at: root.appending(path: "lmstudio/mlx-community/NoTokenizer"), missing: ["tokenizer.json"])
        let gguf = root.appending(path: "lmstudio/lmstudio-community/Qwen3-GGUF")
        try FileManager.default.createDirectory(at: gguf, withIntermediateDirectories: true)
        try Data([0]).write(to: gguf.appending(path: "Qwen3-4B-Q4_K_M.gguf"))

        XCTAssertEqual(locator.scan(), [])
    }

    func testMissingFoldersMeanNoModels() {
        XCTAssertEqual(locator.scan(), [])
    }
}

final class ModelCatalogTests: XCTestCase {
    private let eightGB: UInt64 = 8 * 1_073_741_824
    private let thirtyTwoGB: UInt64 = 32 * 1_073_741_824

    private func local(_ repo: String, _ source: LocalModel.Source, size: Int64 = 3_000_000_000) -> LocalModel {
        LocalModel(repoID: repo, directory: URL(fileURLWithPath: "/models/\(source)/\(repo)"), source: source, sizeBytes: size, modelType: "qwen3_5")
    }

    func testInstalledModelIsNotOfferedForDownload() {
        let catalog = ModelCatalog.build(local: [local(ModelCatalog.defaultID, .lmStudio)], physicalMemory: eightGB)

        XCTAssertEqual(catalog.installed.map(\.id), [ModelCatalog.defaultID])
        XCTAssertFalse(catalog.downloads.contains { $0.id == ModelCatalog.defaultID })
    }

    func testLMStudioCopyWinsOverHuggingFaceCache() {
        let catalog = ModelCatalog.build(
            local: [local("org/M", .huggingFaceCache), local("org/M", .lmStudio)],
            physicalMemory: eightGB
        )

        XCTAssertEqual(catalog.installed.count, 1)
        XCTAssertEqual(catalog.installed.first?.source, .lmStudio(URL(fileURLWithPath: "/models/lmStudio/org/M")))
    }

    func testDownloadsAreFilteredByMemory() {
        let small = ModelCatalog.build(local: [], physicalMemory: eightGB).downloads.map(\.id)
        let large = ModelCatalog.build(local: [], physicalMemory: thirtyTwoGB).downloads.map(\.id)

        XCTAssertTrue(small.contains("mlx-community/Qwen3.5-4B-MLX-4bit"))
        XCTAssertTrue(small.contains("mlx-community/Qwen3.5-0.8B-MLX-4bit"))
        XCTAssertFalse(small.contains("mlx-community/gemma-4-e4b-it-4bit"))
        XCTAssertFalse(small.contains("mlx-community/Qwen3.5-9B-MLX-4bit"))
        XCTAssertEqual(large.count, ModelCatalog.downloadable.count)
    }

    func testResolvePrefersSavedThenDefaultThenInstalled() {
        let catalog = ModelCatalog.build(local: [local("org/Custom", .lmStudio)], physicalMemory: eightGB)

        XCTAssertEqual(ModelCatalog.resolve(selectedID: "org/Custom", installed: catalog.installed, downloads: catalog.downloads).id, "org/Custom")
        XCTAssertEqual(ModelCatalog.resolve(selectedID: "org/Gone", installed: catalog.installed, downloads: catalog.downloads).id, ModelCatalog.defaultID)
        XCTAssertEqual(ModelCatalog.resolve(selectedID: nil, installed: catalog.installed, downloads: []).id, "org/Custom")
    }

    func testDefaultIsInstalledCopyWhenPresent() {
        let catalog = ModelCatalog.build(local: [local(ModelCatalog.defaultID, .lmStudio)], physicalMemory: eightGB)

        let choice = ModelCatalog.resolve(selectedID: nil, installed: catalog.installed, downloads: catalog.downloads)

        XCTAssertTrue(choice.isInstalled)
        XCTAssertEqual(choice.name, "Qwen3.5 4B")
    }

    func testUnknownLocalModelIsNamedByFolder() {
        XCTAssertEqual(ModelCatalog.displayName(for: "lmstudio-community/Llama-3.2-3B-Instruct-MLX-4bit"), "Llama-3.2-3B-Instruct-MLX-4bit")
    }

    func testSpecUsesDirectoryAndEndOfTurnTokens() {
        let installed = ModelCatalog.build(local: [local("org/M", .lmStudio)], physicalMemory: eightGB).installed[0]
        let spec = ModelSpec(for: installed)

        XCTAssertEqual(spec.directory, URL(fileURLWithPath: "/models/lmStudio/org/M"))
        XCTAssertEqual(spec.extraEOSTokens, ["<|im_end|>"])
        XCTAssertEqual(ModelSpec.endOfTurnTokens(modelType: "gemma4"), ["<turn|>"])
        XCTAssertEqual(ModelSpec.endOfTurnTokens(modelType: "llama"), [])
    }
}

final class ModelUnloadPolicyTests: XCTestCase {
    private let lastUsed = Date(timeIntervalSince1970: 1_000_000)

    func testUnloadsReadyModelAfterIdleDelay() {
        XCTAssertTrue(ModelStore.shouldUnload(isReady: true, activeUses: 0, lastUsed: lastUsed, now: lastUsed + 300, delay: 300))
        XCTAssertFalse(ModelStore.shouldUnload(isReady: true, activeUses: 0, lastUsed: lastUsed, now: lastUsed + 299, delay: 300))
    }

    func testNeverUnloadsDuringSessionOrWhenDisabled() {
        XCTAssertFalse(ModelStore.shouldUnload(isReady: true, activeUses: 1, lastUsed: lastUsed, now: lastUsed + 9999, delay: 300))
        XCTAssertFalse(ModelStore.shouldUnload(isReady: true, activeUses: 0, lastUsed: lastUsed, now: lastUsed + 9999, delay: 0))
    }

    func testNothingToUnloadWhenNotLoaded() {
        XCTAssertFalse(ModelStore.shouldUnload(isReady: false, activeUses: 0, lastUsed: lastUsed, now: lastUsed + 9999, delay: 60))
    }

    func testDefaultDelayIsOneOfTheOptions() {
        XCTAssertTrue(ModelStore.unloadDelayOptions.contains { $0.seconds == ModelStore.defaultUnloadDelay })
        XCTAssertTrue(ModelStore.unloadDelayOptions.contains { $0.seconds == 0 })
    }
}
