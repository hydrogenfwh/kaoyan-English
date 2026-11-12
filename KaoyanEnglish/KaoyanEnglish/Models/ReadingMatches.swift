import Foundation

struct ReadingMatch: Equatable {
    let range: NSRange
    let vocabularyIDs: [String]
    let writingIDs: [String]
}

enum ReadingMatches {
    /// Longest exact, case-insensitive matches win; no guessed inflection or substring inside words.
    static func find(in text: String, vocabulary: [Vocabulary], writing: [WritingExpression]) -> [ReadingMatch] {
        struct Candidate { let range: NSRange; let vocabularyID: String?; let writingID: String? }
        var candidates: [Candidate] = []
        func add(_ phrase: String, vocabularyID: String? = nil, writingID: String? = nil) {
            let value = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            let escaped = NSRegularExpression.escapedPattern(for: value)
            let pattern = "(?<![\\p{L}\\p{N}_])" + escaped + "(?![\\p{L}\\p{N}_])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                candidates.append(Candidate(range: match.range, vocabularyID: vocabularyID, writingID: writingID))
            }
        }
        for word in vocabulary { add(word.expression, vocabularyID: word.id) }
        for expression in writing { add(expression.expression, writingID: expression.id) }
        candidates.sort { $0.range.location != $1.range.location ? $0.range.location < $1.range.location : $0.range.length > $1.range.length }
        var results: [ReadingMatch] = []
        for c in candidates {
            if let index = results.indices.last, results[index].range == c.range {
                let existing = results[index]
                results[index] = ReadingMatch(range: existing.range,
                    vocabularyIDs: Array(Set(existing.vocabularyIDs + (c.vocabularyID.map { [$0] } ?? []))).sorted(),
                    writingIDs: Array(Set(existing.writingIDs + (c.writingID.map { [$0] } ?? []))).sorted())
            } else if let last = results.last, NSMaxRange(last.range) > c.range.location {
                continue
            } else {
                results.append(ReadingMatch(range: c.range, vocabularyIDs: c.vocabularyID.map { [$0] } ?? [], writingIDs: c.writingID.map { [$0] } ?? []))
            }
        }
        return results
    }
}
