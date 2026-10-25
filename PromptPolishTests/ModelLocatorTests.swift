import XCTest
@testable import PromptPolish

final class ModelLocatorTests: XCTestCase {
    private var root: URL!
    private var locator: ModelLocator!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ModelLocatorTests-\(UUID().uuidString)")
        locator = ModelLocator(
            lmStudioRoots: [root.appending(path: "lmstudio")],
            huggingFaceHub: root.appending(path: "hub")
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Папка модели: конфиг, токенизатор, индекс весов и перечисленные в нём файлы.
    private func makeModel(at directory: URL, shards: [String] = ["model.safetensors"], missing: Set<String> = []) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let weightMap = Dictionary(uniqueKeysWithValues: shards.enumerated().map { ("layer.\($0.offset)", $0.element) })
        let index = try JSONSerialization.data(withJSONObject: ["weight_map": weightMap])
        var files: [String: Data] = ["config.json": Data("{}".utf8), "tokenizer.json": Data("{}".utf8), "model.safetensors.index.json": index]
        for shard in shards { files[shard] = Data([0]) }
        for (name, data) in files where !missing.contains(name) {
            try data.write(to: directory.appending(path: name))
        }
    }

    func testFindsModelInLMStudio() throws {
        let directory = root.appending(path: "lmstudio/mlx-community/Qwen3.5-4B-MLX-4bit")
        try makeModel(at: directory)

        XCTAssertEqual(locator.locate(repoIDs: ["mlx-community/Qwen3.5-4B-MLX-4bit"]), .lmStudio(directory))
    }

    func testFindsModelByAlias() throws {
        let directory = root.appending(path: "lmstudio/mlx-community/Qwen3.5-4B-4bit")
        try makeModel(at: directory)

        let location = locator.locate(repoIDs: ["mlx-community/Qwen3.5-4B-MLX-4bit", "mlx-community/Qwen3.5-4B-4bit"])

        XCTAssertEqual(location, .lmStudio(directory))
    }

    func testIncompleteModelIsIgnored() throws {
        try makeModel(
            at: root.appending(path: "lmstudio/mlx-community/M"),
            shards: ["model-00001-of-00002.safetensors", "model-00002-of-00002.safetensors"],
            missing: ["model-00002-of-00002.safetensors"]
        )
        try makeModel(at: root.appending(path: "lmstudio/mlx-community/N"), missing: ["tokenizer.json"])

        XCTAssertEqual(locator.locate(repoIDs: ["mlx-community/M"]), .download)
        XCTAssertEqual(locator.locate(repoIDs: ["mlx-community/N"]), .download)
    }

    func testFindsHuggingFaceSnapshotFromRef() throws {
        let repo = root.appending(path: "hub/models--mlx-community--Qwen3.5-4B-MLX-4bit")
        let snapshot = repo.appending(path: "snapshots/abc123")
        try makeModel(at: snapshot)
        try FileManager.default.createDirectory(at: repo.appending(path: "refs"), withIntermediateDirectories: true)
        try Data("abc123\n".utf8).write(to: repo.appending(path: "refs/main"))

        XCTAssertEqual(locator.locate(repoIDs: ["mlx-community/Qwen3.5-4B-MLX-4bit"]), .huggingFaceCache(snapshot))
    }

    func testLMStudioWinsOverHuggingFaceCache() throws {
        let lmStudio = root.appending(path: "lmstudio/mlx-community/X")
        try makeModel(at: lmStudio)
        let repo = root.appending(path: "hub/models--mlx-community--X")
        try makeModel(at: repo.appending(path: "snapshots/c1"))
        try FileManager.default.createDirectory(at: repo.appending(path: "refs"), withIntermediateDirectories: true)
        try Data("c1".utf8).write(to: repo.appending(path: "refs/main"))

        XCTAssertEqual(locator.locate(repoIDs: ["mlx-community/X"]), .lmStudio(lmStudio))
    }

    func testNothingOnDiskMeansDownload() {
        XCTAssertEqual(locator.locate(repoIDs: ["mlx-community/Absent"]), .download)
    }
}
