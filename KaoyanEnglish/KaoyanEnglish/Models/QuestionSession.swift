import Foundation

struct QuestionSession {
    private let question: Question
    private(set) var submitted = false
    var selectedAnswer = ""
    init(question: Question) { self.question = question }
    var canSubmit: Bool {
        !submitted && (question.type == .readingSingleChoice
            ? (question.options ?? []).contains { $0.id == selectedAnswer }
            : !TextKey.normalize(selectedAnswer).isEmpty)
    }
    var revealedAnswer: String? { submitted ? question.correctAnswer : nil }
    var revealedExplanation: String? { submitted ? question.explanation : nil }
    var revealedEvidence: String? { submitted ? question.evidence : nil }
    var revealedDistractors: [String: String]? { submitted ? question.distractorAnalysis : nil }
    func makeAttempt() throws -> AnswerAttempt {
        guard canSubmit else { throw LibraryError.validation(["请先作答，且每轮只能提交一次"]) }
        return AnswerAttempt(id: UUID().uuidString.lowercased(), questionId: question.id, answer: selectedAnswer,
                             isCorrect: question.type == .readingSingleChoice ? selectedAnswer == question.correctAnswer : nil, submittedAt: Timestamp.now())
    }
    // Called only after durable storage succeeds; a failed write must not reveal answers.
    mutating func markSubmitted() { submitted = true }
    mutating func reset() { submitted = false; selectedAnswer = "" }
}
