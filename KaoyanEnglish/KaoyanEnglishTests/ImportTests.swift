import XCTest
#if SWIFT_PACKAGE
@testable import KaoyanCore
#else
@testable import KaoyanEnglish
#endif

final class ImportTests: StoreTestCase {
    func testJSONImportAndExportRoundTrip() throws {
        let p = fixture(); let data = try JSONCoding.encoder().encode(p)
        let report = try store.importData(data)
        XCTAssertEqual(report.vocabularyAdded, 1); XCTAssertEqual(report.questionsAdded, 1); XCTAssertEqual(report.writingAdded, 1)
        let exported = try PackageValidator.decode(store.exportJSON())
        XCTAssertEqual(exported.articles.first?.body, p.articles[0].body)
        _ = try store.importPackage(exported)
        XCTAssertEqual(try store.snapshot().vocabulary.count, 1)
    }
    func testDuplicatePackageDoesNotRecreateDeletedData() throws {
        let p = fixture(); _ = try store.importPackage(p)
        try store.delete(id: p.vocabulary[0].id, kind: .vocabulary)
        let report = try store.importPackage(p)
        XCTAssertTrue(report.alreadyImported); XCTAssertEqual(report.vocabularyAdded, 0)
        XCTAssertEqual(try store.snapshot().history.count, 1); XCTAssertTrue(try store.snapshot().vocabulary.isEmpty)
    }
    func testDuplicateWordMergesMultipleSourcesAndPreservesLearning() throws {
        let p = fixture(); _ = try store.importPackage(p)
        try store.setFavorite(id: p.vocabulary[0].id, kind: .vocabulary, favorite: true)
        var second = p; second.packageId = UUID().uuidString.lowercased()
        second.articles[0].id = UUID().uuidString.lowercased()
        second.vocabulary[0].id = UUID().uuidString.lowercased()
        second.vocabulary[0].expression = "  FACILITATE  "
        second.vocabulary[0].sourceArticleIds = [second.articles[0].id]
        second.vocabulary[0].phonetic = "must not overwrite"
        second.questions = []; second.writingExpressions = []
        let report = try store.importPackage(second)
        XCTAssertEqual(report.duplicates, 1)
        let snapshot = try store.snapshot()
        XCTAssertEqual(snapshot.vocabulary.count, 2)
        let entry = try XCTUnwrap(VocabularyGrouping.entries(snapshot.vocabulary).first)
        XCTAssertEqual(VocabularyGrouping.entries(snapshot.vocabulary).count, 1)
        XCTAssertEqual(Set(entry.records.flatMap(\.sourceArticleIds)), Set([p.articles[0].id, second.articles[0].id]))
        XCTAssertNil(snapshot.vocabulary.first(where: { $0.id == p.vocabulary[0].id })?.phonetic)
        XCTAssertEqual(snapshot.vocabulary.first(where: { $0.id == second.vocabulary[0].id })?.phonetic, "must not overwrite")
        XCTAssertTrue(entry.isFavorite(snapshot.favoriteVocabulary))
    }
    func testMalformedJSONMissingFieldAndInvalidReferencesDoNotWrite() throws {
        _ = try store.importPackage(fixture())
        XCTAssertThrowsError(try store.importData(Data("{bad json".utf8)))
        XCTAssertThrowsError(try store.importData(Data("{}".utf8)))
        var p = fixture(); p.questions[0].articleId = UUID().uuidString.lowercased()
        XCTAssertThrowsError(try store.importPackage(p))
        p = fixture(); p.questions[0].correctAnswer = "missing"
        XCTAssertThrowsError(try store.importPackage(p))
        XCTAssertEqual(try store.snapshot().history.count, 1)
    }
    func testMidWriteFailureRollsBackAllThreeDatabases() throws {
        let p = fixture()
        // Failure after article + vocabulary + question + writing have all been written.
        XCTAssertThrowsError(try store.importPackage(p, faultAfterWrites: 4))
        let s = try store.snapshot()
        XCTAssertTrue(s.articles.isEmpty && s.vocabulary.isEmpty && s.questions.isEmpty && s.writing.isEmpty && s.history.isEmpty)
        store = nil; store = try LibraryStore(directory: directory)
        XCTAssertEqual(try store.importPackage(p).vocabularyAdded, 1)
    }
    func testChangedPackageAndReusedIDRejected() throws {
        let p = fixture(); _ = try store.importPackage(p)
        var changed = p; changed.vocabulary[0].phonetic = "changed"
        XCTAssertThrowsError(try store.importPackage(changed))
        changed.packageId = UUID().uuidString.lowercased(); changed.vocabulary[0].meaning = "another meaning"
        XCTAssertThrowsError(try store.importPackage(changed))
        XCTAssertEqual(try store.snapshot().vocabulary.count, 1)
    }
    func testOptionalFieldsAndUnknownVersion() throws {
        var p = fixture(); p.schemaVersion = "2.0"
        XCTAssertThrowsError(try store.importPackage(p))
        p.schemaVersion = "1.0"; _ = try store.importData(JSONCoding.encoder().encode(p))
        XCTAssertNil(try store.snapshot().vocabulary[0].phonetic)
    }
    func testQuestionAndWritingSemanticDedup() throws {
        let p = fixture(); _ = try store.importPackage(p)
        var second = p; second.packageId = UUID().uuidString.lowercased()
        second.vocabulary = []; second.questions[0].id = UUID().uuidString.lowercased()
        second.writingExpressions[0].id = UUID().uuidString.lowercased()
        let report = try store.importPackage(second)
        XCTAssertEqual(report.duplicates, 2)
        XCTAssertEqual(try store.snapshot().questions.count, 1)
        XCTAssertEqual(try store.snapshot().writing.count, 1)
    }
    func testImportReportStoresItemDetailsAndLegacyReportsDecodeWithoutItems() throws {
        let p = fixture()
        let report = try store.importPackage(p)
        let items = try XCTUnwrap(report.items)
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(Set(items.map(\.kind)), Set([.article, .vocabulary, .question, .writing]))
        XCTAssertEqual(items.first { $0.kind == .vocabulary }?.title, "facilitate")
        XCTAssertEqual(items.first { $0.kind == .vocabulary }?.detail, "促进；使便利")
        XCTAssertEqual(items.first { $0.kind == .vocabulary }?.outcome, .added)
        XCTAssertEqual(try store.snapshot().history.first, report)
        let legacy = """
        {"package_id":"\(p.packageId)","imported_at":"2026-11-10T00:00:00Z","vocabulary_added":1,"questions_added":1,"writing_added":1,"duplicates":0,"failed":0,"already_imported":false}
        """
        let decoded = try JSONCoding.decoder().decode(ImportReport.self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.items)
        XCTAssertNil(decoded.itemsTruncated)
        XCTAssertEqual(decoded.vocabularyAdded, 1)
    }
    func testImportItemOutcomesDistinguishNewContextAndMergedDuplicate() throws {
        let p = fixture(); _ = try store.importPackage(p)
        var context = p; context.packageId = UUID().uuidString.lowercased()
        context.articles = []; context.questions = []; context.writingExpressions = []
        context.vocabulary[0].id = UUID().uuidString.lowercased()
        context.vocabulary[0].originalSentence = "A different sentence."
        let contextReport = try store.importPackage(context)
        XCTAssertEqual(contextReport.items?.first?.outcome, .contextAdded)
        XCTAssertEqual(contextReport.duplicates, 1)
        var duplicate = p; duplicate.packageId = UUID().uuidString.lowercased()
        duplicate.articles = []; duplicate.questions = []; duplicate.writingExpressions = []
        duplicate.vocabulary[0].id = UUID().uuidString.lowercased()
        let duplicateReport = try store.importPackage(duplicate)
        XCTAssertEqual(duplicateReport.items?.first?.outcome, .merged)
        XCTAssertEqual(duplicateReport.duplicates, 1)
        XCTAssertEqual(try store.snapshot().vocabulary.count, 2)
    }
    func testImportItemListIsBoundedAndMarkedTruncated() throws {
        var p = fixture()
        let base = p.vocabulary[0]
        p.vocabulary = (0..<205).map { index in
            var value = base
            value.id = UUID().uuidString.lowercased()
            value.expression = "word\(index)"
            value.meaning = "释义 \(index)"
            return value
        }
        let report = try store.importPackage(p)
        XCTAssertEqual(report.vocabularyAdded, 205)
        XCTAssertEqual(report.items?.count, ImportReport.maximumItems)
        XCTAssertEqual(report.itemsTruncated, true)
        XCTAssertEqual(try store.snapshot().history.first?.itemsTruncated, true)
    }
}
