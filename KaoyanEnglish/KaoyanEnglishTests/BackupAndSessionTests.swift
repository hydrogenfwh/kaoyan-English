import XCTest
#if SWIFT_PACKAGE
@testable import KaoyanCore
#else
@testable import KaoyanEnglish
#endif

final class BackupAndSessionTests: StoreTestCase {
    func testBackupRestoresAllDataAndLearningState() throws {
        let p = fixture(); _ = try store.importPackage(p)
        try store.setFavorite(id: p.writingExpressions[0].id, kind: .writing, favorite: true)
        var session = QuestionSession(question: p.questions[0]); session.selectedAnswer = "B"
        try store.saveAttempt(session.makeAttempt())
        let url = try store.backup(to: directory.appendingPathComponent("exports"))
        let data = try Data(contentsOf: url)
        let restoredDirectory = directory.appendingPathComponent("restored")
        try BackupService.restore(data, toNewDirectory: restoredDirectory)
        let restored = try LibraryStore(directory: restoredDirectory)
        let snapshot = try restored.snapshot()
        XCTAssertEqual(snapshot.vocabulary.count, 1); XCTAssertEqual(snapshot.history.count, 1)
        XCTAssertEqual(snapshot.attempts.count, 1); XCTAssertTrue(snapshot.favoriteWriting.contains(p.writingExpressions[0].id))
        XCTAssertThrowsError(try BackupService.restore(data, toNewDirectory: restoredDirectory))
        var broken = try JSONCoding.decoder().decode(BackupArchive.self, from: data)
        broken.checksums["questions.sqlite"] = "incorrect"
        XCTAssertThrowsError(try BackupService.restore(JSONCoding.encoder().encode(broken), toNewDirectory: directory.appendingPathComponent("bad")))
    }
    func testAnswersHiddenUntilDurableSubmissionAndReset() throws {
        let p = fixture(); _ = try store.importPackage(p)
        var session = QuestionSession(question: p.questions[0])
        XCTAssertNil(session.revealedAnswer); XCTAssertNil(session.revealedExplanation)
        XCTAssertNil(session.revealedEvidence); XCTAssertNil(session.revealedDistractors)
        XCTAssertFalse(session.canSubmit); XCTAssertThrowsError(try session.makeAttempt())
        session.selectedAnswer = "A"
        XCTAssertNil(session.revealedAnswer)
        let attempt = try session.makeAttempt(); try store.saveAttempt(attempt); session.markSubmitted()
        XCTAssertEqual(session.revealedAnswer, "B"); XCTAssertNotNil(session.revealedExplanation)
        XCTAssertFalse(session.canSubmit); XCTAssertEqual(try store.snapshot().attempts[0].isCorrect, false)
        session.reset(); XCTAssertNil(session.revealedAnswer); XCTAssertFalse(session.canSubmit)
    }
    func testFailedSubmissionKeepsAnswersHidden() throws {
        let p = fixture()
        var session = QuestionSession(question: p.questions[0]); session.selectedAnswer = "B"
        XCTAssertThrowsError(try store.saveAttempt(session.makeAttempt()))
        XCTAssertNil(session.revealedAnswer); XCTAssertNil(session.revealedExplanation)
    }
}
