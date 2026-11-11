import XCTest
#if SWIFT_PACKAGE
@testable import KaoyanCore
#else
@testable import KaoyanEnglish
#endif

final class DictionaryRevisionTests: StoreTestCase {
    private func word(_ expression: String, meaning: String = "学习", pos: String? = nil,
                      lemma: String? = nil, article: String? = nil) -> Vocabulary {
        var value = Vocabulary(id: UUID().uuidString.lowercased(), expression: expression, meaning: meaning,
                               sourceArticleIds: [article ?? fixture().articles[0].id])
        value.partOfSpeech = pos
        value.lemma = lemma
        return value
    }

    func testInflectionsShareEntryButKeepOriginalFormsAndExactSenses() {
        let records = [word("study", pos: "verb"), word(" STUDIES ", pos: "verb"),
                       word("studied", pos: "verb"), word("studying", pos: "verb"),
                       word("study", meaning: "研究", pos: "noun"),
                       word("study", meaning: "进行学习", pos: "verb")]
        let entries = VocabularyGrouping.entries(records)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.lemma, "study")
        XCTAssertEqual(entries.first?.records.count, 6)
        XCTAssertEqual(entries.first?.senses.count, 3, "Different wording or part of speech must not be semantically merged.")
        XCTAssertEqual(Set(entries.first?.records.map(\.expression) ?? []), Set(records.map(\.expression)))
    }

    func testUnknownAndAmbiguousWordsAreNotAggressivelyStemmed() {
        let words = [word("axis"), word("axes"), word("news"), word("new"), word("unlistedwording")]
        XCTAssertEqual(VocabularyGrouping.entries(words).count, words.count)
        var explicit = words[1]; explicit.lemma = "axis"
        XCTAssertEqual(VocabularyGrouping.entries([words[0], explicit]).count, 1)
    }

    func testKnownPluralsAndTensesNormalizeCaseAndWhitespace() {
        XCTAssertEqual(VocabularyGrouping.entries([word("dog"), word("DOGS")]).count, 1)
        XCTAssertEqual(VocabularyGrouping.entries([word("work"), word("works"), word("worked"), word("working")]).count, 1)
        XCTAssertEqual(VocabularyGrouping.entries([word(" PLAY   A ROLE "), word("play a role")]).count, 1)
    }

    func testWordFamiliesLinkExistingEntriesWithoutMergingOrSpellingGuesses() throws {
        var verb = word("educate", meaning: "教育", pos: "verb")
        var noun = word("education", meaning: "教育", pos: "noun")
        verb.wordFamily = "education"; noun.wordFamily = "education"
        let unrelated = word("educationallyish", meaning: "未可靠关联")
        let entries = VocabularyGrouping.entries([verb, noun, unrelated])
        XCTAssertEqual(entries.count, 3)
        let entry = try XCTUnwrap(entries.first { $0.lemma == "educate" })
        let related = VocabularyGrouping.related(to: entry, in: entries)
        XCTAssertTrue(related.contains { $0.lemma == "education" })
        XCTAssertFalse(related.contains { $0.lemma == "educationallyish" || $0.id == entry.id })
    }

    func testMissingPartOfSpeechRemainsDistinctAndExactMeaningOnlyDeduplicates() throws {
        let records = [word("record", meaning: "记录", pos: "noun"), word("record", meaning: "记录", pos: "verb"),
                       word("record", meaning: "记录"), word("record", meaning: "记录"),
                       word("record", meaning: "记录下来")]
        let entry = try XCTUnwrap(VocabularyGrouping.entries(records).first)
        XCTAssertEqual(entry.senses.count, 4)
        XCTAssertEqual(entry.records.count, 5)
    }

    func testWhitespaceAndPartOfSpeechAliasesShareSenseButWordingDoesNot() throws {
        let records = [word("study", meaning: " 学习 ", pos: "noun"),
                       word("study", meaning: "学习", pos: "n"),
                       word("study", meaning: "学习。", pos: "noun"),
                       word("study", meaning: "学习", pos: "verb")]
        let entry = try XCTUnwrap(VocabularyGrouping.entries(records).first)
        XCTAssertEqual(entry.senses.count, 3)
        XCTAssertEqual(entry.records.count, 4)
        let exact = try XCTUnwrap(entry.senses.first {
            $0.partOfSpeech == "名词" && VocabularyGrouping.normalizedMeaning($0.meaning) == "学习"
        })
        XCTAssertEqual(exact.records.count, 2)
    }

    func testFiltersMatchOneContextButDoNotDiscardOtherMeaningsFromDetailEntry() throws {
        var first = word("study", meaning: "学习", pos: "verb")
        first.topics = ["教育与人才培养"]; first.difficulty = 2; first.englishDefinition = "to learn about a subject"
        var second = word("studies", meaning: "研究", pos: "noun")
        second.topics = ["科技与人工智能"]; second.difficulty = 5
        let all = [first, second]
        let results = VocabularyGrouping.filteredEntries(all, search: "learn", topic: "教育与人才培养", difficulty: 2,
                                                        favoritesOnly: true, favoriteIDs: [first.id])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.records.count, 2, "Filtering the list must not hide sibling senses from the entry.")
        XCTAssertTrue(try XCTUnwrap(results.first).isFavorite([first.id]))
        let contradictory = VocabularyGrouping.filteredEntries(all, search: "", topic: "教育与人才培养", difficulty: 5,
                                                              favoritesOnly: false, favoriteIDs: [])
        XCTAssertTrue(contradictory.isEmpty, "One occurrence must satisfy the combined topic/difficulty criteria.")
    }

    func testDuplicateMeaningRetainsBothSourceExamplesAndMetadataThroughExportAndReopen() throws {
        var first = fixture()
        first.vocabulary[0].originalSentence = "A new tool can facilitate learning."
        first.vocabulary[0].sentenceTranslation = "新工具可以促进学习。"
        first.vocabulary[0].uncommonMeaning = "保留的旧字段"
        first.vocabulary[0].writingValue = "保留的写作价值"
        _ = try store.importPackage(first)
        try store.setFavorite(id: first.vocabulary[0].id, kind: .vocabulary, favorite: true)

        var second = first; second.packageId = UUID().uuidString.lowercased()
        second.articles[0].id = UUID().uuidString.lowercased()
        second.vocabulary[0].id = UUID().uuidString.lowercased()
        second.vocabulary[0].expression = "FACILITATE"
        second.vocabulary[0].sourceArticleIds = [second.articles[0].id]
        second.vocabulary[0].originalSentence = "Clear rules facilitate communication."
        second.vocabulary[0].sentenceTranslation = "清晰的规则促进交流。"
        second.vocabulary[0].phonetic = "/fəˈsɪlɪteɪt/"
        second.vocabulary[0].englishDefinition = "to make an activity easier"
        second.questions = []; second.writingExpressions = []
        _ = try store.importPackage(second)
        store = nil; store = try LibraryStore(directory: directory)
        let snapshot = try store.snapshot()
        XCTAssertEqual(snapshot.vocabulary.count, 2)
        let entry = try XCTUnwrap(VocabularyGrouping.entries(snapshot.vocabulary).first)
        XCTAssertEqual(entry.senses.count, 1)
        XCTAssertTrue(entry.isFavorite(snapshot.favoriteVocabulary))
        XCTAssertEqual(Set(entry.records.compactMap(\.originalSentence)), Set([first.vocabulary[0].originalSentence!, second.vocabulary[0].originalSentence!]))
        XCTAssertEqual(Set(entry.records.flatMap(\.sourceArticleIds)), Set([first.articles[0].id, second.articles[0].id]))
        XCTAssertEqual(try store.vocabulary(id: first.vocabulary[0].id).writingValue, "保留的写作价值")
        let exported = try PackageValidator.decode(store.exportJSON())
        XCTAssertEqual(Set(exported.vocabulary.compactMap(\.originalSentence)), Set(entry.records.compactMap(\.originalSentence)))
        XCTAssertEqual(exported.vocabulary.first { $0.id == second.vocabulary[0].id }?.englishDefinition, "to make an activity easier")
        try store.checkIntegrity()
    }

    func testSameImportedIDWithNewContextPreservesBothVersionsWithoutOverwriting() throws {
        var first = fixture(); first.vocabulary[0].originalSentence = "First recorded sentence."
        _ = try store.importPackage(first)
        var next = first; next.packageId = UUID().uuidString.lowercased()
        next.vocabulary[0].originalSentence = "Another source sentence."
        next.vocabulary[0].sentenceTranslation = "另一条例句。"
        _ = try store.importPackage(next)
        let records = try store.snapshot().vocabulary
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(Set(records.compactMap(\.originalSentence)), ["First recorded sentence.", "Another source sentence."])
        XCTAssertTrue(records.contains { $0.originId == first.vocabulary[0].id && $0.id != first.vocabulary[0].id })
        XCTAssertTrue(try store.importPackage(next).alreadyImported)
        XCTAssertEqual(try store.snapshot().vocabulary.count, 2)
        let exportedData = try store.exportJSON()
        _ = try store.importData(exportedData)
        XCTAssertEqual(try store.snapshot().vocabulary.count, 2)
        let restored = try LibraryStore(directory: directory.appendingPathComponent("context-roundtrip"))
        _ = try restored.importData(exportedData)
        let restoredRecords = try restored.snapshot().vocabulary
        XCTAssertEqual(Set(restoredRecords.map(\.id)), Set(records.map(\.id)))
        XCTAssertEqual(Set(restoredRecords.compactMap(\.originId)), Set(records.compactMap(\.originId)))
        XCTAssertEqual(Set(restoredRecords.compactMap(\.originalSentence)), Set(records.compactMap(\.originalSentence)))
    }

    func testIdenticalRecordInNewPackageDoesNotCreateAnotherOccurrence() throws {
        let first = fixture(); _ = try store.importPackage(first)
        var next = first; next.packageId = UUID().uuidString.lowercased()
        _ = try store.importPackage(next)
        XCTAssertEqual(try store.snapshot().vocabulary.count, 1)
    }

    func testEditAndDeleteOneSenseLeavesOtherSenseFavoriteAndQuestionAttempts() throws {
        var package = fixture()
        var other = package.vocabulary[0]; other.id = UUID().uuidString.lowercased(); other.meaning = "使过程更容易"
        package.vocabulary.append(other)
        _ = try store.importPackage(package)
        try store.setVocabularyFavorites(ids: package.vocabulary.map(\.id), favorite: true)
        let attempt = AnswerAttempt(id: UUID().uuidString.lowercased(), questionId: package.questions[0].id,
                                    answer: "B", isCorrect: true, submittedAt: Timestamp.now())
        try store.saveAttempt(attempt)
        var edited = try store.vocabulary(id: package.vocabulary[0].id)
        edited.meaning = "促进某项活动"; edited.originalSentence = "An edited example."
        try store.updateVocabulary(edited)
        XCTAssertEqual(try store.vocabulary(id: other.id).meaning, other.meaning)
        try store.delete(id: edited.id, kind: .vocabulary)
        let snapshot = try store.snapshot()
        XCTAssertEqual(snapshot.vocabulary.map(\.id), [other.id])
        XCTAssertTrue(snapshot.favoriteVocabulary.contains(other.id))
        XCTAssertEqual(snapshot.attempts.map(\.id), [attempt.id])
        try store.checkIntegrity()
    }

    func testGroupedFavoriteChangeIsAtomicIfOneRecordIsMissing() throws {
        let package = fixture(); _ = try store.importPackage(package)
        XCTAssertThrowsError(try store.setVocabularyFavorites(ids: [package.vocabulary[0].id, UUID().uuidString.lowercased()], favorite: true))
        XCTAssertFalse(try store.snapshot().favoriteVocabulary.contains(package.vocabulary[0].id))
    }

    func testVersionOneMigrationPreservesLegacyPayloadAliasesFavoritesAndAttempts() throws {
        var package = fixture()
        package.vocabulary[0].uncommonMeaning = "旧熟词僻义字段"
        package.vocabulary[0].writingValue = "旧写作价值字段"
        _ = try store.importPackage(package)
        let saved = try store.vocabulary(id: package.vocabulary[0].id)
        let aliasId = UUID().uuidString.lowercased()
        let attempt = AnswerAttempt(id: UUID().uuidString.lowercased(), questionId: package.questions[0].id,
                                    answer: "B", isCorrect: true, submittedAt: Timestamp.now())
        try store.saveAttempt(attempt)
        // Reconstruct a real version-one vocabulary file in the isolated fixture only.
        try store.db.transaction {
            try store.db.execute("DROP TABLE vocab.record_topics")
            try store.db.execute("DROP TABLE vocab.record_article_links")
            try store.db.execute("DROP TABLE vocab.record_aliases")
            try store.db.execute("DROP TABLE vocab.records")
            try store.db.execute("INSERT INTO vocab.vocabulary (id,expression,meaning,difficulty,dedup_key,favorite,payload) VALUES (?,?,?,?,?,1,?)", [saved.id,saved.expression,saved.meaning,saved.difficulty.map(String.init),saved.dedupKey,try JSONCoding.string(saved)])
            try store.db.execute("INSERT INTO vocab.aliases VALUES (?,?)", [saved.id,saved.id])
            try store.db.execute("INSERT INTO vocab.aliases VALUES (?,?)", [aliasId,saved.id])
            for id in saved.sourceArticleIds { try store.db.execute("INSERT INTO vocab.article_links VALUES (?,?)", [saved.id,id]) }
            for topic in saved.topics ?? [] { try store.db.execute("INSERT INTO vocab.topics VALUES (?,?)", [saved.id,topic]) }
            for (schema, _) in DatabaseSchema.files { try store.db.execute("PRAGMA \(schema).user_version=1") }
        }
        store = nil; store = try LibraryStore(directory: directory)
        let snapshot = try store.snapshot()
        XCTAssertEqual(snapshot.vocabulary, [saved])
        XCTAssertTrue(snapshot.favoriteVocabulary.contains(saved.id))
        XCTAssertEqual(snapshot.attempts.map(\.id), [attempt.id])
        XCTAssertEqual(snapshot.history.count, 1)
        XCTAssertEqual(try store.db.rows("SELECT entity_id FROM vocab.record_aliases WHERE alias_id=?", [aliasId]).first?["entity_id"], saved.id)
        XCTAssertEqual(try store.db.rows("PRAGMA vocab.user_version").first?["user_version"], "2")
        XCTAssertEqual(try store.db.rows("SELECT count(*) AS n FROM vocab.vocabulary").first?["n"], "1", "Legacy archive is retained.")
        try store.checkIntegrity()
    }

    func testOriginalCategoriesAndQuestionEntrancesKeepUnderlyingRecords() {
        var snapshot = LibrarySnapshot()
        let original = fixture().articles[0]
        var unclassified = original; unclassified.id = UUID().uuidString.lowercased(); unclassified.theme = " \n "
        var classified = original; classified.id = UUID().uuidString.lowercased(); classified.theme = "科技与人工智能"
        var adapted = original; adapted.id = UUID().uuidString.lowercased(); adapted.kind = .adapted
        adapted.originalArticleId = original.id; adapted.theme = "仅改编文分类"
        snapshot.articles = [original, unclassified, classified, adapted]
        XCTAssertEqual(ArticleNavigation.originals(in: snapshot).count, 3)
        XCTAssertEqual(ArticleNavigation.originals(in: snapshot, category: "未分类").count, 2)
        XCTAssertEqual(ArticleNavigation.originals(in: snapshot, category: "科技与人工智能").map(\.id), [classified.id])
        XCTAssertFalse(ArticleNavigation.categories(in: snapshot).contains("仅改编文分类"))
        XCTAssertEqual(ArticleNavigation.questionArticles(in: snapshot).map(\.id), [adapted.id])
        XCTAssertEqual(snapshot.articles.count, 4, "Navigation filtering must never delete original rows.")
    }

    func testOriginalQuestionLinksIncludeAdaptationsDeduplicateAndKeepAnswersHidden() throws {
        let original = fixture().articles[0]
        var adapted = original; adapted.id = UUID().uuidString.lowercased(); adapted.kind = .adapted; adapted.originalArticleId = original.id
        var unrelated = adapted; unrelated.id = UUID().uuidString.lowercased(); unrelated.originalArticleId = UUID().uuidString.lowercased()
        let directQuestion = fixture().questions[0]
        var adaptedQuestion = directQuestion; adaptedQuestion.id = UUID().uuidString.lowercased(); adaptedQuestion.articleId = adapted.id
        var unrelatedQuestion = directQuestion; unrelatedQuestion.id = UUID().uuidString.lowercased(); unrelatedQuestion.articleId = unrelated.id
        var snapshot = LibrarySnapshot()
        snapshot.articles = [original, adapted, unrelated]
        snapshot.questions = [directQuestion, adaptedQuestion, adaptedQuestion, unrelatedQuestion]
        let linked = ArticleNavigation.questions(for: original.id, in: snapshot)
        XCTAssertEqual(Set(linked.map(\.id)), [directQuestion.id, adaptedQuestion.id])
        XCTAssertEqual(linked.count, 2)
        XCTAssertEqual(ArticleNavigation.relatedArticleIds(to: original.id, in: snapshot), [original.id, adapted.id])
        XCTAssertEqual(ArticleNavigation.adaptations(of: original.id, in: snapshot).first?.title, adapted.title)
        for question in linked {
            let session = QuestionSession(question: question)
            XCTAssertNil(session.revealedAnswer); XCTAssertNil(session.revealedExplanation)
            XCTAssertNil(session.revealedEvidence); XCTAssertNil(session.revealedDistractors)
        }
    }

    func testOldImportHistoryRetainsRecordedFactsAfterContentChanges() throws {
        let package = fixture(); let originalReport = try store.importPackage(package)
        try store.delete(id: package.vocabulary[0].id, kind: .vocabulary)
        let report = try XCTUnwrap(store.snapshot().history.first)
        XCTAssertEqual(report, originalReport)
        XCTAssertEqual(report.vocabularyAdded, 1)
        XCTAssertEqual(report.packageId, package.packageId)
        XCTAssertEqual(report.failed, 0)
        let oldJSON = try JSONCoding.encoder().encode(originalReport)
        XCTAssertEqual(try JSONCoding.decoder().decode(ImportReport.self, from: oldJSON), originalReport)
        XCTAssertTrue(try store.snapshot().vocabulary.isEmpty, "History counts remain historical facts; current rows cannot be used to infer deleted import details.")
    }
}
