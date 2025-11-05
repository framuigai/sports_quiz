import 'package:flutter/material.dart';

import '../services/http_service.dart';
import '../services/firestore_service.dart';
import '../services/firebase_service.dart';
import '../widgets/snackbar_helper.dart';
import 'quiz_player_page.dart';

/// UI form to generate an AI quiz:
///  - Topic (text)
///  - Difficulty (easy/medium/hard)
///  - Number of Questions (1..20)
/// On success:
///  1) Calls backend /ai/generate_quiz (mode = 'user')
///  2) FirestoreService.fetchQuizById(quiz_id)  -> caches quiz in user_quizzes
///  3) FirestoreService.fetchQuestionsByQuizId(quiz_id, isAdmin: false) -> caches questions
///  4) Offer to open immediately in the Player OR return to My Quizzes.
class GenerateQuizPage extends StatefulWidget {
  const GenerateQuizPage({super.key});

  @override
  State<GenerateQuizPage> createState() => _GenerateQuizPageState();
}

class _GenerateQuizPageState extends State<GenerateQuizPage> {
  final _formKey = GlobalKey<FormState>();

  final _topicCtrl = TextEditingController();
  String _difficulty = 'medium';
  int _numQuestions = 8;

  bool _submitting = false;

  @override
  void dispose() {
    _topicCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    try {
      final uid = FirebaseService.I.currentUser?.uid ?? '';
      // Call backend to generate a USER quiz (not admin).
      final payload = {
        'topic': _topicCtrl.text.trim(),
        'difficulty': _difficulty,
        'num_questions': _numQuestions,
        'mode': 'user',
        if (uid.isNotEmpty) 'owner_id': uid, // backend may ignore, but harmless
      };

      final resp = await HttpService.postJson('/ai/generate_quiz', payload);
      final quizId = (resp?['quiz_id'] ?? '').toString();

      if (quizId.isEmpty) {
        throw Exception('Server did not return quiz_id.');
      }

      // Pull the created quiz & questions from Firestore → cache locally
      final q1 = await FirestoreService.fetchQuizById(quizId);
      if (q1.status == FetchStatus.error) {
        throw Exception(q1.errorMessage ?? 'Failed to fetch quiz by id');
      }

      final q2 = await FirestoreService.fetchQuestionsByQuizId(
        quizId,
        isAdmin: false,
      );
      if (q2.status == FetchStatus.error) {
        throw Exception(q2.errorMessage ?? 'Failed to fetch quiz questions');
      }

      if (!mounted) return;

      // Offer options: open now vs. return to My Quizzes
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Quiz Ready'),
          content: Text(
              'Your quiz has been created successfully.\n\nID: $quizId\n\nOpen now or find it under "My Quizzes".'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // close dialog
                Navigator.of(context).pop(true); // close page, signal refresh
              },
              child: const Text('My Quizzes'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop(); // close dialog
                // Go straight to player
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => QuizPlayerPage(
                      quizId: quizId,
                      title: _topicCtrl.text.trim().isEmpty
                          ? 'My AI Quiz'
                          : _topicCtrl.text.trim(),
                      difficulty: _difficulty,
                      isAdmin: false,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play Now'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      SnackbarHelper.showError(context, 'Failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        !_submitting && _topicCtrl.text.trim().isNotEmpty && _numQuestions > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Generate AI Quiz'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          onChanged: () => setState(() {}),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _topicCtrl,
                decoration: const InputDecoration(
                  labelText: 'Topic',
                  hintText: 'e.g., Premier League History',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Please enter a topic';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _difficulty,
                      decoration: const InputDecoration(
                        labelText: 'Difficulty',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'easy', child: Text('Easy')),
                        DropdownMenuItem(value: 'medium', child: Text('Medium')),
                        DropdownMenuItem(value: 'hard', child: Text('Hard')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _difficulty = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: _numQuestions.toString(),
                      decoration: const InputDecoration(
                        labelText: 'Number of Questions (1-20)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n < 1 || n > 20) {
                          return 'Enter 1..20';
                        }
                        return null;
                      },
                      onChanged: (v) {
                        final n = int.tryParse(v);
                        if (n != null) setState(() => _numQuestions = n);
                      },
                    ),
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: canSubmit ? _submit : null,
                  icon: _submitting
                      ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.auto_awesome),
                  label: Text(_submitting ? 'Generating…' : 'Generate'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
