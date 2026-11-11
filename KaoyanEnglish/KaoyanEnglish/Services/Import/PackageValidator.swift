import Foundation

enum PackageValidator {
    static let maximumBytes = 20 * 1024 * 1024
    static func decode(_ data: Data) throws -> LearningPackage {
        guard data.count <= maximumBytes else { throw LibraryError.validation(["单个文件不得超过 20 MB。"] ) }
        do { return try JSONCoding.decoder().decode(LearningPackage.self, from: data) }
        catch let error as DecodingError {
            let detail: String
            switch error {
            case .keyNotFound(let key, let context): detail = path(context.codingPath) + "." + key.stringValue + "：缺少必填字段"
            case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context): detail = path(context.codingPath) + "：" + context.debugDescription
            @unknown default: detail = error.localizedDescription
            }
            throw LibraryError.validation([detail])
        }
    }
    private static func path(_ keys: [CodingKey]) -> String { "$" + keys.map { "." + $0.stringValue }.joined() }
    static func validate(_ package: LearningPackage, existing: LibrarySnapshot) throws {
        var issues: [String] = []
        func require(_ condition: Bool, _ text: String) { if !condition { issues.append(text) } }
        func id(_ value: String, _ label: String) {
            require(UUID(uuidString: value)?.uuidString.lowercased() == value, "\(label)：必须是小写 UUID")
        }
        func nonempty(_ value: String, _ label: String) { require(!TextKey.normalize(value).isEmpty, "\(label)：不得为空") }
        func date(_ value: String?, _ label: String) { if let value { require(Timestamp.valid(value), "\(label)：需使用 ISO-8601 时间") } }
        func difficulty(_ value: Int?, _ label: String) { if let value { require((1...5).contains(value), "\(label)：难度范围为 1–5") } }
        func topics(_ values: [String]?, _ label: String) { for v in values ?? [] { nonempty(v, label) } }
        id(package.packageId, "package_id")
        require(package.schemaVersion == "1.0", "不支持 schema_version \(package.schemaVersion)，当前支持 1.0")
        date(package.createdAt, "created_at")
        let entityIds = package.sources.map(\.id) + package.articles.map(\.id) + package.vocabulary.map(\.id) + package.questions.map(\.id) + package.writingExpressions.map(\.id)
        require(entityIds.count <= 50_000, "单个资料包最多包含 50,000 个实体")
        require(Set(entityIds).count == entityIds.count, "资料包内部出现重复实体 ID")
        for value in entityIds { id(value, value) }
        let sourceIds = Set(existing.sources.map(\.id) + package.sources.map(\.id))
        let articleIds = Set(existing.articles.map(\.id) + package.articles.map(\.id))
        var articleMap = Dictionary(uniqueKeysWithValues: existing.articles.map { ($0.id, $0) })
        for a in package.articles { articleMap[a.id] = a }
        for source in package.sources {
            nonempty(source.title, "来源 \(source.id).title")
            if let url = source.url { require(URL(string: url)?.scheme.map { ["http", "https"].contains($0.lowercased()) } == true, "来源 URL 必须为 http 或 https") }
        }
        for a in package.articles {
            nonempty(a.title, "文章 \(a.id).title"); nonempty(a.body, "文章 \(a.id).body"); date(a.createdAt, "文章创建时间")
            if let s = a.sourceId { require(sourceIds.contains(s), "文章 \(a.id) 的来源不存在") }
            if a.kind == .adapted { require(a.originalArticleId != nil, "改编文章 \(a.id) 必须关联原始文章") }
            if let original = a.originalArticleId {
                require(original != a.id && articleMap[original]?.kind == .original, "文章 \(a.id) 必须指向另一篇原始文章")
            }
            if a.kind == .original { require(a.originalArticleId == nil, "原始文章不得设置 original_article_id") }
        }
        func refs(_ ids: [String], _ label: String) {
            require(!ids.isEmpty, "\(label)：至少关联一篇来源文章")
            require(Set(ids).count == ids.count, "\(label)：来源文章 ID 不得重复")
            for value in ids { require(articleIds.contains(value), "\(label)：来源文章 \(value) 不存在") }
        }
        for v in package.vocabulary {
            for (name, value) in [("lemma", v.lemma), ("part_of_speech", v.partOfSpeech), ("word_family", v.wordFamily)] {
                if let value { nonempty(value, "词汇 \(v.id).\(name)") }
            }
            if let origin = v.originId { id(origin, "词汇 origin_id") }

            nonempty(v.expression, "词汇英文"); nonempty(v.meaning, "词汇释义"); refs(v.sourceArticleIds, "词汇 \(v.id)")
            difficulty(v.difficulty, "词汇 \(v.id)"); topics(v.topics, "词汇主题"); date(v.createdAt, "词汇创建时间"); date(v.updatedAt, "词汇更新时间")
        }
        for q in package.questions {
            require(q.provenance == "original_simulation", "题目必须标记为 original_simulation（原创模拟题）")
            require(articleIds.contains(q.articleId), "题目 \(q.id) 的文章不存在")
            nonempty(q.stem, "题干"); nonempty(q.correctAnswer, "正确答案"); nonempty(q.explanation, "答案解析")
            difficulty(q.difficulty, "题目 \(q.id)"); date(q.createdAt, "题目创建时间")
            let options = q.options ?? []
            require(Set(options.map(\.id)).count == options.count, "题目 \(q.id)：选项 ID 重复")
            for o in options { nonempty(o.id, "选项 ID"); nonempty(o.text, "选项内容") }
            if q.type == .readingSingleChoice {
                require(options.count >= 2, "阅读单选题 \(q.id)：至少需要两个选项")
                require(options.contains { $0.id == q.correctAnswer }, "阅读单选题 \(q.id)：正确答案必须对应一个选项 ID")
            }
            for key in q.distractorAnalysis?.keys ?? Dictionary<String,String>().keys {
                require(options.contains { $0.id == key }, "题目 \(q.id)：错误选项分析引用未知选项")
            }
        }
        for w in package.writingExpressions {
            nonempty(w.expression, "写作表达"); nonempty(w.meaning, "表达释义"); refs(w.sourceArticleIds, "表达 \(w.id)")
            topics(w.topics, "写作主题"); date(w.createdAt, "表达创建时间")
        }
        if !issues.isEmpty { throw LibraryError.validation(issues) }
    }
}
