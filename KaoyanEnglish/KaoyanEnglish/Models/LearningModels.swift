import Foundation

struct LearningPackage: Codable, Equatable {
    var schemaVersion: String = "1.0"
    var packageId: String
    var createdAt: String
    var sources: [Source]
    var articles: [Article]
    var vocabulary: [Vocabulary]
    var questions: [Question]
    var writingExpressions: [WritingExpression]
}

struct Source: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var url: String? = nil
    var note: String? = nil
}

struct Article: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var body: String
    var kind: ArticleKind
    var sourceId: String? = nil
    var originalArticleId: String? = nil
    var theme: String? = nil
    var createdAt: String? = nil
}

enum ArticleKind: String, Codable, CaseIterable { case original, adapted }

struct Vocabulary: Codable, Identifiable, Equatable {
    var id: String
    var expression: String
    var meaning: String
    var sourceArticleIds: [String]
    var lemma: String? = nil
    var partOfSpeech: String? = nil
    var wordFamily: String? = nil
    var originId: String? = nil
    var phonetic: String? = nil
    var englishDefinition: String? = nil
    var originalSentence: String? = nil
    var sentenceTranslation: String? = nil
    var collocations: [String]? = nil
    var uncommonMeaning: String? = nil
    var difficulty: Int? = nil
    var topics: [String]? = nil
    var writingValue: String? = nil
    var createdAt: String? = nil
    var updatedAt: String? = nil
    var dedupKey: String { TextKey.pair(expression, meaning) }
}

enum QuestionType: String, Codable, CaseIterable, Identifiable {
    case readingSingleChoice = "reading_single_choice"
    case cloze, sevenChooseFive = "seven_choose_five", ordering, headingMatch = "heading_match"
    case translation, practicalWriting = "practical_writing", essayWriting = "essay_writing"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .readingSingleChoice: return "阅读理解"
        case .cloze: return "完形填空"
        case .sevenChooseFive: return "七选五"
        case .ordering: return "排序"
        case .headingMatch: return "标题匹配"
        case .translation: return "英译汉"
        case .practicalWriting: return "应用文写作"
        case .essayWriting: return "文章写作"
        }
    }
}
struct QuestionOption: Codable, Equatable, Identifiable {
    var id: String
    var text: String
}
struct Question: Codable, Identifiable, Equatable {
    var id: String
    var articleId: String
    var type: QuestionType
    var stem: String
    var correctAnswer: String
    var explanation: String
    var provenance: String = "original_simulation"
    var options: [QuestionOption]? = nil
    var evidence: String? = nil
    var distractorAnalysis: [String: String]? = nil
    var testedSkill: String? = nil
    var difficulty: Int? = nil
    var createdAt: String? = nil
    // Display provenance is fixed by the application, never trusted from imported text.
    var provenanceLabel: String { "原创模拟题" }
    var dedupKey: String { TextKey.pair(articleId + ":" + type.rawValue, stem) }
}
struct WritingExpression: Codable, Identifiable, Equatable {
    var id: String
    var expression: String
    var meaning: String
    var sourceArticleIds: [String]
    var topics: [String]? = nil
    var expressionType: String? = nil
    var context: String? = nil
    var originalSentence: String? = nil
    var essaySentence: String? = nil
    var translation: String? = nil
    var alternatives: [String]? = nil
    var usageNotes: String? = nil
    var createdAt: String? = nil
    var dedupKey: String { TextKey.pair(expression, meaning) }
}
struct ImportItem: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case source, article, vocabulary, question, writing
        var label: String {
            switch self {
            case .source: return "来源"
            case .article: return "文章"
            case .vocabulary: return "词汇"
            case .question: return "题目"
            case .writing: return "写作表达"
            }
        }
    }
    enum Outcome: String, Codable {
        case added, merged, contextAdded
        var label: String {
            switch self {
            case .added: return "新增"
            case .merged: return "合并"
            case .contextAdded: return "新增语境记录"
            }
        }
    }
    var kind: Kind
    var entityId: String
    var title: String
    var detail: String? = nil
    var outcome: Outcome
    var id: String { kind.rawValue + ":" + entityId }
}
struct ImportReport: Codable, Identifiable, Equatable {
    static let maximumItems = 200
    var id: String { packageId }
    var packageId: String
    var importedAt: String
    var vocabularyAdded: Int
    var questionsAdded: Int
    var writingAdded: Int
    var duplicates: Int
    var failed: Int = 0
    var alreadyImported: Bool = false
    // New reports save a bounded item list. Older reports decode with nil and are shown as unavailable.
    var items: [ImportItem]? = nil
    var itemsTruncated: Bool? = nil
}
struct AnswerAttempt: Codable, Identifiable, Equatable {
    var id: String
    var questionId: String
    var answer: String
    var isCorrect: Bool?
    var submittedAt: String
}
struct LibrarySnapshot {
    var sources: [Source] = []
    var articles: [Article] = []
    var vocabulary: [Vocabulary] = []
    var questions: [Question] = []
    var writing: [WritingExpression] = []
    var favoriteVocabulary: Set<String> = []
    var favoriteWriting: Set<String> = []
    var history: [ImportReport] = []
    var attempts: [AnswerAttempt] = []
}

enum DefaultTopics {
    static let all = ["科技与人工智能", "教育与人才培养", "环境保护与可持续发展", "社会发展与公共治理", "文化与人文", "经济与就业", "全球化与国际关系", "健康与生活方式", "个人成长与心理素质", "媒体与信息传播"]
}
