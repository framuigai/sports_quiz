import 'package:cloud_firestore/cloud_firestore.dart';
import 'cache_repository.dart';

class FirestoreService {
  static final _db = FirebaseFirestore.instance;

  static Future<void> fetchGlobalQuizzes() async {
    try {
      final snapshot = await _db
          .collection('quizzes')
          .where('is_admin_quiz', isEqualTo: true)
          .where('available_to_all', isEqualTo: true)
          .where('is_approved', isEqualTo: true)
          .where('deleted', isEqualTo: false)
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final quiz = {
          'quiz_id': doc.id,
          'title': data['title'] ?? 'Untitled Quiz',
          'description': data['description'] ?? '',
          'difficulty': data['difficulty'] ?? 'medium',
          'tags': (data['tags'] is List ? (data['tags'] as List).join(',') : ''),
          'is_admin_quiz': 1,
          'available_to_all': (data['available_to_all'] == true) ? 1 : 0,
          'is_approved': (data['is_approved'] == true) ? 1 : 0,
          'deleted': 0,
          'deleted_at': null,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        };
        await CacheRepository.saveAdminQuiz(quiz);
      }
      // success path just returns
    } catch (e) {
      // Swallow — the UI will fallback to cache
      // You can log with Firebase Crashlytics later
      // print('Firestore fetch failed: $e');
    }
  }
}
