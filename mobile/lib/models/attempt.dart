// mobile/lib/models/attempt.dart
//
// Local-only models to carry a finished quiz attempt to the summary screen.
// We keep this independent of persistence so it compiles now; later we can
// add toCacheMap()/fromCacheMap() when wiring SQLite.
//
// Attempt → a single playthrough
// AnswerRecord → per-question result (selected option, correctness)

class Attempt {
  final String quizId;
  final String title;
  final int totalQuestions;
  final int correctCount;
  final DateTime startedAt;
  final DateTime completedAt;
  final List<AnswerRecord> answers;

  const Attempt({
    required this.quizId,
    required this.title,
    required this.totalQuestions,
    required this.correctCount,
    required this.startedAt,
    required this.completedAt,
    required this.answers,
  });

  int get durationSeconds =>
      completedAt.difference(startedAt).inSeconds.clamp(0, 24 * 3600);

  double get scorePercent =>
      totalQuestions == 0 ? 0 : (correctCount / totalQuestions) * 100.0;
}

class AnswerRecord {
  final String questionId;
  final String questionText;
  final int selectedIndex;
  final int correctIndex;
  final bool isCorrect;

  const AnswerRecord({
    required this.questionId,
    required this.questionText,
    required this.selectedIndex,
    required this.correctIndex,
    required this.isCorrect,
  });
}
