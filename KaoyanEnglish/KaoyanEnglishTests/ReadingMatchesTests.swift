import XCTest
#if SWIFT_PACKAGE
@testable import KaoyanCore
#else
@testable import KaoyanEnglish
#endif

final class ReadingMatchesTests: StoreTestCase {
    func testPreparedArticlesImportAndReimport() throws {
        #if SWIFT_PACKAGE
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("KaoyanEnglish/Resources")
        let urls = ["prepared-media-literacy", "prepared-technology"].map { resources.appendingPathComponent($0 + ".json") }
        #else
        let urls = try ["prepared-media-literacy", "prepared-technology"].map { try XCTUnwrap(Bundle.main.url(forResource: $0, withExtension: "json")) }
        #endif
        let files = try urls.map { try Data(contentsOf: $0) }
        _ = try store.importBatch(files)
        let state = try store.snapshot()
        XCTAssertEqual(state.articles.filter { $0.kind == .original }.count, 3)
        XCTAssertEqual(state.vocabulary.count, 11)
        XCTAssertEqual(state.questions.count, 3)
        XCTAssertEqual(state.writing.count, 3)
        XCTAssertTrue(try store.importBatch(files).allSatisfy(\.alreadyImported))
        XCTAssertEqual(try store.snapshot().articles.count, state.articles.count)
    }
    func testWholeWordsCaseAndUnicodeOffsets() throws {
        let word = fixture().vocabulary[0]
        let text = "中文 FACILITATE, facilitates; facilitate."
        let matches = ReadingMatches.find(in: text, vocabulary: [word], writing: [])
        XCTAssertEqual(matches.count, 2)
        let source = text as NSString
        XCTAssertEqual(matches.map { source.substring(with: $0.range) }, ["FACILITATE", "facilitate"])
        XCTAssertEqual(matches[0].vocabularyIDs, [word.id])
    }
    func testLongestPhraseAndSharedEntriesRemainAccessible() throws {
        var word = fixture().vocabulary[0]; word.expression = "learning"
        var phrase = fixture().writingExpressions[0]; phrase.expression = "effective learning"
        var same = phrase; same.id = UUID().uuidString.lowercased()
        let text = "Effective learning helps learning."
        let matches = ReadingMatches.find(in: text, vocabulary: [word], writing: [phrase,same])
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual((text as NSString).substring(with: matches[0].range), "Effective learning")
        XCTAssertEqual(Set(matches[0].writingIDs), [phrase.id, same.id])
        XCTAssertEqual(matches[1].vocabularyIDs, [word.id])
    }
    func testNoSubstringMatches() {
        var word = fixture().vocabulary[0]; word.expression = "art"
        XCTAssertTrue(ReadingMatches.find(in: "article artificial", vocabulary: [word], writing: []).isEmpty)
        XCTAssertEqual(ReadingMatches.find(in: "art, art's", vocabulary: [word], writing: []).count, 2)
    }
}
