// mobile/lib/pages/quiz_player_page.dart
//
// Quiz Player with play loop (Day 10):
//  - Accepts quizId, title, difficulty via constructor
//  - On load: best-effort Firestore fetch → always read from cache
//  - Renders states: loading / error / empty / ready
//  - Shows question view with selectable options, instant feedback, Next/Finish
//  - Tracks per-question answers (in-memory) and navigates to Summary screen
//  - Analytics: quiz_started (on questions ready), question_answered, quiz_completed
//
// Dependencies: FirestoreService, CacheRepository, SnackbarHelper, FirebaseService,
// and the Question, Attempt models.

import 'package:flutter/material.dart';

import '../models/question.dart';
import '../models/attempt.dart';
import '../services/firestore_service.dart';
import '../services/cache_repository.dart';
import '../services/firebase_service.dart';
import '../widgets/snackbar_helper.dart';
import '../widgets/option_tile.dart';
import 'quiz_summary_page.dart';

class QuizPlayerPage extends StatefulWidget {
  final String quizId;
  final String title;
  final String difficulty;

  const QuizPlayerPage({
    super.key,
    required this.quizId,
    required this.title,
    required this.difficulty,
  });

  @override
  State<QuizPlayerPage> createState() => _QuizPlayerPageState();
}

class _QuizPlayerPageState extends State<QuizPlayerPage> {
  bool _loading = true;
  String? _error;
  List<Question> _questions = const [];
  int _currentIndex = 0;
  bool _loggedStarted = false;

  // Day 10 state:
  int? _selectedIndex;     // index selected for current question
  bool _showFeedback = false;
  final List<AnswerRecord> _answers = [];
  late DateTime _startedAt;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _loadQuestions(firstLoad: true);
  }

  Future<void> _loadQuestions({bool firstLoad = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // 1) Try to fetch from server (best effort)
    final outcome = await FirestoreService.fetchQuestionsByQuizId(widget.quizId);

    // 2) Always read from cache
    final raw = await CacheRepository.getQuestionsByQuizId(widget.quizId);
    final parsed = raw.map((m) => Question.fromCacheMap(m)).toList();

    if (!mounted) return;
    setState(() {
      _questions = parsed;
      _currentIndex = 0;
      _selectedIndex = null;
      _showFeedback = false;
      _answers.clear();
      _loading = false;
      _error = (outcome.status == FetchStatus.error && parsed.isEmpty)
          ? (outcome.errorMessage ?? 'Failed to load questions')
          : null;
    });

    // Feedback snackbars and analytics
    if (outcome.status == FetchStatus.successFromServer) {
      if (!firstLoad) {
        SnackbarHelper.showInfo(context, 'Questions updated from server.');
      }
    } else if (outcome.status == FetchStatus.error) {
      if (parsed.isNotEmpty) {
        SnackbarHelper.showInfo(context, 'Showing cached questions.');
      } else {
        SnackbarHelper.showError(context, 'Couldn’t load questions.');
      }
    }

    // Log quiz_started once when we have at least one question
    if (!_loggedStarted && _questions.isNotEmpty) {
      _loggedStarted = true;
      await FirebaseService.I.logQuizStarted(
        quizId: widget.quizId,
        title: widget.title,
      );
    }
  }

  void _onOptionTap(int optionIndex) {
    if (_showFeedback) return; // already answered this question
    final q = _questions[_currentIndex];
    final isCorrect = optionIndex == q.correctIndex;

    setState(() {
      _selectedIndex = optionIndex;
      _showFeedback = true;
    });

    // Analytics per question
    FirebaseService.I.logQuestionAnswered(
      quizId: widget.quizId,
      questionId: q.id,
      isCorrect: isCorrect,
      selectedIndex: optionIndex,
    );

    // Record the answer to build Attempt later
    _answers.add(AnswerRecord(
      questionId: q.id,
      questionText: q.text,
      selectedIndex: optionIndex,
      correctIndex: q.correctIndex,
      isCorrect: isCorrect,
    ));
  }

  void _nextQuestion() {
    if (_questions.isEmpty) return;

    // Require an answer before moving on
    if (_selectedIndex == null) {
      SnackbarHelper.showInfo(context, 'Please select an option to continue.');
      return;
    }

    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex += 1;
        _selectedIndex = null;
        _showFeedback = false;
      });
    } else {
      _finishQuiz();
    }
  }

  void _finishQuiz() {
    final completedAt = DateTime.now();
    final total = _questions.length;
    final correct = _answers.where((a) => a.isCorrect).length;

    // Log completion analytics
    FirebaseService.I.logQuizCompleted(
      quizId: widget.quizId,
      title: widget.title,
      score: correct,
      total: total,
    );

    // Build the Attempt and navigate to Summary
    final attempt = Attempt(
      quizId: widget.quizId,
      title: widget.title,
      totalQuestions: total,
      correctCount: correct,
      startedAt: _startedAt,
      completedAt: completedAt,
      answers: List<AnswerRecord>.from(_answers),
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuizSummaryPage(attempt: attempt),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final difficultyChip = Chip(
      label: Text(widget.difficulty.toUpperCase()),
      visualDensity: VisualDensity.compact,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [Padding(padding: const EdgeInsets.only(right: 8), child: difficultyChip)],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _questions.isEmpty) {
      return _ErrorState(
        message: _error!,
        onRetry: () => _loadQuestions(),
      );
    }

    if (_questions.isEmpty) {
      return _EmptyState(
        onRetry: () => _loadQuestions(),
      );
    }

    final q = _questions[_currentIndex];
    final canAdvance = _selectedIndex != null;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          _ProgressHeader(
            current: _currentIndex + 1,
            total: _questions.length,
          ),
          const SizedBox(height: 12),
          _QuestionCard(
            question: q,
            selectedIndex: _selectedIndex,
            showFeedback: _showFeedback,
            onTapOption: _onOptionTap,
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: canAdvance ? _nextQuestion : null,
                  icon: Icon(_currentIndex < _questions.length - 1 ? Icons.arrow_forward : Icons.flag),
                  label: Text(_currentIndex < _questions.length - 1 ? 'Next' : 'Finish'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  final int current;
  final int total;
  const _ProgressHeader({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Question $current of $total', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 12),
        Expanded(
          child: LinearProgressIndicator(
            value: total > 0 ? current / total : 0,
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final Question question;
  final int? selectedIndex;
  final bool showFeedback;
  final void Function(int index) onTapOption;

  const _QuestionCard({
    required this.question,
    required this.selectedIndex,
    required this.showFeedback,
    required this.onTapOption,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            question.text.isEmpty ? 'Untitled question' : question.text,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (question.imageUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                question.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          ..._buildOptions(context, question),
        ]),
      ),
    );
  }

  List<Widget> _buildOptions(BuildContext context, Question q) {
    if (q.options.isEmpty) {
      return const [
        Text(
          'No options available.',
          style: TextStyle(color: Colors.grey),
        ),
      ];
    }

    return List<Widget>.generate(q.options.length, (i) {
      final text = q.options[i];
      final isSelected = selectedIndex == i;
      final isCorrect = q.correctIndex == i;
      return OptionTile(
        text: text,
        isSelected: isSelected,
        isCorrect: isCorrect,
        showFeedback: showFeedback,
        onTap: () => onTapOption(i),
      );
    });
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onRetry;
  const _EmptyState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('No questions yet for this quiz.', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ]),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(message, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ]),
    );
  }
}
