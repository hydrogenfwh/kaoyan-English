import Foundation

/// A dictionary entry is a non-destructive presentation of saved context records.
/// Stable storage IDs, provenance, learning state and every sense remain unchanged.
struct VocabularyEntry: Identifiable {
    var id: String { lemma }
    let lemma: String
    let records: [Vocabulary]
    var senses: [VocabularySense] {
        let groups = Dictionary(grouping: records) { record in
            // Exact meaning only. Different wording is never semantically collapsed.
            VocabularySense.key(meaning: record.meaning, partOfSpeech: record.partOfSpeech)
        }
        return groups.keys.sorted().map { key in
            let values = groups[key]!.sorted { $0.id < $1.id }
            return VocabularySense(id: key, meaning: values[0].meaning,
                                   partOfSpeech: VocabularyGrouping.normalizedPartOfSpeech(values[0].partOfSpeech), records: values)
        }
    }
    func isFavorite(_ ids: Set<String>) -> Bool { records.contains { ids.contains($0.id) } }
    var topics: [String] { Array(Set(records.flatMap { $0.topics ?? [] })).sorted() }
    var phonetics: [String] { Array(Set(records.compactMap(\.phonetic).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted() }
}

struct VocabularySense: Identifiable {
    let id: String
    let meaning: String
    let partOfSpeech: String?
    let records: [Vocabulary]
    var englishDefinitions: [String] {
        Array(Set(records.compactMap(\.englishDefinition).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
    }
    static func key(meaning: String, partOfSpeech: String?) -> String {
        let pos = VocabularyGrouping.normalizedPartOfSpeech(partOfSpeech) ?? ""
        // Only whitespace and compatibility differences collapse. Wording, case and
        // punctuation differences remain separate senses until a human edits them.
        let gloss = VocabularyGrouping.normalizedMeaning(meaning)
        return "\(pos.utf8.count):\(pos)\(gloss.utf8.count):\(gloss)"
    }
}

enum VocabularyGrouping {
    /// Offline, reviewed inflections only. No suffix stripping / similarity guessing.
    /// Homographs with multiple possible lemmas (saw, axes, leaves, better, etc.)
    /// are intentionally absent and need an explicit lemma from the imported source/editor.
    private static let inflectionGroups: [String: [String]] = [
        "study": ["studies", "studied", "studying"],
        "learn": ["learns", "learned", "learnt", "learning"],
        "work": ["works", "worked", "working"],
        "play": ["plays", "played", "playing"],
        "develop": ["develops", "developed", "developing"],
        "identify": ["identifies", "identified", "identifying"],
        "communicate": ["communicates", "communicated", "communicating"],
        "reflect": ["reflects", "reflected", "reflecting"],
        "facilitate": ["facilitates", "facilitated", "facilitating"],
        "compromise": ["compromises", "compromised", "compromising"],
        "distinguish": ["distinguishes", "distinguished", "distinguishing"],
        "regain": ["regains", "regained", "regaining"],
        "withstand": ["withstands", "withstood", "withstanding"],
        "run": ["runs", "ran", "running"],
        "walk": ["walks", "walked", "walking"],
        "write": ["writes", "wrote", "written", "writing"],
        "read": ["reads", "reading"],
        "go": ["goes", "went", "gone", "going"],
        "eat": ["eats", "ate", "eaten", "eating"],
        "take": ["takes", "took", "taken", "taking"],
        "make": ["makes", "made", "making"],
        "have": ["has", "had", "having"],
        "use": ["uses", "used", "using"],
        "create": ["creates", "created", "creating"],
        "support": ["supports", "supported", "supporting"],
        "change": ["changes", "changed", "changing"],
        "think": ["thinks", "thinking"],
        "understand": ["understands", "understood", "understanding"],
        "book": ["books", "booked", "booking"],
        "word": ["words", "worded", "wording"],
        "article": ["articles"], "animal": ["animals"], "robot": ["robots"], "dog": ["dogs"],
        "student": ["students"], "teacher": ["teachers"], "question": ["questions", "questioned", "questioning"],
        "expression": ["expressions"], "allegation": ["allegations"],
        "implant": ["implants", "implanted", "implanting"],
        "child": ["children"], "mouse": ["mice"], "tooth": ["teeth"],
        "foot": ["feet"], "man": ["men"], "woman": ["women"],
        "city": ["cities"], "country": ["countries"], "company": ["companies"],
        "technology": ["technologies"], "analysis": ["analyses"],
        "criterion": ["criteria"], "phenomenon": ["phenomena"]
    ]
    private static let inflections: [String: String] = {
        var result: [String: String] = [:]
        for (lemma, forms) in inflectionGroups { for form in forms { result[form] = lemma } }
        return result
    }()
    // Established derivational families only; these are RELATED, never merged.
    private static let families: [[String]] = [
        ["develop", "development", "developer", "developmental"],
        ["educate", "education", "educator", "educational"],
        ["communicate", "communication", "communicative", "communicator"],
        ["create", "creation", "creator", "creative", "creativity"],
        ["govern", "government", "governance", "governor"],
        ["economy", "economic", "economical", "economist", "economics"],
        ["reflect", "reflection", "reflective"],
        ["identify", "identification", "identifiable"],
        ["flexible", "flexibility", "inflexible"],
        ["rigid", "rigidity"], ["allege", "allegation"]
    ]
    static func normalizedMeaning(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    static func normalizedPartOfSpeech(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = TextKey.normalize(value)
        guard !normalized.isEmpty else { return nil }
        switch normalized {
        case "n", "n.", "noun", "名词": return "名词"
        case "v", "v.", "verb", "动词": return "动词"
        case "vt", "vt.", "transitive verb", "及物动词": return "及物动词"
        case "vi", "vi.", "intransitive verb", "不及物动词": return "不及物动词"
        case "adj", "adj.", "adjective", "形容词": return "形容词"
        case "adv", "adv.", "adverb", "副词": return "副词"
        case "phrase", "短语": return "短语"
        default: return normalized
        }
    }
    static func lemma(for record: Vocabulary) -> String {
        if let explicit = record.lemma, !TextKey.normalize(explicit).isEmpty { return TextKey.normalize(explicit) }
        let form = TextKey.normalize(record.expression)
        // An explicit non-verb POS can disambiguate a lexicalized noun/adjective.
        let pos = normalizedPartOfSpeech(record.partOfSpeech)
        if pos == "形容词" || pos == "副词" { return form }
        let isVerb = ["动词", "及物动词", "不及物动词"].contains(pos ?? "")
        if form == "thought", isVerb { return "think" }
        let lexicalizedForms: Set<String> = ["learning", "writing", "reading", "understanding", "distinguished", "used", "working", "running", "booking", "wording"]
        if lexicalizedForms.contains(form), !isVerb { return form }
        if pos == "名词", form.hasSuffix("ing") || form.hasSuffix("ed") { return form }
        return inflections[form] ?? form
    }
    static func entries(_ records: [Vocabulary]) -> [VocabularyEntry] {
        let groups = Dictionary(grouping: records, by: lemma(for:))
        return groups.keys.sorted().map { VocabularyEntry(lemma: $0, records: groups[$0]!.sorted { $0.id < $1.id }) }
    }
    static func related(to entry: VocabularyEntry, in entries: [VocabularyEntry]) -> [VocabularyEntry] {
        func declared(_ e: VocabularyEntry) -> Set<String> {
            Set(e.records.compactMap(\.wordFamily).map(TextKey.normalize).filter { !$0.isEmpty })
        }
        let explicit = declared(entry)
        return entries.filter { other in
            guard other.id != entry.id else { return false }
            return !explicit.intersection(declared(other)).isEmpty || families.contains { $0.contains(entry.lemma) && $0.contains(other.lemma) }
        }.sorted { $0.lemma < $1.lemma }
    }
    static func filteredEntries(_ records: [Vocabulary], search: String = "", topic: String = "", difficulty: Int = 0,
                                favoritesOnly: Bool = false, favoriteIDs: Set<String> = []) -> [VocabularyEntry] {
        let query = TextKey.normalize(search)
        return entries(records).filter { entry in
            // Favorite is a property of the combined entry. Other criteria must match a saved record.
            (!favoritesOnly || entry.isFavorite(favoriteIDs)) && entry.records.contains { record in
                let searchable = [entry.lemma, record.expression, record.meaning, record.englishDefinition ?? ""].joined(separator: " ")
                return (query.isEmpty || TextKey.normalize(searchable).contains(query)) &&
                    (topic.isEmpty || (record.topics ?? []).contains(topic)) && (difficulty == 0 || record.difficulty == difficulty)
            }
        }
    }
}
