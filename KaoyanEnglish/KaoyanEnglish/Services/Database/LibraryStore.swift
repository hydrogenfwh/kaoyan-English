import Foundation
import CryptoKit

// One store owns all three files. Every entry point is serialized by this recursive lock.
// The application additionally runs the store on LibraryWorker's actor, off the UI actor.
final class LibraryStore {
    let directory: URL
    let db: SQLiteConnection
    let lock = NSRecursiveLock()
    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        db = try SQLiteConnection(url: directory.appendingPathComponent("questions.sqlite"))
        try db.execute("ATTACH DATABASE ? AS vocab", [directory.appendingPathComponent("vocabulary.sqlite").path])
        try db.execute("ATTACH DATABASE ? AS writing", [directory.appendingPathComponent("writing.sqlite").path])
        // Atomic commit across ATTACHed files requires an on-disk main DB and rollback journals,
        // not WAL. SQLite's super-journal provides crash recovery on next open.
        for (schema, _) in DatabaseSchema.files {
            let mode = try db.rows("PRAGMA \(schema).journal_mode = DELETE").first?["journal_mode"]
            guard mode == "delete" else { throw LibraryError.database("无法启用跨库回滚日志") }
            try db.execute("PRAGMA \(schema).synchronous = FULL")
        }
        try DatabaseSchema.migrate(db)
        try checkIntegrity()
    }
    func synchronized<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }; return try body()
    }
    func records<T: Decodable>(_ type: T.Type, table: String) throws -> [T] {
        try db.rows("SELECT payload FROM \(table) ORDER BY rowid DESC").map { try JSONCoding.decode(type, $0["payload"]!) }
    }
    func snapshot() throws -> LibrarySnapshot {
        try synchronized {
            LibrarySnapshot(sources: try records(Source.self, table: "main.sources"), articles: try records(Article.self, table: "main.articles"),
                            vocabulary: try records(Vocabulary.self, table: "vocab.records"), questions: try records(Question.self, table: "main.questions"),
                            writing: try records(WritingExpression.self, table: "writing.expressions"),
                            favoriteVocabulary: Set(try db.rows("SELECT id FROM vocab.records WHERE favorite = 1").compactMap { $0["id"] }),
                            favoriteWriting: Set(try db.rows("SELECT id FROM writing.expressions WHERE favorite = 1").compactMap { $0["id"] }),
                            history: try records(ImportReport.self, table: "main.import_history"), attempts: try records(AnswerAttempt.self, table: "main.attempts"))
        }
    }
    func checkIntegrity() throws {
        try synchronized {
            for (schema, _) in DatabaseSchema.files {
                guard try db.rows("PRAGMA \(schema).integrity_check").allSatisfy({ $0.values.first == "ok" }),
                      try db.rows("PRAGMA \(schema).foreign_key_check").isEmpty else { throw LibraryError.database("\(schema) 完整性检查失败") }
            }
            for schema in ["vocab", "writing"] {
                let linkTable = schema == "vocab" ? "record_article_links" : "article_links"
                guard try db.rows("SELECT l.article_id FROM \(schema).\(linkTable) l LEFT JOIN main.articles a ON a.id = l.article_id WHERE a.id IS NULL").isEmpty else {
                    throw LibraryError.database("\(schema) 存在失效的跨库文章引用")
                }
            }
        }
    }
    func importData(_ data: Data) throws -> ImportReport { try importPackage(PackageValidator.decode(data)) }
    func importBatch(_ files: [Data]) throws -> [ImportReport] {
        let packages = try files.map(PackageValidator.decode)
        return try synchronized { try db.transaction { try packages.map { try importPackage($0) } } }
    }
    // faultAfterWrites is internal, solely for deterministic rollback tests.
    func importPackage(_ package: LearningPackage, faultAfterWrites: Int? = nil) throws -> ImportReport {
        try synchronized {
            try db.transaction {
                let current = try snapshot()
                try PackageValidator.validate(package, existing: current)
                try validateIdentities(package, existing: current)
                let digest = SHA256.hash(data: try JSONCoding.encoder().encode(package)).map { String(format: "%02x", $0) }.joined()
                if let row = try db.rows("SELECT digest, payload FROM main.import_history WHERE package_id = ?", [package.packageId]).first {
                    guard row["digest"] == digest else { throw LibraryError.conflict("同一 package_id 对应不同内容，请使用新 UUID。") }
                    var report = try JSONCoding.decode(ImportReport.self, row["payload"]!)
                    report.alreadyImported = true
                    report.vocabularyAdded = 0; report.questionsAdded = 0; report.writingAdded = 0
                    report.duplicates = package.vocabulary.count + package.questions.count + package.writingExpressions.count
                    return report
                }
                var writes = 0
                func checkpoint() throws {
                    writes += 1
                    if faultAfterWrites == writes { throw LibraryError.database("测试注入的写入失败") }
                }
                var report = ImportReport(packageId: package.packageId, importedAt: Timestamp.now(), vocabularyAdded: 0, questionsAdded: 0, writingAdded: 0, duplicates: 0)
                report.items = []
                func recordItem(_ kind: ImportItem.Kind, _ entityId: String, _ title: String, _ detail: String?, _ outcome: ImportItem.Outcome) {
                    if report.items == nil { report.items = [] }
                    guard report.items!.count < ImportReport.maximumItems else {
                        report.itemsTruncated = true
                        return
                    }
                    report.items!.append(ImportItem(kind: kind, entityId: entityId, title: Self.itemTitle(title),
                                                    detail: detail.map(Self.itemTitle), outcome: outcome))
                }
                for source in package.sources {
                    if !current.sources.contains(where: { $0.id == source.id }) {
                        try db.execute("INSERT INTO main.sources (id,payload) VALUES (?,?)", [source.id, try JSONCoding.string(source)])
                        recordItem(.source, source.id, source.title, source.url, .added)
                        try checkpoint()
                    }
                }
                for var article in package.articles {
                    if !current.articles.contains(where: { $0.id == article.id }) {
                        article.createdAt = article.createdAt ?? report.importedAt
                        try insertArticle(article)
                        recordItem(.article, article.id, article.title, article.kind == .original ? "原始文章" : "改编文章", .added)
                        try checkpoint()
                    }
                }
                for var v in package.vocabulary {
                    let incomingId = v.id
                    let saved = try records(Vocabulary.self, table: "vocab.records")
                    let sameSense = saved.contains {
                        VocabularyGrouping.lemma(for: $0) == VocabularyGrouping.lemma(for: v) &&
                        VocabularySense.key(meaning: $0.meaning, partOfSpeech: $0.partOfSpeech) == VocabularySense.key(meaning: v.meaning, partOfSpeech: v.partOfSpeech)
                    }
                    // Compare the complete authored context, not just spelling and gloss. In
                    // particular, never merge source IDs across records with different sentences.
                    if let identical = saved.first(where: { Self.sameVocabularyContext($0, v) }) {
                        try alias(incomingId, identical.id, table: "vocab.record_aliases")
                        recordItem(.vocabulary, incomingId, identical.expression, identical.meaning, .merged)
                        report.duplicates += 1
                    } else {
                        // A stable incoming ID may already name an older context. Keep that
                        // record unchanged and retain the incoming ID as provenance of this copy.
                        if !(try db.rows("SELECT alias_id FROM vocab.record_aliases WHERE alias_id=?", [incomingId])).isEmpty {
                            v.originId = v.originId ?? incomingId
                            v.id = UUID().uuidString.lowercased()
                        }
                        v.createdAt = v.createdAt ?? report.importedAt
                        v.updatedAt = v.updatedAt ?? v.createdAt
                        try writeVocabulary(v, insert: true)
                        try alias(v.id, v.id, table: "vocab.record_aliases")
                        try alias(incomingId, v.id, table: "vocab.record_aliases")
                        recordItem(.vocabulary, incomingId, v.expression, v.meaning, sameSense ? .contextAdded : .added)
                        if sameSense { report.duplicates += 1 } else { report.vocabularyAdded += 1 }
                    }
                    try checkpoint()
                }
                for var q in package.questions {
                    if let canonical = try canonicalId(table: "main.questions", key: q.dedupKey) {
                        try alias(q.id, canonical, table: "main.question_aliases")
                        recordItem(.question, q.id, q.stem, q.type.title, .merged)
                        report.duplicates += 1
                    } else {
                        q.createdAt = q.createdAt ?? report.importedAt
                        try writeQuestion(q, insert: true)
                        try alias(q.id, q.id, table: "main.question_aliases")
                        recordItem(.question, q.id, q.stem, q.type.title, .added)
                        report.questionsAdded += 1
                    }
                    try checkpoint()
                }
                for var w in package.writingExpressions {
                    if let canonical = try canonicalId(table: "writing.expressions", key: w.dedupKey) {
                        var old = try writing(id: canonical)
                        old.sourceArticleIds = Array(Set(old.sourceArticleIds + w.sourceArticleIds)).sorted()
                        old.topics = Array(Set((old.topics ?? []) + (w.topics ?? []))).sorted()
                        try writeWriting(old, insert: false)
                        recordItem(.writing, w.id, w.expression, w.meaning, .merged)
                        report.duplicates += 1
                    } else {
                        w.createdAt = w.createdAt ?? report.importedAt
                        try writeWriting(w, insert: true)
                        recordItem(.writing, w.id, w.expression, w.meaning, .added)
                        report.writingAdded += 1
                    }
                    let canonical = try canonicalId(table: "writing.expressions", key: w.dedupKey)!
                    try alias(w.id, canonical, table: "writing.aliases"); try checkpoint()
                }
                try db.execute("INSERT INTO main.import_history (package_id,digest,imported_at,payload) VALUES (?,?,?,?)", [package.packageId,digest,report.importedAt,try JSONCoding.string(report)])
                return report
            }
        }
    }
    private static func itemTitle(_ text: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.count <= 120 ? value : String(value.prefix(120)) + "…"
    }
    private static func sameVocabularyContext(_ saved: Vocabulary, _ incoming: Vocabulary) -> Bool {
        if let origin = incoming.originId, origin != saved.originId { return false }
        var value = incoming
        value.id = saved.id
        value.originId = saved.originId
        value.createdAt = value.createdAt ?? saved.createdAt
        value.updatedAt = value.updatedAt ?? saved.updatedAt
        return value == saved
    }
    private func validateIdentities(_ p: LearningPackage, existing: LibrarySnapshot) throws {
        var owners: [String: String] = [:]
        for s in existing.sources { owners[s.id] = "source" }
        for a in existing.articles { owners[a.id] = "article" }
        for (table, kind) in [("vocab.record_aliases","vocabulary"),("main.question_aliases","question"),("writing.aliases","writing")] {
            for row in try db.rows("SELECT alias_id FROM \(table)") { owners[row["alias_id"]!] = kind }
        }
        let incoming = p.sources.map { ($0.id,"source") } + p.articles.map { ($0.id,"article") } + p.vocabulary.map { ($0.id,"vocabulary") } + p.questions.map { ($0.id,"question") } + p.writingExpressions.map { ($0.id,"writing") }
        for (id, kind) in incoming {
            if let owner = owners[id], owner != kind { throw LibraryError.conflict("ID \(id) 已用于其他实体类型") }
        }
        for source in p.sources {
            if let old = existing.sources.first(where: { $0.id == source.id }), old != source { throw LibraryError.conflict("来源 \(source.id) 内容已改变") }
        }
        for var article in p.articles {
            if let old = existing.articles.first(where: { $0.id == article.id }) {
                article.createdAt = article.createdAt ?? old.createdAt
                if old != article { throw LibraryError.conflict("文章 \(article.id) 内容已改变；请编辑已有文章或使用新 ID") }
            }
        }
        func check(_ id: String, _ key: String, _ aliasTable: String, _ table: String) throws {
            if let row = try db.rows("SELECT t.dedup_key FROM \(aliasTable) a JOIN \(table) t ON t.id = a.entity_id WHERE a.alias_id = ?", [id]).first,
               row["dedup_key"] != key { throw LibraryError.conflict("ID \(id) 对应不同内容，未覆盖原记录") }
        }
        for v in p.vocabulary { try check(v.id, v.dedupKey, "vocab.record_aliases", "vocab.records") }
        for q in p.questions { try check(q.id, q.dedupKey, "main.question_aliases", "main.questions") }
        for w in p.writingExpressions { try check(w.id, w.dedupKey, "writing.aliases", "writing.expressions") }
    }
    func canonicalId(table: String, key: String) throws -> String? {
        try db.rows("SELECT id FROM \(table) WHERE dedup_key = ?", [key]).first?["id"]
    }
    private func alias(_ id: String, _ canonical: String, table: String) throws {
        try db.execute("INSERT OR IGNORE INTO \(table) (alias_id,entity_id) VALUES (?,?)", [id,canonical])
    }
    func vocabulary(id: String) throws -> Vocabulary { try record(Vocabulary.self, table: "vocab.records", id: id) }
    func writing(id: String) throws -> WritingExpression { try record(WritingExpression.self, table: "writing.expressions", id: id) }
    func record<T: Decodable>(_ type: T.Type, table: String, id: String) throws -> T {
        try synchronized {
            guard let text = try db.rows("SELECT payload FROM \(table) WHERE id = ?", [id]).first?["payload"] else { throw LibraryError.missing(id) }
            return try JSONCoding.decode(type, text)
        }
    }
    func insertArticle(_ a: Article) throws {
        try db.execute("INSERT INTO main.articles (id,title,body,kind,source_id,original_article_id,payload) VALUES (?,?,?,?,?,?,?)", [a.id,a.title,a.body,a.kind.rawValue,a.sourceId,a.originalArticleId,try JSONCoding.string(a)])
    }
    func writeVocabulary(_ v: Vocabulary, insert: Bool) throws {
        if insert {
            try db.execute("INSERT INTO vocab.records (id,expression,meaning,difficulty,dedup_key,payload) VALUES (?,?,?,?,?,?)", [v.id,v.expression,v.meaning,v.difficulty.map(String.init),v.dedupKey,try JSONCoding.string(v)])
        } else {
            try db.execute("UPDATE vocab.records SET expression=?,meaning=?,difficulty=?,dedup_key=?,payload=? WHERE id=?", [v.expression,v.meaning,v.difficulty.map(String.init),v.dedupKey,try JSONCoding.string(v),v.id])
        }
        try links(schema: "vocab", id: v.id, articles: v.sourceArticleIds, topics: v.topics ?? [])
    }
    func writeWriting(_ w: WritingExpression, insert: Bool) throws {
        if insert {
            try db.execute("INSERT INTO writing.expressions (id,expression,meaning,dedup_key,payload) VALUES (?,?,?,?,?)", [w.id,w.expression,w.meaning,w.dedupKey,try JSONCoding.string(w)])
        } else {
            try db.execute("UPDATE writing.expressions SET expression=?,meaning=?,dedup_key=?,payload=? WHERE id=?", [w.expression,w.meaning,w.dedupKey,try JSONCoding.string(w),w.id])
        }
        try links(schema: "writing", id: w.id, articles: w.sourceArticleIds, topics: w.topics ?? [])
    }
    func writeQuestion(_ q: Question, insert: Bool) throws {
        if insert {
            try db.execute("INSERT INTO main.questions (id,article_id,type,stem,dedup_key,payload) VALUES (?,?,?,?,?,?)", [q.id,q.articleId,q.type.rawValue,q.stem,q.dedupKey,try JSONCoding.string(q)])
        } else {
            try db.execute("UPDATE main.questions SET article_id=?,type=?,stem=?,dedup_key=?,payload=? WHERE id=?", [q.articleId,q.type.rawValue,q.stem,q.dedupKey,try JSONCoding.string(q),q.id])
        }
    }
    private func links(schema: String, id: String, articles: [String], topics: [String]) throws {
        let linkTable = schema == "vocab" ? "record_article_links" : "article_links"
        let topicTable = schema == "vocab" ? "record_topics" : "topics"
        try db.execute("DELETE FROM \(schema).\(linkTable) WHERE entity_id=?", [id])
        for article in Set(articles) { try db.execute("INSERT INTO \(schema).\(linkTable) VALUES (?,?)", [id,article]) }
        try db.execute("DELETE FROM \(schema).\(topicTable) WHERE entity_id=?", [id])
        for topic in Set(topics) { try db.execute("INSERT INTO \(schema).\(topicTable) VALUES (?,?)", [id,topic]) }
    }
}
