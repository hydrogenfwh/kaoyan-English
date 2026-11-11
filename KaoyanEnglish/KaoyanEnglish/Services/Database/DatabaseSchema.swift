import Foundation

enum DatabaseSchema {
    static let version = 2
    static let files = [("main", "questions.sqlite"), ("vocab", "vocabulary.sqlite"), ("writing", "writing.sqlite")]
    static func migrate(_ db: SQLiteConnection) throws {
        for (schema, _) in files {
            let current = Int(try db.rows("PRAGMA \(schema).user_version").first?["user_version"] ?? "0") ?? 0
            guard current <= version else { throw LibraryError.database("\(schema) 的版本高于本应用，已停止打开。") }
            // Future migrations must be explicit, ordered and transactional; never drop unknown tables.
        }
        let vocabularyVersion = Int(try db.rows("PRAGMA vocab.user_version").first?["user_version"] ?? "0") ?? 0
        try db.transaction {
            try db.execute("CREATE TABLE IF NOT EXISTS main.sources (id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
            try db.execute("CREATE TABLE IF NOT EXISTS main.articles (id TEXT PRIMARY KEY, title TEXT NOT NULL, body TEXT NOT NULL, kind TEXT NOT NULL, source_id TEXT REFERENCES sources(id), original_article_id TEXT REFERENCES articles(id) DEFERRABLE INITIALLY DEFERRED, payload TEXT NOT NULL)")
            try db.execute("CREATE TABLE IF NOT EXISTS main.questions (id TEXT PRIMARY KEY, article_id TEXT NOT NULL REFERENCES articles(id), type TEXT NOT NULL, stem TEXT NOT NULL, dedup_key TEXT NOT NULL UNIQUE, payload TEXT NOT NULL)")
            try db.execute("CREATE TABLE IF NOT EXISTS main.question_aliases (alias_id TEXT PRIMARY KEY, entity_id TEXT NOT NULL REFERENCES questions(id) ON DELETE CASCADE)")
            try db.execute("CREATE TABLE IF NOT EXISTS main.import_history (package_id TEXT PRIMARY KEY, digest TEXT NOT NULL, imported_at TEXT NOT NULL, payload TEXT NOT NULL)")
            try db.execute("CREATE TABLE IF NOT EXISTS main.attempts (id TEXT PRIMARY KEY, question_id TEXT NOT NULL REFERENCES questions(id) ON DELETE CASCADE, payload TEXT NOT NULL)")
            for (schema, table) in [("vocab", "vocabulary"), ("writing", "expressions")] {
                try db.execute("CREATE TABLE IF NOT EXISTS \(schema).\(table) (id TEXT PRIMARY KEY, expression TEXT NOT NULL, meaning TEXT NOT NULL, difficulty INTEGER, dedup_key TEXT NOT NULL UNIQUE, favorite INTEGER NOT NULL DEFAULT 0 CHECK (favorite IN (0,1)), payload TEXT NOT NULL)")
                try db.execute("CREATE TABLE IF NOT EXISTS \(schema).aliases (alias_id TEXT PRIMARY KEY, entity_id TEXT NOT NULL REFERENCES \(table)(id) ON DELETE CASCADE)")
                try db.execute("CREATE TABLE IF NOT EXISTS \(schema).article_links (entity_id TEXT NOT NULL REFERENCES \(table)(id) ON DELETE CASCADE, article_id TEXT NOT NULL, PRIMARY KEY(entity_id, article_id))")
                try db.execute("CREATE TABLE IF NOT EXISTS \(schema).topics (entity_id TEXT NOT NULL REFERENCES \(table)(id) ON DELETE CASCADE, topic TEXT NOT NULL, PRIMARY KEY(entity_id, topic))")
                try db.execute("CREATE INDEX IF NOT EXISTS \(schema).topic_lookup ON topics(topic)")
                try db.execute("CREATE INDEX IF NOT EXISTS \(schema).article_lookup ON article_links(article_id)")
            }
            try db.execute("CREATE INDEX IF NOT EXISTS main.question_article ON questions(article_id)")
            // Version 2 retains the original tables as a migration archive. No learning rows
            // are dropped; new context records may share a semantic key without losing evidence.
            try db.execute("CREATE TABLE IF NOT EXISTS vocab.records (id TEXT PRIMARY KEY, expression TEXT NOT NULL, meaning TEXT NOT NULL, difficulty INTEGER, dedup_key TEXT NOT NULL, favorite INTEGER NOT NULL DEFAULT 0 CHECK (favorite IN (0,1)), payload TEXT NOT NULL)")
            try db.execute("CREATE TABLE IF NOT EXISTS vocab.record_aliases (alias_id TEXT PRIMARY KEY, entity_id TEXT NOT NULL REFERENCES records(id) ON DELETE CASCADE)")
            try db.execute("CREATE TABLE IF NOT EXISTS vocab.record_article_links (entity_id TEXT NOT NULL REFERENCES records(id) ON DELETE CASCADE, article_id TEXT NOT NULL, PRIMARY KEY(entity_id, article_id))")
            try db.execute("CREATE TABLE IF NOT EXISTS vocab.record_topics (entity_id TEXT NOT NULL REFERENCES records(id) ON DELETE CASCADE, topic TEXT NOT NULL, PRIMARY KEY(entity_id, topic))")
            try db.execute("CREATE INDEX IF NOT EXISTS vocab.record_key_lookup ON records(dedup_key)")
            try db.execute("CREATE INDEX IF NOT EXISTS vocab.record_topic_lookup ON record_topics(topic)")
            try db.execute("CREATE INDEX IF NOT EXISTS vocab.record_article_lookup ON record_article_links(article_id)")
            if vocabularyVersion < 2 {
                try db.execute("INSERT INTO vocab.records SELECT * FROM vocab.vocabulary")
                try db.execute("INSERT INTO vocab.record_aliases SELECT * FROM vocab.aliases")
                try db.execute("INSERT INTO vocab.record_article_links SELECT * FROM vocab.article_links")
                try db.execute("INSERT INTO vocab.record_topics SELECT * FROM vocab.topics")
            }
            for (schema, _) in files { try db.execute("PRAGMA \(schema).user_version = \(version)") }
        }
    }
}
