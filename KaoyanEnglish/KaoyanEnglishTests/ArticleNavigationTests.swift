import XCTest
#if SWIFT_PACKAGE
@testable import KaoyanCore
#else
@testable import KaoyanEnglish
#endif

final class ArticleNavigationTests: XCTestCase {
    private func article(_ id: String, kind: ArticleKind = .original, theme: String? = nil, parent: String? = nil) -> Article {
        Article(id: id, title: "Article \(id)", body: "An article for reading.", kind: kind, originalArticleId: parent, theme: theme)
    }
    private func question(_ id: String, articleId: String) -> Question {
        Question(id: id, articleId: articleId, type: .readingSingleChoice, stem: "What is the point?", correctAnswer: "A", explanation: "Explanation", options: [.init(id: "A", text: "First"), .init(id: "B", text: "Second")])
    }
    func testOriginalCategoriesAndUncategorized() {
        let snapshot = LibrarySnapshot(articles: [article("1", theme: nil), article("2", theme: " \n"), article("3", theme: " 科技 "), article("4", kind: .adapted, theme: "不应出现", parent: "3")])
        XCTAssertEqual(ArticleNavigation.originals(in: snapshot).count, 3)
        XCTAssertEqual(ArticleNavigation.originals(in: snapshot, category: "未分类").map(\.id), ["1", "2"])
        XCTAssertEqual(ArticleNavigation.originals(in: snapshot, category: "科技").map(\.id), ["3"])
        XCTAssertFalse(ArticleNavigation.categories(in: snapshot).contains("不应出现"))
        XCTAssertTrue(ArticleNavigation.originals(in: snapshot, category: "教育").isEmpty)
    }
    func testOriginalQuestionsIncludeAdaptationsExactlyOnceAndPreserveGate() {
        let first = question("q1", articleId: "original")
        let second = question("q2", articleId: "adapted")
        let unrelated = question("q3", articleId: "other")
        let snapshot = LibrarySnapshot(articles: [article("original"), article("adapted", kind: .adapted, parent: "original"), article("other")], questions: [first, second, second, unrelated])
        XCTAssertEqual(Set(ArticleNavigation.questions(for: "original", in: snapshot).map(\.id)), ["q1", "q2"])
        XCTAssertEqual(ArticleNavigation.questions(for: "original", in: snapshot).count, 2)
        XCTAssertEqual(ArticleNavigation.relatedArticleIds(to: "original", in: snapshot), ["original", "adapted"])
        for question in ArticleNavigation.questions(for: "original", in: snapshot) {
            let session = QuestionSession(question: question)
            XCTAssertNil(session.revealedAnswer)
            XCTAssertNil(session.revealedExplanation)
        }
    }
    func testQuestionLibraryOnlyAdaptationsAndFilters() {
        let snapshot = LibrarySnapshot(articles: [article("original"), article("adapted", kind: .adapted, parent: "original")], questions: [question("q1", articleId: "original"), question("q2", articleId: "adapted")])
        XCTAssertEqual(ArticleNavigation.questionArticles(in: snapshot).map(\.id), ["adapted"])
        XCTAssertEqual(ArticleNavigation.questionArticles(in: snapshot, type: QuestionType.readingSingleChoice.rawValue).count, 1)
        XCTAssertTrue(ArticleNavigation.questionArticles(in: snapshot, type: QuestionType.translation.rawValue).isEmpty)
        XCTAssertTrue(ArticleNavigation.questionArticles(in: snapshot, search: "missing").isEmpty)
        // Filtering never mutates or removes stored originals.
        XCTAssertEqual(snapshot.articles.count, 2)
        XCTAssertEqual(snapshot.questions.count, 2)
    }
    func testEmptyOriginalHasNoInferredQuestionsOrAdaptations() {
        let snapshot = LibrarySnapshot(articles: [article("original")])
        XCTAssertTrue(ArticleNavigation.questions(for: "original", in: snapshot).isEmpty)
        XCTAssertTrue(ArticleNavigation.adaptations(of: "original", in: snapshot).isEmpty)
    }
}
