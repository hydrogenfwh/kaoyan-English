import XCTest
#if SWIFT_PACKAGE
@testable import KaoyanCore
#else
@testable import KaoyanEnglish
#endif

class StoreTestCase: XCTestCase {
    var directory: URL!
    var store: LibraryStore!
    override func setUpWithError() throws {
        let base = ProcessInfo.processInfo.environment["KAOYAN_TEST_ROOT"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("KaoyanTests-" + UUID().uuidString, isDirectory: true)
        store = try LibraryStore(directory: directory)
    }
    override func tearDownWithError() throws {
        store = nil
        if let directory, FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    func fixture() -> LearningPackage {
        let a = Article(id: "00000000-0000-4000-8000-000000000001", title: "Technology and Learning", body: "Technology can facilitate learning, but critical thinking remains essential.", kind: .original)
        let v = Vocabulary(id: "00000000-0000-4000-8000-000000000002", expression: "facilitate", meaning: "促进；使便利", sourceArticleIds: [a.id], difficulty: 3, topics: ["教育与人才培养"])
        let q = Question(id: "00000000-0000-4000-8000-000000000003", articleId: a.id, type: .readingSingleChoice, stem: "What remains essential?", correctAnswer: "B", explanation: "文章明确指出批判性思维依然重要。", options: [.init(id: "A", text: "Technology alone"), .init(id: "B", text: "Critical thinking")], evidence: "critical thinking remains essential", distractorAnalysis: ["A": "以偏概全"])
        let w = WritingExpression(id: "00000000-0000-4000-8000-000000000004", expression: "play a vital role in", meaning: "在……中发挥重要作用", sourceArticleIds: [a.id], topics: ["科技与人工智能", "教育与人才培养"])
        return LearningPackage(packageId: UUID().uuidString.lowercased(), createdAt: "2026-11-10T00:00:00Z", sources: [], articles: [a], vocabulary: [v], questions: [q], writingExpressions: [w])
    }
}
final class DatabaseTests: StoreTestCase {
    func testInitialization() throws {
        try store.checkIntegrity()
        for (_, file) in DatabaseSchema.files { XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(file).path)) }
        XCTAssertEqual(try store.snapshot().vocabulary.count, 0)
    }
    func testVocabularyAddReadAndSameWordDifferentMeaning() throws {
        var p = fixture()
        var other = p.vocabulary[0]; other.id = UUID().uuidString.lowercased(); other.meaning = "推动进程"
        p.vocabulary.append(other)
        let report = try store.importPackage(p)
        XCTAssertEqual(report.vocabularyAdded, 2)
        XCTAssertEqual(Set(try store.snapshot().vocabulary.map(\.meaning)), ["促进；使便利", "推动进程"])
    }
    func testArticleQuestionAndWritingTopics() throws {
        let p = fixture(); _ = try store.importPackage(p)
        let snapshot = try store.snapshot()
        XCTAssertEqual(snapshot.questions[0].articleId, snapshot.articles[0].id)
        XCTAssertEqual(snapshot.writing[0].topics?.count, 2)
        XCTAssertEqual(snapshot.questions[0].provenanceLabel, "原创模拟题")
        XCTAssertThrowsError(try store.delete(id: p.articles[0].id, kind: .article))
    }
    func testPersistenceAfterReopen() throws {
        let p = fixture(); _ = try store.importPackage(p)
        try store.setFavorite(id: p.vocabulary[0].id, kind: .vocabulary, favorite: true)
        store = nil; store = try LibraryStore(directory: directory)
        XCTAssertEqual(try store.snapshot().questions.count, 1)
        XCTAssertTrue(try store.snapshot().favoriteVocabulary.contains(p.vocabulary[0].id))
    }
    func testEditDeletePreservesFavoriteAndBlocksDuplicates() throws {
        let p = fixture(); _ = try store.importPackage(p)
        var v = try store.vocabulary(id: p.vocabulary[0].id)
        try store.setFavorite(id: v.id, kind: .vocabulary, favorite: true)
        v.phonetic = "/fəˈsɪlɪteɪt/"; try store.updateVocabulary(v)
        XCTAssertEqual(try store.vocabulary(id: v.id).phonetic, v.phonetic)
        XCTAssertTrue(try store.snapshot().favoriteVocabulary.contains(v.id))
        try store.delete(id: v.id, kind: .vocabulary)
        XCTAssertTrue(try store.snapshot().vocabulary.isEmpty)
        try store.checkIntegrity()
    }
    func testEnglishDefinitionBackwardsCompatibleAndPersistent() throws {
        let p = fixture()
        let legacyJSON = try JSONCoding.encoder().encode(p)
        XCTAssertNil(try PackageValidator.decode(legacyJSON).vocabulary[0].englishDefinition)
        _ = try store.importData(legacyJSON)
        var word = try store.vocabulary(id: p.vocabulary[0].id)
        word.phonetic = "/fəˈsɪlɪteɪt/"
        word.englishDefinition = "to make a process easier"
        try store.updateVocabulary(word)
        store = nil; store = try LibraryStore(directory: directory)
        let restored = try store.vocabulary(id: word.id)
        XCTAssertEqual(restored.englishDefinition, "to make a process easier")
        XCTAssertEqual(restored.phonetic, "/fəˈsɪlɪteɪt/")
        let exported = try PackageValidator.decode(store.exportJSON())
        XCTAssertEqual(exported.vocabulary.first?.englishDefinition, restored.englishDefinition)
    }
}
