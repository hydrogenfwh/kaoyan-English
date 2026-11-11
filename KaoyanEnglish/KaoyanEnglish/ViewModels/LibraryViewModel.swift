import Foundation
import SwiftUI

actor LibraryWorker {
    private var store: LibraryStore?
    private func opened() throws -> LibraryStore {
        if let store { return store }
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("KaoyanEnglish", isDirectory: true)
        let result = try LibraryStore(directory: root)
        #if os(iOS)
        for (_, filename) in DatabaseSchema.files {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: root.appendingPathComponent(filename).path)
        }
        #endif
        store = result; return result
    }
    func snapshot() throws -> LibrarySnapshot { try opened().snapshot() }
    func importFiles(_ urls: [URL]) throws -> [ImportReport] {
        let files = try urls.map { url -> Data in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > PackageValidator.maximumBytes {
                throw LibraryError.validation(["\(url.lastPathComponent) 超过 20 MB；本批次未导入。"])
            }
            // Coordinate with Files/iCloud providers; downloaded content is read while access is held.
            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?
            var result: Result<Data, Error>?
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
                result = Result { try Data(contentsOf: readable) }
            }
            if let coordinationError { throw coordinationError }
            guard let result else { throw LibraryError.missing(url.lastPathComponent) }
            return try result.get()
        }
        return try opened().importBatch(files)
    }
    func importSample() throws -> [ImportReport] {
        guard let url = Bundle.main.url(forResource: "sample-package", withExtension: "json") else { throw LibraryError.missing("内置示例资料") }
        return [try opened().importData(Data(contentsOf: url))]
    }
    func favoriteVocabulary(ids: [String], value: Bool) throws { try opened().setVocabularyFavorites(ids: ids, favorite: value) }
    func favorite(_ id: String, kind: EntityKind, value: Bool) throws { try opened().setFavorite(id: id, kind: kind, favorite: value) }
    func delete(_ id: String, kind: EntityKind) throws { try opened().delete(id: id, kind: kind) }
    func save(_ value: Vocabulary, isNew: Bool) throws {
        let store = try opened()
        if isNew { _ = try store.importPackage(package(vocabulary: [value])) }
        else { try store.updateVocabulary(value) }
    }
    func save(_ value: WritingExpression, isNew: Bool) throws {
        let store = try opened()
        if isNew { _ = try store.importPackage(package(writing: [value])) }
        else { try store.updateWriting(value) }
    }
    func save(_ value: Article) throws { try opened().updateArticle(value) }
    func save(_ value: Question) throws { try opened().updateQuestion(value) }
    func submit(_ attempt: AnswerAttempt) throws { try opened().saveAttempt(attempt) }
    func check() throws { try opened().checkIntegrity() }
    func export(backup: Bool) throws -> URL {
        let store = try opened()
        let directory = store.directory.appendingPathComponent("Exports", isDirectory: true)
        if backup { return try store.backup(to: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("KaoyanEnglish-\(UUID().uuidString.lowercased()).json")
        try store.exportJSON().write(to: url, options: .atomic)
        return url
    }
    private func package(vocabulary: [Vocabulary] = [], writing: [WritingExpression] = []) -> LearningPackage {
        LearningPackage(packageId: UUID().uuidString.lowercased(), createdAt: Timestamp.now(), sources: [], articles: [], vocabulary: vocabulary, questions: [], writingExpressions: writing)
    }
}
struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
    let isBackup: Bool
}
@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var snapshot = LibrarySnapshot()
    @Published private(set) var busy = false
    @Published private(set) var ready = false
    @Published var message: String?
    @Published var reports: [ImportReport] = []
    @Published var showImportReport = false
    @Published var exportItem: ExportItem?
    let worker = LibraryWorker()
    var topics: [String] { Array(Set(DefaultTopics.all + snapshot.vocabulary.flatMap { $0.topics ?? [] } + snapshot.writing.flatMap { $0.topics ?? [] })).sorted() }
    @discardableResult
    func perform(_ action: () async throws -> Void) async -> Bool {
        guard !busy else { message = "当前操作尚未完成，请稍后再试。"; return false }
        busy = true; defer { busy = false }
        do {
            try await action()
            snapshot = try await worker.snapshot(); ready = true
            return true
        } catch { message = error.localizedDescription; return false }
    }
    func load() async { _ = await perform {} }
    func importFiles(_ urls: [URL]) async {
        if await perform({ reports = try await worker.importFiles(urls) }) { showImportReport = true }
    }
    func importSample() async {
        if await perform({ reports = try await worker.importSample() }) { showImportReport = true }
    }
    func favoriteVocabulary(ids: [String], value: Bool) async {
        await perform { try await worker.favoriteVocabulary(ids: ids, value: value) }
    }
    func favorite(_ id: String, kind: EntityKind, value: Bool) async {
        await perform { try await worker.favorite(id, kind: kind, value: value) }
    }
    func delete(_ id: String, kind: EntityKind) async -> Bool {
        await perform { try await worker.delete(id, kind: kind) }
    }
    func export(backup: Bool) async {
        await perform { exportItem = ExportItem(url: try await worker.export(backup: backup), isBackup: backup) }
    }
}
