import XCTest
#if SWIFT_PACKAGE
@testable import KaoyanCore
#else
@testable import KaoyanEnglish
#endif

final class ContractTests: StoreTestCase {
    func testBundledExampleImportsAndReimports() throws {
        #if SWIFT_PACKAGE
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("KaoyanEnglish/Resources/sample-package.json")
        #else
        let url = try XCTUnwrap(Bundle.main.url(forResource: "sample-package", withExtension: "json"))
        #endif
        let data = try Data(contentsOf: url)
        let report = try store.importData(data)
        XCTAssertEqual(report.vocabularyAdded, 3); XCTAssertEqual(report.questionsAdded, 2); XCTAssertEqual(report.writingAdded, 1)
        XCTAssertTrue(try store.importData(data).alreadyImported)
        XCTAssertEqual(try store.snapshot().articles.filter { $0.kind == .adapted }.first?.originalArticleId,
                       try store.snapshot().articles.filter { $0.kind == .original }.first?.id)
    }
    func testBatchValidationFailureRollsBackEarlierPackage() throws {
        let first = fixture()
        var invalid = fixture(); invalid.articles = []; invalid.questions[0].articleId = UUID().uuidString.lowercased()
        let data = try [first,invalid].map { try JSONCoding.encoder().encode($0) }
        XCTAssertThrowsError(try store.importBatch(data))
        XCTAssertTrue(try store.snapshot().history.isEmpty)
        XCTAssertTrue(try store.snapshot().vocabulary.isEmpty)
        try store.checkIntegrity()
    }
    func testBatchCanReferToEarlierPackage() throws {
        let first = fixture()
        var second = fixture(); second.articles = []; second.questions = []; second.writingExpressions = []
        second.vocabulary[0].id = UUID().uuidString.lowercased(); second.vocabulary[0].expression = "critical thinking"
        XCTAssertEqual(try store.importBatch([first,second].map { try JSONCoding.encoder().encode($0) }).count, 2)
        XCTAssertEqual(try store.snapshot().vocabulary.count, 2)
    }
    func testGlobalIDCollisionAndInvalidAdaptationRejected() throws {
        let first = fixture(); _ = try store.importPackage(first)
        var bad = first; bad.packageId = UUID().uuidString.lowercased(); bad.vocabulary = []
        bad.writingExpressions[0].id = first.vocabulary[0].id
        XCTAssertThrowsError(try store.importPackage(bad))
        bad = fixture(); bad.articles[0].kind = .adapted
        XCTAssertThrowsError(try store.importPackage(bad))
    }
    func testFutureDatabaseVersionIsNotDowngraded() throws {
        try store.db.execute("PRAGMA vocab.user_version=99")
        store = nil
        XCTAssertThrowsError(try LibraryStore(directory: directory))
        let raw = try SQLiteConnection(url: directory.appendingPathComponent("vocabulary.sqlite"))
        XCTAssertEqual(try raw.rows("PRAGMA user_version").first?["user_version"], "99")
    }
    func testQuestionAndWritingCRUD() throws {
        let p = fixture(); _ = try store.importPackage(p)
        var writing = p.writingExpressions[0]; writing.context = "新增语境"; try store.updateWriting(writing)
        XCTAssertEqual(try store.writing(id: writing.id).context, "新增语境")
        var question = p.questions[0]; question.explanation = "新的解析"; try store.updateQuestion(question)
        XCTAssertEqual(try store.snapshot().questions[0].explanation, "新的解析")
        var article = try XCTUnwrap(store.snapshot().articles.first); article.title = "更新标题"; try store.updateArticle(article)
        XCTAssertEqual(try store.snapshot().articles[0].title, "更新标题")
        try store.delete(id: writing.id, kind: .writing); try store.delete(id: question.id, kind: .question)
        try store.delete(id: p.vocabulary[0].id, kind: .vocabulary); try store.delete(id: article.id, kind: .article)
        XCTAssertTrue(try store.snapshot().articles.isEmpty); try store.checkIntegrity()
    }
}
