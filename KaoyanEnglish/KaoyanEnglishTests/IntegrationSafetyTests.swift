import XCTest
#if SWIFT_PACKAGE
@testable import KaoyanCore
#else
@testable import KaoyanEnglish
#endif
final class IntegrationSafetyTests: StoreTestCase {
    func testDifferentOriginIdentifiersArePreservedAlongsideItemDetails() throws {
        var p = fixture()
        let firstOrigin = UUID().uuidString.lowercased(), secondOrigin = UUID().uuidString.lowercased()
        p.vocabulary[0].originId = firstOrigin
        _ = try store.importPackage(p)
        var second = p; second.packageId = UUID().uuidString.lowercased()
        second.articles = []; second.questions = []; second.writingExpressions = []
        second.vocabulary[0].id = UUID().uuidString.lowercased(); second.vocabulary[0].originId = secondOrigin
        let report = try store.importPackage(second)
        XCTAssertEqual(report.items?.first?.outcome, .contextAdded)
        XCTAssertEqual(Set(try store.snapshot().vocabulary.compactMap(\.originId)), [firstOrigin,secondOrigin])
        let backup = try store.backup(to: directory.appendingPathComponent("exports"))
        let restoredURL = directory.appendingPathComponent("restore-integration")
        try BackupService.restore(Data(contentsOf: backup), toNewDirectory: restoredURL)
        let restored = try LibraryStore(directory: restoredURL).snapshot()
        XCTAssertEqual(Set(restored.vocabulary.compactMap(\.originId)), [firstOrigin,secondOrigin])
        XCTAssertEqual(restored.history.first?.items?.first?.outcome, .contextAdded)
    }
    func testEmptyPackageHasEmptyDetailsRatherThanUnavailable() throws {
        var p = fixture(); p.articles = []; p.vocabulary = []; p.questions = []; p.writingExpressions = []
        let report = try store.importPackage(p)
        XCTAssertEqual(report.items?.count, 0)
        XCTAssertEqual(try store.snapshot().history.first?.items?.count, 0)
    }
}
