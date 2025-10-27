// lib/services/firestore_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'cache_repository.dart';

enum FetchStatus { successFromServer, error }

class FetchOutcome {
  final FetchStatus status;
  final int fetchedCount;
  final String? errorMessage;
  const FetchOutcome.success(this.fetchedCount)
      : status = FetchStatus.successFromServer,
        errorMessage = null;
  const FetchOutcome.error(this.errorMessage)
      : status = FetchStatus.error,
        fetchedCount = 0;
}

class FirestoreService {
  static final _db = FirebaseFirestore.instance;

  /// Fetch global/admin quizzes and persist to local cache.
  static Future<FetchOutcome> fetchGlobalQuizzes() async {
    try {
      final qInt = _db
          .collection('quizzes')
          .where('is_admin_quiz', isEqualTo: true)
          .where('available_to_all', isEqualTo: true)
          .where('is_approved', isEqualTo: true)
          .where('deleted', isEqualTo: 0);
      final qBool = _db
          .collection('quizzes')
          .where('is_admin_quiz', isEqualTo: true)
          .where('available_to_all', isEqualTo: true)
          .where('is_approved', isEqualTo: true)
          .where('deleted', isEqualTo: false);

      final results = await Future.wait([qInt.get(), qBool.get()]);
      final seen = <String>{};
      final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final snap in results) {
        for (final d in snap.docs) {
          if (seen.add(d.id)) allDocs.add(d);
        }
      }

      for (var doc in allDocs) {
        final data = doc.data();
        final quiz = {
          'quiz_id': doc.id,
          'title': data['title'] ?? 'Untitled Quiz',
          'description': data['description'] ?? '',
          'difficulty': (data['difficulty'] ?? 'medium').toString(),
          'tags': data['tags'] is List
              ? (data['tags'] as List).join(',')
              : (data['tags']?.toString() ?? ''),
          'is_admin_quiz': 1,
          'available_to_all': data['available_to_all'] == true ? 1 : 0,
          'is_approved': data['is_approved'] == true ? 1 : 0,
          'deleted': 0,
          'deleted_at': null,
          'created_at': data['created_at']?.toString() ??
              DateTime.now().toIso8601String(),
          'updated_at': data['updated_at']?.toString() ??
              DateTime.now().toIso8601String(),
        };
        await CacheRepository.saveAdminQuiz(quiz);
      }
      return FetchOutcome.success(allDocs.length);
    } catch (e) {
      return FetchOutcome.error(e.toString());
    }
  }

  // 🧩 NEW: Fetch questions by quizId for the Player screen.
  static Future<FetchOutcome> fetchQuestionsByQuizId(String quizId) async {
    try {
      final query = await _db
          .collection('quizzes')
          .doc(quizId)
          .collection('questions')
          .get();

      final questions = query.docs.map((d) {
        final q = d.data();
        return {
          'question_id': d.id,
          'quiz_id': quizId,
          'index': q['index'] ?? 0,
          'text': q['text'] ?? '',
          'options': q['options'] is List
              ? (q['options'] as List).join('|')
              : q['options']?.toString() ?? '',
          'correct_index': q['correct_index'] ?? 0,
          'image_url': q['image_url'] ?? '',
          'created_at': q['created_at']?.toString() ??
              DateTime.now().toIso8601String(),
          'updated_at': q['updated_at']?.toString() ??
              DateTime.now().toIso8601String(),
        };
      }).toList();

      await CacheRepository.saveAdminQuestions(questions);
      return FetchOutcome.success(questions.length);
    } catch (e) {
      return FetchOutcome.error('Error fetching questions: $e');
    }
  }
}
