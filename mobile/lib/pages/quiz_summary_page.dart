// mobile/lib/pages/quiz_summary_page.dart
//
// Summary screen shown after finishing a quiz:
//  - Displays score, correct/total, duration
//  - Lists each question with your answer vs correct answer
//  - Actions: Play Again (reload Player) and Back to Quizzes
//
// Analytics:
//  - Calls logQuizSummaryViewed() on appear
//
// Persistence:
//  - Not saving to SQLite yet; we will add in Day 11 persistence step.

import 'package:flutter/material.dart';
import '../models/attempt.dart';
import '../services/firebase_service.dart';

class QuizSummaryPage extends StatefulWidget {
  final Attempt attempt;

  const QuizSummaryPage({super.key, required this.attempt});

  @override
  State<QuizSummaryPage> createState() => _QuizSummaryPageState();
}

class _QuizSummaryPageState extends State<QuizSummaryPage> {
  @override
  void initState() {
    super.initState();
    FirebaseService.I.logQuizSummaryViewed(quizId: widget.attempt.quizId);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.attempt;
    final percent = a.scorePercent.toStringAsFixed(0);

    return Scaffold(
      appBar: AppBar(
        title: Text('${a.title} — Summary'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _ScoreCard(
              score: a.correctCount,
              total: a.totalQuestions,
              durationSeconds: a.durationSeconds,
              percent: percent,
            ),
            const SizedBox(height: 16),
            Expanded(child: _AnswersList(answers: a.answers)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // Back to quizzes list
                      Navigator.of(context).popUntil((r) => r.isFirst);
                    },
                    icon: const Icon(Icons.list),
                    label: const Text('Back to Quizzes'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      // Play again → go back one (summary) then push new Player
                      Navigator.of(context).pop(); // close summary
                      // The caller (Player) can decide whether to auto-reload.
                      // Alternatively, you can pass a callback via Navigator if needed.
                    },
                    icon: const Icon(Icons.replay),
                    label: const Text('Play Again'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final int score;
  final int total;
  final int durationSeconds;
  final String percent;

  const _ScoreCard({
    required this.score,
    required this.total,
    required this.durationSeconds,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    final mins = (durationSeconds ~/ 60);
    final secs = (durationSeconds % 60);

    return Card(
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              child: Text(
                '$percent%',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Score: $score / $total',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('Time: ${mins}m ${secs}s',
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnswersList extends StatelessWidget {
  final List<AnswerRecord> answers;
  const _AnswersList({required this.answers});

  @override
  Widget build(BuildContext context) {
    if (answers.isEmpty) {
      return const Center(child: Text('No answers recorded.'));
    }

    return ListView.separated(
      itemCount: answers.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final a = answers[i];
        final isCorrect = a.isCorrect;
        final yours = a.selectedIndex;
        final correct = a.correctIndex;

        return ListTile(
          title: Text(a.questionText.isEmpty ? 'Untitled question' : a.questionText),
          subtitle: Text(
            'Your answer: ${_letter(yours)}   •   Correct: ${_letter(correct)}',
          ),
          trailing: Icon(
            isCorrect ? Icons.check_circle : Icons.cancel,
            color: isCorrect ? Colors.green : Colors.red,
          ),
        );
      },
    );
  }

  String _letter(int idx) {
    switch (idx) {
      case 0:
        return 'A';
      case 1:
        return 'B';
      case 2:
        return 'C';
      case 3:
        return 'D';
      default:
        return '-';
    }
  }
}
