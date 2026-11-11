import Foundation

enum EntityKind { case vocabulary, writing, question, article, source }

extension LibraryStore {
    private func validateEdit(vocabulary: [Vocabulary] = [], writing: [WritingExpression] = [], articles: [Article] = [], questions: [Question] = []) throws {
        let p = LearningPackage(packageId: UUID().uuidString.lowercased(), createdAt: Timestamp.now(), sources: [], articles: articles, vocabulary: vocabulary, questions: questions, writingExpressions: writing)
        try PackageValidator.validate(p, existing: snapshot())
    }
    func updateVocabulary(_ value: Vocabulary) throws {
        try synchronized {
            try db.transaction {
                let old = try vocabulary(id: value.id)
                var value = value; value.createdAt = old.createdAt; value.updatedAt = Timestamp.now()
                try validateEdit(vocabulary: [value]); try writeVocabulary(value, insert: false)
            }
        }
    }
    func updateWriting(_ value: WritingExpression) throws {
        try synchronized {
            try db.transaction {
                let old = try writing(id: value.id)
                var value = value; value.createdAt = old.createdAt
                try validateEdit(writing: [value]); try writeWriting(value, insert: false)
            }
        }
    }
    func updateArticle(_ value: Article) throws {
        try synchronized {
            try db.transaction {
                let old = try record(Article.self, table: "main.articles", id: value.id)
                var value = value; value.createdAt = old.createdAt
                try validateEdit(articles: [value])
                let adaptations = try db.rows("SELECT id FROM main.articles WHERE original_article_id=?", [value.id])
                if value.kind != .original && !adaptations.isEmpty {
                    throw LibraryError.conflict("已有改编文章引用此原始文章，不能改变其类型")
                }
                try db.execute("UPDATE main.articles SET title=?,body=?,kind=?,source_id=?,original_article_id=?,payload=? WHERE id=?", [value.title,value.body,value.kind.rawValue,value.sourceId,value.originalArticleId,try JSONCoding.string(value),value.id])
            }
        }
    }
    func updateQuestion(_ value: Question) throws {
        try synchronized {
            try db.transaction {
                let old = try record(Question.self, table: "main.questions", id: value.id)
                var value = value; value.createdAt = old.createdAt
                try validateEdit(questions: [value])
                // Past attempts retain their original answer and correctness; editing does not rewrite history.
                try writeQuestion(value, insert: false)
            }
        }
    }
    func setVocabularyFavorites(ids: [String], favorite: Bool) throws {
        try synchronized {
            try db.transaction {
                for id in Set(ids) { try setFavorite(id: id, kind: .vocabulary, favorite: favorite) }
            }
        }
    }
    func setFavorite(id: String, kind: EntityKind, favorite: Bool) throws {
        try synchronized {
            let table: String
            switch kind {
            case .vocabulary: table = "vocab.records"
            case .writing: table = "writing.expressions"
            default: throw LibraryError.conflict("此类型不支持收藏")
            }
            guard !(try db.rows("SELECT id FROM \(table) WHERE id=?", [id])).isEmpty else { throw LibraryError.missing(id) }
            try db.execute("UPDATE \(table) SET favorite=? WHERE id=?", [favorite ? "1" : "0",id])
        }
    }
    func delete(id: String, kind: EntityKind) throws {
        try synchronized {
            try db.transaction {
                let table: String
                switch kind {
                case .vocabulary: table = "vocab.records"
                case .writing: table = "writing.expressions"
                case .question: table = "main.questions"
                case .source: table = "main.sources"
                case .article:
                    table = "main.articles"
                    for schema in ["vocab", "writing"] {
                let linkTable = schema == "vocab" ? "record_article_links" : "article_links"
                        guard try db.rows("SELECT entity_id FROM \(schema).\(linkTable) WHERE article_id=? LIMIT 1", [id]).isEmpty else {
                            throw LibraryError.conflict("文章仍被词汇或写作表达引用，请先调整关联")
                        }
                    }
                }
                try db.execute("DELETE FROM \(table) WHERE id=?", [id])
            }
        }
    }
    func saveAttempt(_ attempt: AnswerAttempt) throws {
        try synchronized {
            let question = try record(Question.self, table: "main.questions", id: attempt.questionId)
            guard UUID(uuidString: attempt.id) != nil, !TextKey.normalize(attempt.answer).isEmpty else { throw LibraryError.validation(["答题记录无效"]) }
            if question.type == .readingSingleChoice {
                guard question.options?.contains(where: { $0.id == attempt.answer }) == true else { throw LibraryError.validation(["请选择有效选项"]) }
            }
            var attempt = attempt
            attempt.isCorrect = question.type == .readingSingleChoice ? attempt.answer == question.correctAnswer : nil
            try db.execute("INSERT INTO main.attempts (id,question_id,payload) VALUES (?,?,?)", [attempt.id,attempt.questionId,try JSONCoding.string(attempt)])
        }
    }
    func exportJSON() throws -> Data {
        try synchronized {
            let state = try snapshot()
            let package = LearningPackage(packageId: UUID().uuidString.lowercased(), createdAt: Timestamp.now(), sources: state.sources, articles: state.articles, vocabulary: state.vocabulary, questions: state.questions, writingExpressions: state.writing)
            return try JSONCoding.encoder().encode(package)
        }
    }
}
